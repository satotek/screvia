import AppKit
import CoreGraphics

/// Produces a display-sized image while keeping the original image available
/// for saving. Long scrolling captures otherwise make SwiftUI render and
/// retain far more pixels than the preview window can show.
enum ImagePreview {
    static func downsample(
        _ image: NSImage,
        maxPixelDimension: Int = 4_096
    ) -> NSImage {
        guard
            maxPixelDimension > 0,
            let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return image
        }

        let sourceWidth = source.width
        let sourceHeight = source.height
        let sourceMaxDimension = max(sourceWidth, sourceHeight)
        guard sourceMaxDimension > maxPixelDimension else {
            return image
        }

        let scale = CGFloat(maxPixelDimension) / CGFloat(sourceMaxDimension)
        let targetWidth = max(1, Int((CGFloat(sourceWidth) * scale).rounded()))
        let targetHeight = max(1, Int((CGFloat(sourceHeight) * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(
            source,
            in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        )

        guard let preview = context.makeImage() else {
            return image
        }

        return NSImage(
            cgImage: preview,
            size: NSSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
        )
    }
}
