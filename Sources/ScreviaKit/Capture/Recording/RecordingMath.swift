import CoreGraphics
import Foundation

/// The arithmetic of screen recording and GIF export, kept apart from
/// ScreenCaptureKit and AVFoundation so it can be tested.
nonisolated enum RecordingMath {
    /// The part of the display to record, in ScreenCaptureKit's terms:
    /// points from the display's top-left corner. `selection` is in the
    /// selection overlay's terms, from the bottom-left.
    static func sourceRect(selection: CGRect, screenSize: CGSize) -> CGRect {
        let screen = CGRect(origin: .zero, size: screenSize)
        let clipped = selection.intersection(screen)
        guard !clipped.isNull else {
            return .zero
        }
        return CGRect(
            x: clipped.minX,
            y: screenSize.height - clipped.maxY,
            width: clipped.width,
            height: clipped.height
        ).integral
    }

    /// The video's size in pixels. H.264 encodes whole macroblocks of a
    /// subsampled picture, so odd sizes are rounded down to even ones.
    static func pixelSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        func even(_ value: CGFloat) -> Int {
            max(2, Int(value * scale) / 2 * 2)
        }
        return (even(points.width), even(points.height))
    }

    /// Elapsed time for the menu bar: 0:05, 12:40, 1:02:03.
    static func elapsedLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// When each GIF frame is taken from the video: every 1/fps seconds
    /// from `start`, the last before `start + duration`, and at least one
    /// frame for a clip shorter than a frame.
    static func gifFrameTimes(start: TimeInterval, duration: TimeInterval, fps: Int) -> [TimeInterval] {
        guard fps > 0, duration > 0 else {
            return [start]
        }
        let count = max(1, Int((duration * Double(fps)).rounded(.up)))
        return (0..<count).map { start + Double($0) / Double(fps) }
    }

    /// A GIF frame's size: the video's, or narrowed to `maxWidth` with the
    /// height in proportion. Never enlarged.
    static func gifSize(video: CGSize, maxWidth: Int?) -> CGSize {
        guard let maxWidth, maxWidth > 0, video.width > CGFloat(maxWidth), video.width > 0 else {
            return CGSize(width: video.width.rounded(), height: video.height.rounded())
        }
        let height = (video.height * CGFloat(maxWidth) / video.width).rounded()
        return CGSize(width: CGFloat(maxWidth), height: max(1, height))
    }
}
