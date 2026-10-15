import AppKit
import CoreGraphics

/// The pointer as it was when a capture was taken. Display captures never
/// include it, so it is drawn in afterwards when the user asks for it.
nonisolated struct CursorSnapshot {
    let image: CGImage
    /// In points, from the image's top-left corner.
    let size: CGSize
    let hotSpot: CGPoint
    /// Where the hot spot is, in points from the screen's top-left corner.
    let location: CGPoint

    @MainActor
    static func current(on screen: NSScreen) -> CursorSnapshot? {
        let cursor = NSCursor.currentSystem ?? NSCursor.arrow
        guard let image = cursor.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        // AppKit's global coordinates start at the bottom-left of the main
        // screen; captures start at the top-left of their own screen.
        let mouse = NSEvent.mouseLocation
        return CursorSnapshot(
            image: image,
            size: cursor.image.size,
            hotSpot: cursor.hotSpot,
            location: CGPoint(x: mouse.x - screen.frame.minX, y: screen.frame.maxY - mouse.y)
        )
    }

    /// `display` with the pointer drawn on it; `display` covers the whole
    /// screen at `pixelsPerPoint`.
    func drawn(onto display: CGImage, pixelsPerPoint: CGFloat) -> CGImage {
        let width = display.width
        let height = display.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: display.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return display
        }

        context.draw(display, in: CGRect(x: 0, y: 0, width: width, height: height))
        // CGContext counts from the bottom; `location` from the top.
        let frame = CGRect(
            x: (location.x - hotSpot.x) * pixelsPerPoint,
            y: CGFloat(height) - (location.y - hotSpot.y + size.height) * pixelsPerPoint,
            width: size.width * pixelsPerPoint,
            height: size.height * pixelsPerPoint
        )
        context.interpolationQuality = .high
        context.draw(image, in: frame)
        return context.makeImage() ?? display
    }
}
