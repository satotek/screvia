import AppKit
import CoreMedia
import ScreenCaptureKit

/// Records part or all of one display to an MP4 file with ScreenCaptureKit's
/// recording output, which encodes on its own; Screvia never sees a frame.
final class ScreenRecorder: NSObject {
    enum RecorderError: LocalizedError {
        case displayUnavailable
        case failed

        var errorDescription: String? {
            switch self {
            case .displayUnavailable:
                return L10n.text("error.noScreen")
            case .failed:
                return L10n.text("error.recordingFailed")
            }
        }
    }

    private static let framesPerSecond: Int32 = 30

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var finished: CheckedContinuation<Void, Error>?
    private var finishResult: Result<Void, Error>?

    /// Called when the system ends the recording rather than Screvia, as
    /// the screen sharing indicator in the menu bar can.
    var onStoppedBySystem: (() -> Void)?

    var isRecording: Bool { stream != nil }

    /// `sourceRect` is in points from the display's top-left corner; nil
    /// records the whole display.
    func start(displayID: CGDirectDisplayID, sourceRect: CGRect?, showsCursor: Bool, to url: URL) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw RecorderError.displayUnavailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let area = sourceRect ?? CGRect(x: 0, y: 0, width: display.width, height: display.height)
        let size = RecordingMath.pixelSize(points: area.size, scale: CGFloat(filter.pointPixelScale))

        let configuration = SCStreamConfiguration()
        if let sourceRect {
            configuration.sourceRect = sourceRect
        }
        configuration.width = size.width
        configuration.height = size.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Self.framesPerSecond)
        configuration.showsCursor = showsCursor
        configuration.capturesAudio = false

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = url
        outputConfiguration.outputFileType = .mp4
        outputConfiguration.videoCodecType = .h264

        let recordingOutput = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addRecordingOutput(recordingOutput)

        finishResult = nil
        self.stream = stream
        self.recordingOutput = recordingOutput
        outputURL = url
        do {
            try await stream.startCapture()
        } catch {
            reset()
            throw error
        }
        Log.capture.info("Recording started")
    }

    /// Stops the recording and returns the finished file once it is
    /// written.
    func stop() async throws -> URL {
        guard let stream, let outputURL else {
            throw RecorderError.failed
        }
        defer { reset() }

        try? await stream.stopCapture()
        // The file is complete only when the recording output says so,
        // which can be before or after stopCapture returns.
        try await withCheckedThrowingContinuation { continuation in
            if let finishResult {
                continuation.resume(with: finishResult)
            } else {
                finished = continuation
            }
        }
        Log.capture.info("Recording finished")
        return outputURL
    }

    private func reset() {
        stream = nil
        recordingOutput = nil
        outputURL = nil
        finished = nil
    }

    private func complete(_ result: Result<Void, Error>) {
        if let finished {
            self.finished = nil
            finished.resume(with: result)
        } else {
            finishResult = result
        }
    }
}

extension ScreenRecorder: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.complete(.success(()))
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            Log.capture.error("Recording failed: \(message, privacy: .public)")
            self.complete(.failure(RecorderError.failed))
        }
    }
}

extension ScreenRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            Log.capture.info("Recording stopped by the system: \(message, privacy: .public)")
            guard self.isRecording else {
                return
            }
            self.onStoppedBySystem?()
        }
    }
}
