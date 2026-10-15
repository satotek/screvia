import CoreGraphics
import Foundation
import Vision

nonisolated enum TextLanguage: String, CaseIterable, Identifiable {
    /// Japanese and English, Japanese weighted first.
    case automatic
    case japanese
    case english

    var id: String { rawValue }

    var title: String {
        L10n.text("textLanguage.\(rawValue)")
    }

    /// Japanese first: Vision weighs the languages in order, and putting
    /// English first makes it read kana and kanji as Latin look-alikes.
    var recognitionLanguages: [String] {
        switch self {
        case .automatic: ["ja-JP", "en-US"]
        case .japanese: ["ja-JP"]
        case .english: ["en-US"]
        }
    }
}

/// Reads the text in an image with Vision, on this Mac; nothing is sent
/// anywhere, which is what lets OCR sit alongside Screvia's local-only rule.
nonisolated enum TextRecognizer {
    enum RecognitionError: LocalizedError {
        case noText

        var errorDescription: String? {
            L10n.text("error.noTextFound")
        }
    }

    /// The text, top to bottom: one line per recognized line, or a single
    /// paragraph when `joinLines` is set.
    @concurrent
    static func text(
        in image: CGImage,
        language: TextLanguage = .automatic,
        joinLines: Bool = false
    ) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = language.recognitionLanguages

        try VNImageRequestHandler(cgImage: image).perform([request])

        let lines = (request.results ?? [])
            // Vision's boxes have a bottom-left origin, so higher on the
            // image is a larger y.
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            .compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else {
            throw RecognitionError.noText
        }
        return joinLines ? joined(lines) : lines.joined(separator: "\n")
    }

    /// Lines run together the way the text was written: Japanese and Chinese
    /// need no space where a line wrapped, other scripts need one.
    static func joined(_ lines: [String]) -> String {
        lines.reduce(into: "") { paragraph, line in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard let last = paragraph.last, let first = line.first else {
                paragraph += line
                return
            }
            paragraph += (isCJK(last) && isCJK(first)) ? line : " " + line
        }
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF:
                true
            default:
                false
            }
        }
    }
}
