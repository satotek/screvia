import AppKit
import UniformTypeIdentifiers

/// Brings an image Screvia did not capture into the editor.
nonisolated enum ImageImport {
    enum ImportError: LocalizedError {
        case unreadable
        case noImageOnClipboard

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return L10n.text("error.imageUnreadable")
            case .noImageOnClipboard:
                return L10n.text("error.clipboardNoImage")
            }
        }
    }

    /// The image sized in points as if captured on a screen of `scale`.
    ///
    /// Editor styles are in image points, and a file's point size comes from
    /// its DPI. Most files say 72, so a 3000-pixel image would be 3000
    /// points wide and a 4-point line a hairline on it. Screvia's own PNGs
    /// carry no DPI either, which is why history entries go through here
    /// too. Treating every image like a capture from this Mac's screen gives
    /// the styles the proportions they have on a fresh capture.
    static func normalized(_ image: NSImage, scale: CGFloat) -> NSImage? {
        guard
            scale > 0,
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        )
    }

    static func image(from data: Data, scale: CGFloat) throws -> NSImage {
        guard let image = NSImage(data: data), let normalized = normalized(image, scale: scale) else {
            throw ImportError.unreadable
        }
        return normalized
    }

    /// Reads an image the user copied. A copied image file counts too, as
    /// Finder puts the file's URL on the pasteboard rather than its pixels.
    static func image(from pasteboard: NSPasteboard, scale: CGFloat) throws -> NSImage {
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) as? [URL])?.first {
            return try image(from: try Data(contentsOf: url), scale: scale)
        }

        guard
            let image = NSImage(pasteboard: pasteboard),
            let normalized = normalized(image, scale: scale)
        else {
            throw ImportError.noImageOnClipboard
        }
        return normalized
    }

    /// The content types the editor opens, for the open panel and drops.
    static let contentTypes: [UTType] = [.image]
}
