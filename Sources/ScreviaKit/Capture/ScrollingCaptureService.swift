import AppKit
// kAXTrustedCheckOptionPrompt imports as a global var because ApplicationServices
// predates Swift's Sendable auditing, even though it's an immutable CFString
// constant. @preconcurrency tells the compiler to trust that, same as it
// would for any other un-audited system header.
@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Captures a scrollable window as a sequence of still images and stitches the
/// overlapping frames into one tall image.
///
/// The first version intentionally uses Quartz scroll events instead of
/// app-specific scripting. That keeps the feature useful across browsers,
/// document readers, terminals, and native AppKit applications.
struct ScrollingCaptureService {
    private let captureService = CaptureService()

    private let maxFrames = 18
    private let scrollDelta: Int32 = -6
    private let settleMilliseconds = 220
    private let sameFrameThreshold = 0.006

    func capture(
        windowID: CGWindowID,
        processID: pid_t,
        windowBounds: CGRect
    ) async throws -> NSImage {
        guard processID > 0 else {
            throw CaptureService.CaptureError.scrollCaptureTargetUnavailable
        }

        try requireAccessibilityAccess()
        try await Task.sleep(for: .milliseconds(160))

        // Shareable content and the capture configuration are expensive to
        // create. Reuse one ScreenCaptureKit session for every viewport.
        let captureSession = try await captureService.makeWindowCaptureSession(
            windowID: windowID,
            includeShadow: false
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Screvia-scroll-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        var storedFrames: [ScrollFrame] = []
        var overlaps = [0]
        var previousFrame: CGImage? = try await captureSession.capture()
        if let previousFrame {
            storedFrames.append(
                try ImageStitcher.store(
                    previousFrame,
                    in: temporaryDirectory,
                    index: storedFrames.count
                )
            )
        }
        var postedScrollCount = 0

        do {
            for _ in 1..<maxFrames {
                try Task.checkCancellation()
                try postScroll(
                    at: CGPoint(x: windowBounds.midX, y: windowBounds.midY),
                    delta: scrollDelta
                )
                postedScrollCount += 1
                try await Task.sleep(for: .milliseconds(settleMilliseconds))

                let nextFrame = try await captureSession.capture()

                guard let previous = previousFrame else {
                    throw CaptureService.CaptureError.scrollCaptureFailed
                }

                // Reaching the end of a document generally produces the same
                // viewport after another scroll. Do not append that duplicate.
                if ImageStitcher.differenceScore(previous, nextFrame)
                    < sameFrameThreshold {
                    break
                }

                let fallback = max(1, min(previous.height, nextFrame.height) / 5)
                let overlap = ImageStitcher.bestOverlap(
                    between: previous,
                    and: nextFrame
                ) ?? fallback
                overlaps.append(overlap)
                storedFrames.append(
                    try ImageStitcher.store(
                        nextFrame,
                        in: temporaryDirectory,
                        index: storedFrames.count
                    )
                )
                previousFrame = nextFrame
            }

            // The full-size viewport images now live on disk while stitching,
            // so the final canvas is the only large allocation left.
            previousFrame = nil
            let result = try ImageStitcher.stitch(storedFrames, overlaps: overlaps)
            restoreScroll(
                at: CGPoint(x: windowBounds.midX, y: windowBounds.midY),
                delta: scrollDelta,
                count: postedScrollCount
            )
            return result
        } catch {
            restoreScroll(
                at: CGPoint(x: windowBounds.midX, y: windowBounds.midY),
                delta: scrollDelta,
                count: postedScrollCount
            )
            throw error
        }
    }

    private func requireAccessibilityAccess() throws {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        guard AXIsProcessTrustedWithOptions(options) else {
            throw CaptureService.CaptureError.accessibilityPermissionRequired
        }
    }

    private func postScroll(at location: CGPoint, delta: Int32) throws {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: delta,
            wheel2: 0,
            wheel3: 0
        ) else {
            throw CaptureService.CaptureError.scrollCaptureFailed
        }

        event.location = location
        // Posting at the HID entry point makes the event look like a real
        // wheel event to WebKit/Safari. `postToPid` can be accepted by the
        // target process while still being ignored by its web content view.
        event.post(tap: .cghidEventTap)
    }

    private func restoreScroll(
        at location: CGPoint,
        delta: Int32,
        count: Int
    ) {
        guard count > 0 else {
            return
        }

        for _ in 0..<count {
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: -delta,
                wheel2: 0,
                wheel3: 0
            ) else {
                return
            }
            event.location = location
            event.post(tap: .cghidEventTap)
        }
    }
}

private struct ScrollFrame {
    let fileURL: URL
    let width: Int
    let height: Int
}

private enum ImageStitcher {
    private struct PixelBuffer {
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let bytesPerPixel: Int
        let data: CFData

        var bytes: UnsafePointer<UInt8>? {
            CFDataGetBytePtr(data)
        }

        init?(image: CGImage) {
            guard
                let data = image.dataProvider?.data,
                image.width > 0,
                image.height > 0,
                image.bitsPerPixel >= 24,
                image.bytesPerRow > 0
            else {
                return nil
            }

            self.width = image.width
            self.height = image.height
            self.bytesPerRow = image.bytesPerRow
            self.bytesPerPixel = max(1, image.bitsPerPixel / 8)
            self.data = data
        }

        func distance(
            from other: PixelBuffer,
            x: Int,
            y: Int,
            otherX: Int = 0,
            otherY: Int
        ) -> Double {
            guard let bytes, let otherBytes = other.bytes else {
                return 1
            }

            let lhsOffset = y * bytesPerRow + x * bytesPerPixel
            let rhsOffset = otherY * other.bytesPerRow + otherX * other.bytesPerPixel
            let channelCount = min(3, min(bytesPerPixel, other.bytesPerPixel))
            guard lhsOffset >= 0, rhsOffset >= 0 else {
                return 1
            }

            var total = 0
            for channel in 0..<channelCount {
                total += abs(Int(bytes[lhsOffset + channel]) - Int(otherBytes[rhsOffset + channel]))
            }

            return Double(total) / Double(max(1, channelCount) * 255)
        }
    }

    static func differenceScore(_ lhs: CGImage, _ rhs: CGImage) -> Double {
        guard let lhs = PixelBuffer(image: lhs), let rhs = PixelBuffer(image: rhs) else {
            return 1
        }

        let width = min(lhs.width, rhs.width)
        let height = min(lhs.height, rhs.height)
        guard width > 0, height > 0 else {
            return 1
        }

        let xStep = max(8, width / 160)
        let yStep = max(8, height / 120)
        var total = 0.0
        var samples = 0

        for y in stride(from: 0, to: height, by: yStep) {
            for x in stride(from: 0, to: width, by: xStep) {
                total += lhs.distance(from: rhs, x: x, y: y, otherX: x, otherY: y)
                samples += 1
            }
        }

        return samples == 0 ? 1 : total / Double(samples)
    }

    static func store(
        _ image: CGImage,
        in directory: URL,
        index: Int
    ) throws -> ScrollFrame {
        let fileURL = directory.appendingPathComponent("frame-(index).png")
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureService.CaptureError.scrollCaptureFailed
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureService.CaptureError.scrollCaptureFailed
        }

        return ScrollFrame(
            fileURL: fileURL,
            width: image.width,
            height: image.height
        )
    }

    static func stitch(
        _ frames: [ScrollFrame],
        overlaps: [Int]
    ) throws -> NSImage {
        guard
            let first = frames.first,
            frames.count == overlaps.count
        else {
            throw CaptureService.CaptureError.scrollCaptureFailed
        }

        if frames.count == 1 {
            guard let image = load(first) else {
                throw CaptureService.CaptureError.scrollCaptureFailed
            }
            return NSImage(
                cgImage: image,
                size: NSSize(width: image.width, height: image.height)
            )
        }

        let width = frames.map(\.width).max() ?? 1
        let height = first.height + frames.dropFirst().enumerated().reduce(0) { total, item in
            let (offset, frame) = item
            let overlap = overlaps[offset + 1]
            return total + max(1, frame.height - overlap)
        }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(size: .zero)
        }

        context.interpolationQuality = .none

        var y: CGFloat = 0
        for index in stride(from: frames.count - 1, through: 0, by: -1) {
            guard let frame = load(frames[index]) else {
                throw CaptureService.CaptureError.scrollCaptureFailed
            }
            context.draw(
                frame,
                in: CGRect(
                    x: 0,
                    y: y,
                    width: CGFloat(frame.width),
                    height: CGFloat(frame.height)
                )
            )

            if index > 0 {
                y += CGFloat(frame.height - overlaps[index])
            }
        }

        guard let result = context.makeImage() else {
            return NSImage(size: .zero)
        }
        return NSImage(cgImage: result, size: NSSize(width: width, height: height))
    }

    private static func load(_ frame: ScrollFrame) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(frame.fileURL as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func bestOverlap(between previous: CGImage, and next: CGImage) -> Int? {
        guard let previous = PixelBuffer(image: previous), let next = PixelBuffer(image: next) else {
            return nil
        }

        let width = min(previous.width, next.width)
        let height = min(previous.height, next.height)
        guard width > 0, height > 0 else {
            return nil
        }

        let minimum = max(1, Int(Double(height) * 0.16))
        let maximum = max(minimum, Int(Double(height) * 0.88))
        let coarseStep = max(4, height / 120)
        var best: (overlap: Int, score: Double)?

        for overlap in stride(from: minimum, through: maximum, by: coarseStep) {
            let score = overlapScore(
                previous: previous,
                next: next,
                width: width,
                overlap: overlap
            )
            if best == nil || score < best!.score {
                best = (overlap, score)
            }
        }

        guard let coarseBest = best else {
            return nil
        }

        let refinementStart = max(minimum, coarseBest.overlap - coarseStep)
        let refinementEnd = min(maximum, coarseBest.overlap + coarseStep)
        var refined = coarseBest
        for overlap in refinementStart...refinementEnd {
            let score = overlapScore(
                previous: previous,
                next: next,
                width: width,
                overlap: overlap
            )
            if score < refined.score {
                refined = (overlap, score)
            }
        }

        // A high score means there was no convincing common strip. In that
        // case the conservative fallback avoids producing an extreme crop.
        return refined.score <= 0.12 ? refined.overlap : nil
    }

    private static func overlapScore(
        previous: PixelBuffer,
        next: PixelBuffer,
        width: Int,
        overlap: Int
    ) -> Double {
        let xStep = max(8, width / 160)
        let yStep = max(6, overlap / 80)
        var total = 0.0
        var samples = 0

        for y in stride(from: 0, to: overlap, by: yStep) {
            let previousY = previous.height - overlap + y
            guard previousY >= 0, previousY < previous.height, y < next.height else {
                continue
            }

            for x in stride(from: 0, to: width, by: xStep) {
                total += previous.distance(
                    from: next,
                    x: x,
                    y: previousY,
                    otherX: x,
                    otherY: y
                )
                samples += 1
            }
        }

        return samples == 0 ? 1 : total / Double(samples)
    }
}
