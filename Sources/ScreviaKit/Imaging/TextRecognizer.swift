import CoreGraphics
import Foundation
import Vision

/// Reads the text in an image with Vision, on this Mac; nothing is sent
/// anywhere, which is what lets OCR sit alongside Screvia's local-only rule.
nonisolated enum TextRecognizer {
    enum RecognitionError: LocalizedError {
        case noText

        var errorDescription: String? {
            L10n.text("error.noTextFound")
        }
    }

    /// The text, one line per recognized line, top to bottom.
    ///
    /// Japanese first: Vision weighs the languages in order, and putting
    /// English first makes it read kana and kanji as Latin look-alikes.
    @concurrent
    static func text(in image: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ja-JP", "en-US"]

        try VNImageRequestHandler(cgImage: image).perform([request])

        let lines = (request.results ?? [])
            // Vision's boxes have a bottom-left origin, so higher on the
            // image is a larger y.
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            .compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else {
            throw RecognitionError.noText
        }
        return lines.joined(separator: "\n")
    }
}
