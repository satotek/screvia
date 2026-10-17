import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Creates a small preview without decoding a full-size screenshot into an
/// NSImage. This is especially important for very tall scrolling captures.
nonisolated enum HistoryThumbnailLoader {
    // NSCache is documented as safe to share across threads without external
    // locking, so this box's @unchecked Sendable just asserts what Apple
    // already guarantees — Swift 6 can't see that from the type alone.
    private final class CacheBox: @unchecked Sendable {
        let cache: NSCache<NSString, NSData> = {
            let cache = NSCache<NSString, NSData>()
            cache.countLimit = 30
            return cache
        }()
    }

    private static let cacheBox = CacheBox()

    /// `pngData(for:maxPixelSize:)` off the caller's actor: decoding a tall
    /// scrolling capture is too slow to run on the main actor.
    @concurrent
    static func loadPNGData(for url: URL, maxPixelSize: Int = 256) async -> Data? {
        pngData(for: url, maxPixelSize: maxPixelSize)
    }

    static func pngData(for url: URL, maxPixelSize: Int = 256) -> Data? {
        // The modification date is in the key because a re-edited capture is
        // saved over its own file.
        // FileManager rather than URL resource values, which a URL can cache.
        let modified = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date)?
            .timeIntervalSinceReferenceDate ?? 0
        let cacheKey = "\(url.standardizedFileURL.path)#\(modified)#\(maxPixelSize)" as NSString
        if let cached = cacheBox.cache.object(forKey: cacheKey) {
            return cached as Data
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        let result = data as Data
        cacheBox.cache.setObject(result as NSData, forKey: cacheKey)
        return result
    }
}
