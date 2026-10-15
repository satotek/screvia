import AppKit
import CoreGraphics

/// Draws annotations. The canvas and the exported image both go through
/// here, so what the user sees while editing is what gets saved, and a new
/// tool is written once.
nonisolated enum AnnotationRenderer {
    /// Draws into a context with a top-left origin, where the image occupies
    /// `imageRect`. `pointScale` is context units per image point, which turns
    /// sizes given in image points into context units.
    ///
    /// `filteredRegion` is the blurred or pixelated region for a redaction
    /// tool. Without it the region gets a cheap sketch, which the canvas
    /// shows while a filter is pending.
    static func draw(
        _ annotation: Annotation,
        in context: CGContext,
        imageRect: CGRect,
        pointScale: CGFloat,
        filteredRegion: CGImage? = nil,
        stepNumber: Int = 1
    ) {
        let style = annotation.style
        let rect = AnnotationSpace.rect(annotation.bounds, in: imageRect)

        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(style.color.cgColor)
        context.setLineWidth(style.lineWidth * pointScale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if style.hasShadow, annotation.tool.usesShadow {
            // No offset: the shadow's offset ignores the context's flip, so
            // any offset would point different ways on screen and in export.
            context.setShadow(
                offset: .zero,
                blur: 6 * pointScale,
                color: CGColor(gray: 0, alpha: 0.55)
            )
        }

        switch annotation.tool {
        case .select, .crop:
            break
        case .rectangle:
            if let fill = style.fillColor {
                context.setFillColor(fill.cgColor)
                context.fill(rect)
            }
            context.stroke(rect)
        case .ellipse:
            if let fill = style.fillColor {
                context.setFillColor(fill.cgColor)
                context.fillEllipse(in: rect)
            }
            context.strokeEllipse(in: rect)
        case .highlight:
            context.setFillColor(CGColor(srgbRed: 1, green: 0.84, blue: 0, alpha: 0.35))
            context.fill(rect)
        case .text:
            drawText(annotation.text ?? "", style: style, in: rect, context: context, pointScale: pointScale)
        case .step:
            drawStep(stepNumber, style: style, in: rect, context: context)
        case .blur, .pixelate:
            if let filteredRegion {
                drawImage(filteredRegion, in: rect, context: context)
            } else {
                drawRedactionSketch(for: annotation.tool, in: rect, context: context, pointScale: pointScale)
            }
        case .line:
            context.move(to: AnnotationSpace.point(annotation.start, in: imageRect))
            context.addLine(to: AnnotationSpace.point(annotation.end, in: imageRect))
            context.strokePath()
        case .freehand:
            let stroke = annotation.points.map { AnnotationSpace.point($0, in: imageRect) }
            guard let first = stroke.first else {
                break
            }
            context.move(to: first)
            // A lone point still shows, as a dot the width of the line.
            context.addLines(between: stroke.count == 1 ? [first, first] : stroke)
            context.strokePath()
        case .arrow:
            let start = AnnotationSpace.point(annotation.start, in: imageRect)
            let end = AnnotationSpace.point(annotation.end, in: imageRect)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let wingLength = (10 + style.lineWidth) * pointScale

            context.move(to: start)
            context.addLine(to: end)
            for wing in [angle - .pi / 6, angle + .pi / 6] {
                context.move(to: CGPoint(
                    x: end.x - wingLength * cos(wing),
                    y: end.y - wingLength * sin(wing)
                ))
                context.addLine(to: end)
            }
            context.strokePath()
        }
    }

    /// Draws a document's annotations in order, numbering the steps.
    static func draw(
        _ annotations: [Annotation],
        in context: CGContext,
        imageRect: CGRect,
        pointScale: CGFloat,
        filteredRegion: (Annotation) -> CGImage?
    ) {
        let stepNumbers = Annotation.stepNumbers(in: annotations)
        for annotation in annotations {
            draw(
                annotation,
                in: context,
                imageRect: imageRect,
                pointScale: pointScale,
                filteredRegion: filteredRegion(annotation),
                stepNumber: stepNumbers[annotation.id] ?? 1
            )
        }
    }

    // MARK: - Sizing

    /// The annotation with its box fitted to its content, for the tools sized
    /// by font rather than by dragging. The top-left corner stays put.
    static func fitted(_ annotation: Annotation, imageSize: CGSize) -> Annotation {
        guard annotation.tool.isSizedByFont, imageSize.width > 0, imageSize.height > 0 else {
            return annotation
        }

        let size: CGSize
        if annotation.tool == .step {
            let diameter = stepDiameter(for: annotation.style)
            size = CGSize(width: diameter, height: diameter)
        } else {
            size = textBoxSize(annotation.text ?? "", style: annotation.style)
        }

        var fitted = annotation
        let origin = annotation.bounds.origin
        fitted.start = origin
        fitted.end = CGPoint(
            x: origin.x + size.width / imageSize.width,
            y: origin.y + size.height / imageSize.height
        )
        return fitted
    }

    static func stepDiameter(for style: AnnotationStyle) -> CGFloat {
        style.fontSize * 1.6
    }

    /// In image points. Empty text is measured as a few characters' width,
    /// so a new text box has room for the caret.
    static func textBoxSize(_ text: String, style: AnnotationStyle) -> CGSize {
        let measured = (text.isEmpty ? "MMMM" : text as NSString)
            .size(withAttributes: [.font: font(for: style, pointScale: 1)])
        let padding = textPadding(for: style)
        return CGSize(
            width: ceil(measured.width) + padding.width * 2,
            height: ceil(measured.height) + padding.height * 2
        )
    }

    static func font(for style: AnnotationStyle, pointScale: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: style.fontSize * pointScale, weight: style.isBold ? .bold : .regular)
    }

    private static func textPadding(for style: AnnotationStyle) -> CGSize {
        CGSize(width: style.fontSize * 0.45, height: style.fontSize * 0.2)
    }

    // MARK: - Export

    /// The document burnt into the image and cropped, at the image's full
    /// pixel size.
    static func flatten(_ image: NSImage, document: AnnotationDocument) -> NSImage {
        let crop = document.crop.intersection(AnnotationSpace.unit)
        guard
            !document.annotations.isEmpty || crop != AnnotationSpace.unit,
            let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            image.size.width > 0, !crop.isEmpty
        else {
            return image
        }

        let colorSpace = source.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: source.width,
            height: source.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        let canvas = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        context.draw(source, in: canvas)
        // Annotation space has a top-left origin, like the canvas view.
        context.translateBy(x: 0, y: canvas.height)
        context.scaleBy(x: 1, y: -1)

        draw(
            document.annotations,
            in: context,
            imageRect: canvas,
            pointScale: canvas.width / image.size.width,
            filteredRegion: { annotation in
                annotation.tool.filterName.flatMap { filterName in
                    filteredRegion(
                        of: source,
                        in: AnnotationSpace.rect(annotation.bounds, in: canvas),
                        filterName: filterName
                    )
                }
            }
        )

        // CGImage cropping, like annotation space, counts from the top.
        guard
            let flattened = context.makeImage(),
            let output = flattened.cropping(to: AnnotationSpace.rect(crop, in: canvas).integral)
        else {
            return image
        }
        return NSImage(
            cgImage: output,
            size: NSSize(
                width: image.size.width * CGFloat(output.width) / canvas.width,
                height: image.size.height * CGFloat(output.height) / canvas.height
            )
        )
    }

    // MARK: - Pieces

    private static func drawText(
        _ text: String,
        style: AnnotationStyle,
        in rect: CGRect,
        context: CGContext,
        pointScale: CGFloat
    ) {
        if style.textAppearance == .background {
            let radius = style.fontSize * 0.3 * pointScale
            context.setFillColor(style.fillColor?.cgColor ?? CGColor(gray: 0, alpha: 0.62))
            context.addPath(CGPath(
                roundedRect: rect,
                cornerWidth: min(radius, rect.width / 2),
                cornerHeight: min(radius, rect.height / 2),
                transform: nil
            ))
            context.fillPath()
            // The box carries the shadow; text on it does not need one too.
            context.setShadow(offset: .zero, blur: 0, color: nil)
        }

        guard !text.isEmpty else {
            return
        }

        let font = font(for: style, pointScale: pointScale)
        let padding = textPadding(for: style)
        let origin = CGPoint(x: rect.minX + padding.width * pointScale, y: rect.minY + padding.height * pointScale)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        if style.textAppearance == .outline {
            // A positive stroke width strokes without filling; drawn first
            // and wide, the fill on top leaves only the outside of it.
            (text as NSString).draw(at: origin, withAttributes: [
                .font: font,
                .strokeColor: NSColor(cgColor: style.color.contrasting.cgColor) ?? .black,
                .strokeWidth: 12
            ])
        }
        (text as NSString).draw(at: origin, withAttributes: [
            .font: font,
            .foregroundColor: NSColor(cgColor: style.color.cgColor) ?? .white
        ])
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawStep(_ number: Int, style: AnnotationStyle, in rect: CGRect, context: CGContext) {
        let diameter = min(rect.width, rect.height)
        let circle = CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)
        context.setFillColor(style.color.cgColor)
        context.fillEllipse(in: circle)
        context.setShadow(offset: .zero, blur: 0, color: nil)

        let label = "\(number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: diameter * 0.55, weight: .bold),
            .foregroundColor: NSColor(cgColor: style.color.contrasting.cgColor) ?? .white
        ]
        let size = label.size(withAttributes: attributes)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        label.draw(at: CGPoint(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// `draw(_:in:)` assumes a bottom-left origin; flip locally so the image
    /// lands upright in a top-left context.
    private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    private static func drawRedactionSketch(
        for tool: AnnotationTool,
        in rect: CGRect,
        context: CGContext,
        pointScale: CGFloat
    ) {
        context.clip(to: rect)
        if tool == .blur {
            context.setFillColor(CGColor(gray: 0, alpha: 0.28))
            context.fill(rect)
            let step = 9 * pointScale
            context.setFillColor(CGColor(gray: 1, alpha: 0.08))
            for x in stride(from: rect.minX, to: rect.maxX, by: step) {
                context.fill(CGRect(x: x, y: rect.minY, width: step / 2, height: rect.height))
            }
        } else {
            let step = 12 * pointScale
            context.setFillColor(CGColor(gray: 1, alpha: 0.22))
            for (column, x) in stride(from: rect.minX, to: rect.maxX, by: step).enumerated() {
                for (row, y) in stride(from: rect.minY, to: rect.maxY, by: step).enumerated()
                where (column + row).isMultiple(of: 2) {
                    context.fill(CGRect(x: x, y: y, width: step, height: step))
                }
            }
        }
    }
}
