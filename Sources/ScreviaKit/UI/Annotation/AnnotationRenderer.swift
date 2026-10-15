import AppKit
import CoreGraphics

/// Draws annotations. The canvas and the exported image both go through
/// here, so what the user sees while editing is what gets saved, and a new
/// tool is written once.
nonisolated enum AnnotationRenderer {
    /// Draws into a context with a top-left origin, where the image occupies
    /// `imageRect`. `pointScale` is context units per image point, which turns
    /// line widths given in image points into context units.
    ///
    /// `filteredRegion` is the blurred or pixelated region for a redaction
    /// tool. Without it the region gets a cheap sketch, which the canvas
    /// shows while a filter is pending.
    static func draw(
        _ annotation: Annotation,
        in context: CGContext,
        imageRect: CGRect,
        pointScale: CGFloat,
        filteredRegion: CGImage? = nil
    ) {
        let rect = AnnotationSpace.rect(annotation.bounds, in: imageRect)
        let lineWidth = annotation.style.lineWidth * pointScale

        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(annotation.style.color)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.tool {
        case .select:
            break
        case .rectangle:
            context.stroke(rect)
        case .ellipse:
            context.strokeEllipse(in: rect)
        case .highlight:
            context.setFillColor(CGColor(srgbRed: 1, green: 0.84, blue: 0, alpha: 0.35))
            context.fill(rect)
        case .text:
            drawText(annotation.text ?? "", in: rect, context: context, pointScale: pointScale)
        case .blur, .pixelate:
            if let filteredRegion {
                drawImage(filteredRegion, in: rect, context: context)
            } else {
                drawRedactionSketch(for: annotation.tool, in: rect, context: context, pointScale: pointScale)
            }
        case .arrow:
            let start = AnnotationSpace.point(annotation.start, in: imageRect)
            let end = AnnotationSpace.point(annotation.end, in: imageRect)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let wingLength = (10 + annotation.style.lineWidth) * pointScale

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

    /// The image with `annotations` burnt in, at the image's full pixel size.
    static func flatten(_ image: NSImage, annotations: [Annotation]) -> NSImage {
        guard
            !annotations.isEmpty,
            let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            image.size.width > 0
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

        let pointScale = canvas.width / image.size.width
        for annotation in annotations {
            let filtered = annotation.tool.filterName.flatMap { filterName in
                filteredRegion(
                    of: source,
                    in: AnnotationSpace.rect(annotation.bounds, in: canvas),
                    filterName: filterName
                )
            }
            draw(annotation, in: context, imageRect: canvas, pointScale: pointScale, filteredRegion: filtered)
        }

        guard let output = context.makeImage() else {
            return image
        }
        return NSImage(cgImage: output, size: image.size)
    }

    private static func drawText(_ text: String, in rect: CGRect, context: CGContext, pointScale: CGFloat) {
        let radius = 7 * pointScale
        context.setFillColor(CGColor(gray: 0, alpha: 0.62))
        context.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: min(radius, rect.width / 2),
            cornerHeight: min(radius, rect.height / 2),
            transform: nil
        ))
        context.fillPath()

        guard !text.isEmpty else {
            return
        }

        // Sized by the box's height in image points, so it scales with the
        // image rather than with the window.
        let fontSize = max(13, min(34, rect.height / pointScale * 0.52)) * pointScale
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        (text as NSString).draw(
            in: rect.insetBy(dx: 9 * pointScale, dy: 5 * pointScale),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        )
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
