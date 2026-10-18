import AppKit

/// The magnified view of the pixels under the pointer while an area is
/// chosen, with the pointer's position, the colour under it and, while
/// dragging, the selection's size.
///
/// The pixels come from a still image of the screen taken before the
/// selection overlay appears, since the overlay would otherwise darken
/// what the loupe shows. Where the loupe goes and which pixels it shows are
/// worked out here, apart from the drawing, so they can be tested.
nonisolated struct SelectionLoupe {
    /// Pixels across and down; odd, so one sits in the middle.
    static let pixelsAcross = 15
    /// Points per magnified pixel.
    static let cellSize: CGFloat = 8
    /// The space between the pointer and the loupe.
    static let gap: CGFloat = 20
    /// Height of the caption under the magnified pixels.
    static let captionHeight: CGFloat = 38

    static var lensSide: CGFloat { CGFloat(pixelsAcross) * cellSize }
    static var size: CGSize { CGSize(width: lensSide, height: lensSide + captionHeight) }

    let screenImage: CGImage
    /// The screen's size in points, which the image covers.
    let screenSize: CGSize

    /// The pixel under `point`, a point in the screen with AppKit's
    /// bottom-left origin, in the image's top-left pixel coordinates.
    func pixel(at point: CGPoint) -> (x: Int, y: Int) {
        let scaleX = CGFloat(screenImage.width) / max(screenSize.width, 1)
        let scaleY = CGFloat(screenImage.height) / max(screenSize.height, 1)
        let x = Int((point.x * scaleX).rounded(.down))
        let y = Int(((screenSize.height - point.y) * scaleY).rounded(.down))
        return (
            min(max(x, 0), screenImage.width - 1),
            min(max(y, 0), screenImage.height - 1)
        )
    }

    /// The square of pixels the loupe shows around `point`. It may reach
    /// past the image's edges, where the loupe shows nothing, so the pixel
    /// under the pointer always stays in the middle.
    func sampledPixels(around point: CGPoint) -> CGRect {
        let center = pixel(at: point)
        let half = Self.pixelsAcross / 2
        return CGRect(x: center.x - half, y: center.y - half, width: Self.pixelsAcross, height: Self.pixelsAcross)
    }

    /// The colour of the pixel under `point`.
    func color(at point: CGPoint) -> AnnotationColor? {
        let center = pixel(at: point)
        return PixelReader(cgImage: screenImage).color(at: CGPoint(
            x: (CGFloat(center.x) + 0.5) / CGFloat(screenImage.width),
            y: (CGFloat(center.y) + 0.5) / CGFloat(screenImage.height)
        ))
    }

    /// Where the loupe goes for a pointer at `point`: below and to the right
    /// of it, as the pointer's own shape leaves that side clear, and on the
    /// other side of the pointer wherever that would leave `bounds`.
    static func frame(for point: CGPoint, in bounds: CGRect) -> CGRect {
        var origin = CGPoint(x: point.x + gap, y: point.y - gap - size.height)
        if origin.x + size.width > bounds.maxX {
            origin.x = point.x - gap - size.width
        }
        if origin.y < bounds.minY {
            origin.y = point.y + gap
        }
        return CGRect(origin: origin, size: size)
    }
}

@MainActor
extension SelectionLoupe {
    /// Draws the loupe into the current AppKit context, for a pointer at
    /// `point` in a view of `bounds`, showing `size` when a selection is
    /// being dragged.
    func draw(at point: CGPoint, in bounds: CGRect, selectionSize: CGSize?) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        let frame = Self.frame(for: point, in: bounds)
        let lens = CGRect(x: frame.minX, y: frame.maxY - Self.lensSide, width: Self.lensSide, height: Self.lensSide)
        let panel = NSBezierPath(roundedRect: frame, xRadius: 10, yRadius: 10)

        context.saveGState()
        NSShadow.loupe.set()
        NSColor(white: 0.1, alpha: 0.92).setFill()
        panel.fill()
        context.restoreGState()

        // The pixels, enlarged without smoothing so each stays a square.
        context.saveGState()
        NSBezierPath(roundedRect: lens, xRadius: 10, yRadius: 10).addClip()
        let sampled = sampledPixels(around: point)
        let available = sampled.intersection(CGRect(x: 0, y: 0, width: screenImage.width, height: screenImage.height))
        if !available.isEmpty, let pixels = screenImage.cropping(to: available) {
            // The sampled square counts down from the top; the lens is drawn
            // in AppKit's coordinates, which count up from the bottom.
            let drawn = CGRect(
                x: lens.minX + (available.minX - sampled.minX) * Self.cellSize,
                y: lens.maxY - (available.maxY - sampled.minY) * Self.cellSize,
                width: available.width * Self.cellSize,
                height: available.height * Self.cellSize
            )
            context.interpolationQuality = .none
            context.draw(pixels, in: drawn)
        }

        // A faint grid, then the middle pixel outlined in black and white so
        // it shows on any colour.
        context.setStrokeColor(NSColor(white: 0.5, alpha: 0.25).cgColor)
        context.setLineWidth(0.5)
        for index in 1..<Self.pixelsAcross {
            let offset = CGFloat(index) * Self.cellSize
            context.move(to: CGPoint(x: lens.minX + offset, y: lens.minY))
            context.addLine(to: CGPoint(x: lens.minX + offset, y: lens.maxY))
            context.move(to: CGPoint(x: lens.minX, y: lens.minY + offset))
            context.addLine(to: CGPoint(x: lens.maxX, y: lens.minY + offset))
        }
        context.strokePath()
        let middle = CGRect(
            x: lens.midX - Self.cellSize / 2,
            y: lens.midY - Self.cellSize / 2,
            width: Self.cellSize,
            height: Self.cellSize
        )
        context.setLineWidth(1)
        context.setStrokeColor(NSColor.black.cgColor)
        context.stroke(middle.insetBy(dx: -1, dy: -1))
        context.setStrokeColor(NSColor.white.cgColor)
        context.stroke(middle)
        context.restoreGState()

        drawCaption(at: point, below: lens, selectionSize: selectionSize)
    }

    private func drawCaption(at point: CGPoint, below lens: CGRect, selectionSize: CGSize?) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        let primary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let secondary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 1, alpha: 0.6)]

        // Positions read from the top-left, as the saved image's do.
        let position = L10n.format(
            "selection.position",
            Int(point.x.rounded(.down)),
            Int((screenSize.height - point.y).rounded(.down))
        )
        let firstLine = CGPoint(x: lens.minX + 9, y: lens.minY - 16)
        position.draw(at: firstLine, withAttributes: secondary)

        let secondLine = CGPoint(x: lens.minX + 9, y: lens.minY - 31)
        if let selectionSize {
            let size = L10n.format(
                "selection.size",
                Int(selectionSize.width.rounded()),
                Int(selectionSize.height.rounded())
            )
            size.draw(at: secondLine, withAttributes: primary)
        } else if let color = color(at: point) {
            let swatch = CGRect(x: secondLine.x, y: secondLine.y + 2, width: 10, height: 10)
            NSColor(cgColor: color.cgColor)?.setFill()
            NSBezierPath(roundedRect: swatch, xRadius: 2, yRadius: 2).fill()
            NSColor(white: 1, alpha: 0.5).setStroke()
            NSBezierPath(roundedRect: swatch, xRadius: 2, yRadius: 2).stroke()
            color.hexString.draw(at: CGPoint(x: swatch.maxX + 6, y: secondLine.y), withAttributes: primary)
        }
    }
}

private extension NSShadow {
    static var loupe: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.45)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        return shadow
    }
}
