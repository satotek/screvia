import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Creates a small preview without decoding a full-size screenshot into an
/// NSImage. This is especially important for very tall scrolling captures.
enum HistoryThumbnailLoader {
    private static let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 30
        return cache
    }()

    static func pngData(for url: URL, maxPixelSize: Int = 256) -> Data? {
        let cacheKey = "(url.standardizedFileURL.path)#(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
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
        cache.setObject(result as NSData, forKey: cacheKey)
        return result
    }
}
