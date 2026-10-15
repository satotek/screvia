import AppKit

nonisolated struct ImageProcessor {
    /// The image at one pixel per point, or itself when it already is.
    func downscaledToPointSize(_ image: NSImage) -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        guard
            width > 0, height > 0, source.width > width,
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else {
            return image
        }
        return NSImage(cgImage: output, size: image.size)
    }

    func process(_ image: NSImage, options: CaptureStyleOptions) -> NSImage {
        let hasFrame = options.backgroundStyle != .none
            || options.padding > 0
            || options.shadowEnabled

        guard hasFrame else {
            return image
        }

        let shadowMargin: CGFloat = options.shadowEnabled ? 32 : 0
        let horizontalInset = options.padding + shadowMargin
        let verticalInset = options.padding + shadowMargin
        let canvasSize = NSSize(
            width: image.size.width + horizontalInset * 2,
            height: image.size.height + verticalInset * 2
        )
        let imageRect = NSRect(
            x: horizontalInset,
            y: verticalInset,
            width: image.size.width,
            height: image.size.height
        )

        let output = NSImage(size: canvasSize)
        output.lockFocus()

        let radius = min(options.cornerRadius, min(imageRect.width, imageRect.height) / 2)
        let path = NSBezierPath(
            roundedRect: imageRect,
            xRadius: radius,
            yRadius: radius
        )

        NSGraphicsContext.current?.saveGraphicsState()
        if options.shadowEnabled {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.26)
            shadow.shadowBlurRadius = 22
            shadow.shadowOffset = NSSize(width: 0, height: -8)
            shadow.set()
        }
        options.backgroundStyle.color.setFill()
        path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        NSGraphicsContext.current?.saveGraphicsState()
        path.addClip()
        image.draw(
            in: imageRect,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.current?.restoreGraphicsState()

        output.unlockFocus()
        return output
    }
}
