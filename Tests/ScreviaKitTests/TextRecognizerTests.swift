import AppKit
import XCTest

@testable import ScreviaKit

final class TextRecognizerTests: XCTestCase {
    /// Black text on white, one entry per line from the top.
    private func image(lines: [String]) -> CGImage {
        let width = 900
        let lineHeight = 90
        let height = lineHeight * lines.count + 60
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(
                at: CGPoint(x: 30, y: height - 30 - lineHeight * (index + 1)),
                withAttributes: [.font: NSFont.systemFont(ofSize: 56), .foregroundColor: NSColor.black]
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }

    /// GitHub's macOS runners are virtual machines where Vision's text
    /// recognition fails outright with an unknown error, so the tests that
    /// recognize real text are skipped there rather than failing CI. They
    /// still run on any Mac, where the feature is used.
    private func requireTextRecognition() async throws {
        do {
            _ = try await TextRecognizer.text(in: image(lines: ["Probe 123"]))
        } catch TextRecognizer.RecognitionError.noText {
            return
        } catch {
            throw XCTSkip("Vision text recognition is unavailable here: \(error)")
        }
    }

    func testReadsEnglishLinesTopToBottom() async throws {
        try await requireTextRecognition()
        let text = try await TextRecognizer.text(in: image(lines: ["Hello Screvia", "Second line 42"]))

        XCTAssertEqual(text, "Hello Screvia\nSecond line 42")
    }

    func testReadsJapanese() async throws {
        try await requireTextRecognition()
        let text = try await TextRecognizer.text(in: image(lines: ["画面を撮影する"]))

        XCTAssertEqual(text, "画面を撮影する")
    }

    func testAnImageWithoutTextSaysSo() async throws {
        try await requireTextRecognition()
        do {
            _ = try await TextRecognizer.text(in: image(lines: []))
            XCTFail("expected noText")
        } catch TextRecognizer.RecognitionError.noText {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Joining lines

    /// Japanese wraps without spaces, so joining must not add any.
    func testJapaneseLinesJoinWithoutSpaces() {
        XCTAssertEqual(TextRecognizer.joined(["画面を", "撮影する"]), "画面を撮影する")
    }

    func testEnglishLinesJoinWithASpace() {
        XCTAssertEqual(TextRecognizer.joined(["Hello", "Screvia "]), "Hello Screvia")
    }

    func testMixedLinesGetASpaceOnlyNextToLatin() {
        XCTAssertEqual(TextRecognizer.joined(["Screvia で", "撮る", "screen"]), "Screvia で撮る screen")
    }

    func testRecognitionCanJoinLines() async throws {
        try await requireTextRecognition()
        let text = try await TextRecognizer.text(in: image(lines: ["Hello Screvia", "Second line 42"]), joinLines: true)

        XCTAssertEqual(text, "Hello Screvia Second line 42")
    }
}
