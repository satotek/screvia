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
    /// `filteredRegion` is what a tool that samples the image shows of it:
    /// the blurred or pixelated region, or the magnifier's enlargement.
    /// Without it the region gets a cheap sketch, which the canvas shows while
    /// one is pending.
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
        case .select, .crop, .liveText:
            break
        case .rectangle:
            let radius = min(style.cornerRadius * pointScale, rect.width / 2, rect.height / 2)
            let box = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            if let fill = style.fillColor {
                context.setFillColor(fill.cgColor)
                context.addPath(box)
                context.fillPath()
            }
            context.addPath(box)
            context.strokePath()
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
            drawText(
                annotation.text ?? "",
                style: style,
                wraps: annotation.textWidth != nil,
                in: rect,
                context: context,
                pointScale: pointScale
            )
        case .balloon:
            drawBalloon(
                annotation.text ?? "",
                style: style,
                in: rect,
                tail: annotation.tail.map { AnnotationSpace.point($0, in: imageRect) },
                context: context,
                pointScale: pointScale
            )
        case .image:
            if let picture = picture(for: annotation) {
                // Through a transparency layer, so the picture casts the
                // shadow as one shape rather than by its transparent box.
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                drawImage(picture, in: rect, context: context)
                context.endTransparencyLayer()
            } else {
                context.setFillColor(CGColor(gray: 0.5, alpha: 0.3))
                context.fill(rect)
            }
        case .magnifier:
            if annotation.isMagnifyingElsewhere {
                drawMagnifiedArea(
                    AnnotationSpace.rect(annotation.sampledArea, in: imageRect),
                    shape: style.magnifierShape,
                    joinedTo: rect,
                    context: context
                )
            }
            drawMagnifier(filteredRegion, shape: style.magnifierShape, in: rect, context: context)
        case .step:
            drawStep(style.stepFormat.label(stepNumber), style: style, in: rect, context: context)
        case .blur, .pixelate:
            if let filteredRegion {
                drawImage(filteredRegion, in: rect, context: context)
            } else {
                drawRedactionSketch(for: annotation.tool, in: rect, context: context, pointScale: pointScale)
            }
        case .line, .arrow:
            drawLine(annotation, in: context, imageRect: imageRect, pointScale: pointScale)
        case .freehand:
            let stroke = annotation.points.map { AnnotationSpace.point($0, in: imageRect) }
            guard let first = stroke.first else {
                break
            }
            context.move(to: first)
            // A lone point still shows, as a dot the width of the line.
            context.addLines(between: stroke.count == 1 ? [first, first] : stroke)
            context.strokePath()
        }
    }

    /// A line or arrow, straight or bent through its `bend`, with heads
    /// pointing along the curve where it ends.
    private static func drawLine(
        _ annotation: Annotation,
        in context: CGContext,
        imageRect: CGRect,
        pointScale: CGFloat
    ) {
        let style = annotation.style
        let start = AnnotationSpace.point(annotation.start, in: imageRect)
        let end = AnnotationSpace.point(annotation.end, in: imageRect)
        let control = annotation.bendControl.map { AnnotationSpace.point($0, in: imageRect) }
        let headLength = (10 + style.lineWidth) * pointScale

        var heads: [(tip: CGPoint, from: CGPoint)] = []
        if annotation.tool == .arrow {
            heads.append((end, control ?? start))
            if style.arrowBothEnds {
                heads.append((start, control ?? end))
            }
        }

        // A filled head covers the line's end, which would otherwise poke
        // out past its tip as a round cap.
        func trimmed(_ tip: CGPoint, from: CGPoint) -> CGPoint {
            guard style.arrowHead == .filled, heads.contains(where: { $0.tip == tip }) else {
                return tip
            }
            let length = hypot(tip.x - from.x, tip.y - from.y)
            guard length > 0 else {
                return tip
            }
            let back = min(headLength * 0.6, length / 2) / length
            return CGPoint(x: tip.x - (tip.x - from.x) * back, y: tip.y - (tip.y - from.y) * back)
        }

        let lineStart = trimmed(start, from: control ?? end)
        let lineEnd = trimmed(end, from: control ?? start)
        context.move(to: lineStart)
        if let control {
            context.addQuadCurve(to: lineEnd, control: control)
        } else {
            context.addLine(to: lineEnd)
        }

        for head in heads {
            let angle = atan2(head.tip.y - head.from.y, head.tip.x - head.from.x)
            let wings = [angle - .pi / 6, angle + .pi / 6].map { wing in
                CGPoint(x: head.tip.x - headLength * cos(wing), y: head.tip.y - headLength * sin(wing))
            }
            switch style.arrowHead {
            case .open:
                for wing in wings {
                    context.move(to: wing)
                    context.addLine(to: head.tip)
                }
            case .filled:
                break
            }
        }
        context.strokePath()

        guard style.arrowHead == .filled else {
            return
        }
        context.setFillColor(style.color.cgColor)
        for head in heads {
            let angle = atan2(head.tip.y - head.from.y, head.tip.x - head.from.x)
            context.move(to: head.tip)
            for wing in [angle - .pi / 6, angle + .pi / 6] {
                context.addLine(to: CGPoint(x: head.tip.x - headLength * cos(wing), y: head.tip.y - headLength * sin(wing)))
            }
            context.closePath()
        }
        context.fillPath()
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

    // MARK: - Inserted pictures

    // Decoding PNG on every frame of a drag would stutter, so decoded
    // pictures are kept, by the annotation and the size of its data.
    // NSCache is thread-safe; the box only tells the compiler so.
    private final class PictureCache: @unchecked Sendable {
        let cache = NSCache<NSString, CGImage>()
    }

    private static let pictures = PictureCache()

    static func picture(for annotation: Annotation) -> CGImage? {
        guard let data = annotation.imageData else {
            return nil
        }
        let key = "\(annotation.id.uuidString)#\(data.count)" as NSString
        if let cached = pictures.cache.object(forKey: key) {
            return cached
        }
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let picture = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        pictures.cache.setObject(picture, forKey: key)
        return picture
    }

    // MARK: - Sizing

    /// The annotation with its box fitted to its content, for the tools sized
    /// by font rather than by dragging. The top-left corner stays put.
    /// A round magnifier, as when its shape is switched to round, becomes
    /// the largest circle inside its box.
    static func fitted(_ annotation: Annotation, imageSize: CGSize) -> Annotation {
        if annotation.tool == .magnifier, annotation.style.magnifierShape == .circle,
           imageSize.width > 0, imageSize.height > 0 {
            let box = annotation.bounds
            let side = min(box.width * imageSize.width, box.height * imageSize.height)
            var fitted = annotation
            fitted.start = CGPoint(x: box.midX - side / imageSize.width / 2, y: box.midY - side / imageSize.height / 2)
            fitted.end = CGPoint(x: box.midX + side / imageSize.width / 2, y: box.midY + side / imageSize.height / 2)
            return fitted
        }
        guard annotation.tool.isSizedByFont, imageSize.width > 0, imageSize.height > 0 else {
            return annotation
        }

        let size: CGSize
        if annotation.tool == .step {
            let diameter = stepDiameter(for: annotation.style)
            size = CGSize(width: diameter, height: diameter)
        } else {
            size = textBoxSize(annotation.text ?? "", style: annotation.style, width: annotation.textWidth)
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
    ///
    /// With a `width`, the text wraps to it and the box grows downwards.
    static func textBoxSize(_ text: String, style: AnnotationStyle, width: CGFloat? = nil) -> CGSize {
        let padding = textPadding(for: style)
        let attributes: [NSAttributedString.Key: Any] = [.font: font(for: style, pointScale: 1)]
        if let width {
            let measured = (text.isEmpty ? "M" : text as NSString).boundingRect(
                with: CGSize(width: max(width - padding.width * 2, 1), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            )
            // A little over the measured height: lines laid out at the
            // export's scale come out slightly taller than measured here.
            return CGSize(width: width, height: ceil(measured.height + style.fontSize * 0.15) + padding.height * 2)
        }
        let measured = (text.isEmpty ? "MMMM" : text as NSString).size(withAttributes: attributes)
        return CGSize(
            width: ceil(measured.width) + padding.width * 2,
            height: ceil(measured.height) + padding.height * 2
        )
    }

    static func font(for style: AnnotationStyle, pointScale: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: style.fontSize * pointScale, weight: style.isBold ? .bold : .regular)
        guard
            style.fontDesign != .standard,
            let descriptor = system.fontDescriptor.withDesign(style.fontDesign.systemDesign)
        else {
            return system
        }
        return NSFont(descriptor: descriptor, size: system.pointSize) ?? system
    }

    private static func textPadding(for style: AnnotationStyle) -> CGSize {
        CGSize(width: style.fontSize * 0.45, height: style.fontSize * 0.2)
    }

    // MARK: - Export

    /// The document burnt into the image and cropped, at the image's full
    /// pixel size.
    ///
    /// `image` is the original as captured; the document's orientation turns
    /// it first, since annotation space is the turned image.
    static func flatten(_ image: NSImage, document: AnnotationDocument) -> NSImage {
        let image = document.orientation.applied(to: image)
        let crop = document.crop.intersection(AnnotationSpace.unit)
        guard
            !document.annotations.isEmpty || crop != AnnotationSpace.unit || !document.effects.isEmpty
                || document.outputScale != 1,
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
                annotation.tool.samplesImage
                    ? sampledRegion(for: annotation.tool, of: source, in: AnnotationSpace.rect(annotation.sampledArea, in: canvas))
                    : nil
            }
        )

        // CGImage cropping, like annotation space, counts from the top.
        let pixelsPerPoint = canvas.width / image.size.width
        guard
            let flattened = context.makeImage(),
            let cropped = flattened.cropping(to: AnnotationSpace.rect(crop, in: canvas).integral),
            let framed = applying(document.effects, to: cropped, pixelsPerPoint: pixelsPerPoint, colorSpace: colorSpace),
            let output = scaled(framed, by: document.outputScale, colorSpace: colorSpace)
        else {
            return image
        }
        // Resize changes the points as well as the pixels, so a halved
        // image is half the size wherever it is pasted.
        return NSImage(
            cgImage: output,
            size: NSSize(
                width: CGFloat(output.width) / pixelsPerPoint,
                height: CGFloat(output.height) / pixelsPerPoint
            )
        )
    }

    private static func scaled(_ image: CGImage, by scale: CGFloat, colorSpace: CGColorSpace) -> CGImage? {
        guard scale > 0, scale != 1 else {
            return image
        }
        let width = max(Int((CGFloat(image.width) * scale).rounded()), 1)
        let height = max(Int((CGFloat(image.height) * scale).rounded()), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// The image framed by `effects`: its border, then room for the shadow
    /// around that. The image itself is untouched, so the crop and the
    /// annotations keep their pixels.
    static func applying(
        _ effects: ImageEffects,
        to image: CGImage,
        pixelsPerPoint: CGFloat,
        colorSpace: CGColorSpace
    ) -> CGImage? {
        guard !effects.isEmpty else {
            return image
        }

        let padding = (effects.margin * pixelsPerPoint).rounded()
        let border = (effects.borderThickness * pixelsPerPoint).rounded()
        let margin = effects.hasShadow ? (ImageEffects.shadowMargin * pixelsPerPoint).rounded() : 0
        let framed = CGRect(
            x: margin,
            y: margin,
            width: CGFloat(image.width) + (padding + border) * 2,
            height: CGFloat(image.height) + (padding + border) * 2
        )
        guard let context = CGContext(
            data: nil,
            width: Int(framed.width + margin * 2),
            height: Int(framed.height + margin * 2),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // A bottom-left origin here, so a negative offset drops the shadow.
        if effects.hasShadow {
            context.setShadow(
                offset: CGSize(width: 0, height: -ImageEffects.shadowDrop * pixelsPerPoint),
                blur: ImageEffects.shadowBlur * pixelsPerPoint,
                color: CGColor(gray: 0, alpha: 0.35)
            )
        }
        // Under the image even without a border, as what casts the shadow.
        let marginColor = effects.marginColor?.cgColor ?? CGColor(gray: 0, alpha: 0)
        if effects.borderColor != nil || effects.hasShadow {
            context.setFillColor(effects.borderColor?.cgColor ?? marginColor)
            context.fill(framed)
        }
        context.setShadow(offset: .zero, blur: 0, color: nil)
        let inner = framed.insetBy(dx: border, dy: border)
        if padding > 0 {
            context.clear(inner)
            context.setFillColor(marginColor)
            context.fill(inner)
        }
        context.draw(image, in: inner.insetBy(dx: padding, dy: padding))
        return context.makeImage()
    }

    // MARK: - Pieces

    private static func drawText(
        _ text: String,
        style: AnnotationStyle,
        wraps: Bool,
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

        drawLabel(
            text,
            style: style,
            outlined: style.textAppearance == .outline,
            wraps: wraps,
            in: rect,
            context: context,
            pointScale: pointScale
        )
    }

    /// The text of a text box or balloon, at the padding the box was sized
    /// with.
    private static func drawLabel(
        _ text: String,
        style: AnnotationStyle,
        outlined: Bool,
        wraps: Bool = false,
        in rect: CGRect,
        context: CGContext,
        pointScale: CGFloat
    ) {
        guard !text.isEmpty else {
            return
        }

        let font = font(for: style, pointScale: pointScale)
        let padding = textPadding(for: style)
        let inner = rect.insetBy(dx: padding.width * pointScale, dy: padding.height * pointScale)

        func draw(_ attributes: [NSAttributedString.Key: Any]) {
            if wraps {
                // Unbounded below: the box was measured at one point per
                // point, and line heights round differently at the export's
                // scale, which could leave the last line out.
                let column = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: .greatestFiniteMagnitude)
                (text as NSString).draw(with: column, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
            } else {
                (text as NSString).draw(at: inner.origin, withAttributes: attributes)
            }
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        if outlined {
            // A positive stroke width strokes without filling; drawn first
            // and wide, the fill on top leaves only the outside of it.
            draw([
                .font: font,
                .strokeColor: NSColor(cgColor: style.color.contrasting.cgColor) ?? .black,
                .strokeWidth: 12
            ])
        }
        draw([
            .font: font,
            .foregroundColor: NSColor(cgColor: style.color.cgColor) ?? .white
        ])
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A rounded box with a tail pointing at `tail`, outlined and its text
    /// in the stroke colour, on the fill colour or white. Box and tail are
    /// one outline, so no seam shows where they meet.
    private static func drawBalloon(
        _ text: String,
        style: AnnotationStyle,
        in rect: CGRect,
        tail: CGPoint?,
        context: CGContext,
        pointScale: CGFloat
    ) {
        context.addPath(balloonOutline(around: rect, pointingAt: tail, cornerRadius: style.fontSize * 0.5 * pointScale))
        context.setFillColor((style.fillColor ?? .white).cgColor)
        context.drawPath(using: .fillStroke)
        context.setShadow(offset: .zero, blur: 0, color: nil)
        drawLabel(text, style: style, outlined: false, in: rect, context: context, pointScale: pointScale)
    }

    static func balloonOutline(around rect: CGRect, pointingAt tip: CGPoint?, cornerRadius: CGFloat) -> CGPath {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        let body = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        // A tip inside the box would turn the tail inside out.
        guard let tip, !rect.contains(tip) else {
            return body
        }

        // The tail's base crosses the middle of the box, square to the tip,
        // so the box hides it and only the part outside shows.
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let across = atan2(tip.y - center.y, tip.x - center.x) + .pi / 2
        let halfBase = min(rect.width, rect.height) * 0.45
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: center.x + halfBase * cos(across), y: center.y + halfBase * sin(across)))
        tail.addLine(to: tip)
        tail.addLine(to: CGPoint(x: center.x - halfBase * cos(across), y: center.y - halfBase * sin(across)))
        tail.closeSubpath()
        return body.union(tail)
    }

    private static func magnifierPath(_ shape: MagnifierShape, in rect: CGRect) -> CGPath {
        switch shape {
        case .rectangle: CGPath(rect: rect, transform: nil)
        case .circle: CGPath(ellipseIn: rect, transform: nil)
        }
    }

    /// Marks what a magnifier placed elsewhere enlarges, with a line to the
    /// magnifier. Drawn first, so the magnifier covers the line's far end.
    private static func drawMagnifiedArea(
        _ area: CGRect,
        shape: MagnifierShape,
        joinedTo lens: CGRect,
        context: CGContext
    ) {
        let from = CGPoint(x: area.midX, y: area.midY)
        let to = CGPoint(x: lens.midX, y: lens.midY)
        let dx = to.x - from.x
        let dy = to.y - from.y
        // Leave the area at its outline, so the line does not cross what it
        // marks: where the ray meets the box, or the ellipse.
        let exit: CGFloat
        switch shape {
        case .rectangle:
            exit = min(
                dx == 0 ? .infinity : area.width / 2 / abs(dx),
                dy == 0 ? .infinity : area.height / 2 / abs(dy)
            )
        case .circle:
            let a = dx / (area.width / 2)
            let b = dy / (area.height / 2)
            exit = 1 / max(hypot(a, b), .ulpOfOne)
        }

        context.saveGState()
        context.setLineDash(phase: 0, lengths: [])
        if exit < 1 {
            context.move(to: CGPoint(x: from.x + dx * exit, y: from.y + dy * exit))
            context.addLine(to: to)
        }
        context.addPath(magnifierPath(shape, in: area))
        context.strokePath()
        context.restoreGState()
    }

    /// The enlargement, framed in the stroke colour. Only the frame casts a
    /// shadow; inside, the image is meant to look like the image.
    private static func drawMagnifier(_ enlarged: CGImage?, shape: MagnifierShape, in rect: CGRect, context: CGContext) {
        let outline = magnifierPath(shape, in: rect)
        context.addPath(outline)
        context.strokePath()

        context.saveGState()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.addPath(outline)
        context.clip()
        if let enlarged {
            context.interpolationQuality = .high
            drawImage(enlarged, in: rect, context: context)
        } else {
            context.setFillColor(CGColor(gray: 0.5, alpha: 0.25))
            context.fill(rect)
        }
        context.restoreGState()

        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.addPath(outline)
        context.strokePath()
    }

    private static func drawStep(_ text: String, style: AnnotationStyle, in rect: CGRect, context: CGContext) {
        let diameter = min(rect.width, rect.height)
        let circle = CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter)
        context.setFillColor(style.color.cgColor)
        context.fillEllipse(in: circle)
        context.setShadow(offset: .zero, blur: 0, color: nil)

        let label = text as NSString
        // A long label, as Roman numerals get, shrinks to stay in the circle.
        let fullSize = diameter * 0.55
        let fullWidth = label.size(withAttributes: [.font: NSFont.systemFont(ofSize: fullSize, weight: .bold)]).width
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fullSize * min(1, diameter * 0.78 / max(fullWidth, 1)), weight: .bold),
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
