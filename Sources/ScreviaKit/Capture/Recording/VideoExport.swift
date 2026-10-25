import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Writing a recording out again: trimmed to a part of it, or as a GIF.
nonisolated enum VideoExport {
    enum ExportError: LocalizedError {
        case failed

        var errorDescription: String? {
            L10n.text("error.exportFailed")
        }
    }

    static let gifFramesPerSecond = 15

    /// Writes `range` of the video at `source` to `destination` as MP4,
    /// re-encoding so the cut lands on the chosen frame rather than the
    /// nearest keyframe.
    @concurrent
    static func trim(_ source: URL, to range: CMTimeRange, destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.failed
        }
        session.timeRange = range
        try? FileManager.default.removeItem(at: destination)
        try await session.export(to: destination, as: .mp4)
    }

    /// Writes the video at `source` to `destination` as a GIF that loops
    /// forever, at most `maxWidth` pixels wide.
    @concurrent
    static func gif(from source: URL, maxWidth: Int?, destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let range = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.failed
        }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let videoSize = naturalSize.applying(transform)
        let size = RecordingMath.gifSize(
            video: CGSize(width: abs(videoSize.width), height: abs(videoSize.height)),
            maxWidth: maxWidth
        )

        let fps = gifFramesPerSecond
        let times = RecordingMath.gifFrameTimes(
            start: range.start.seconds,
            duration: range.duration.seconds,
            fps: fps
        ).map { CMTime(seconds: $0, preferredTimescale: 600) }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        // Frames exactly where asked; the default tolerance repeats
        // keyframes and makes the GIF stutter.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        try? FileManager.default.removeItem(at: destination)
        guard let output = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.gif.identifier as CFString,
            times.count,
            nil
        ) else {
            throw ExportError.failed
        }
        CGImageDestinationSetProperties(output, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 1.0 / Double(fps),
                kCGImagePropertyGIFUnclampedDelayTime: 1.0 / Double(fps)
            ]
        ] as CFDictionary

        // A frame that cannot be read repeats the one before: the image
        // count was promised up front, and finalizing short of it fails.
        var written = 0
        var previous: CGImage?
        for await result in generator.images(for: times) {
            guard let image = (try? result.image) ?? previous else {
                continue
            }
            CGImageDestinationAddImage(output, image, frameProperties)
            previous = image
            written += 1
        }
        guard written == times.count, CGImageDestinationFinalize(output) else {
            try? FileManager.default.removeItem(at: destination)
            throw ExportError.failed
        }
    }
}
