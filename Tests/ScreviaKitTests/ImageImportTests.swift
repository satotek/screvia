import AppKit
import XCTest

@testable import ScreviaKit

final class ImageImportTests: XCTestCase {
    private func pngData(width: Int, height: Int) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: TestImages.solidCGImage(width: width, height: height))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    /// A PNG with no DPI loads as 72 DPI, one point per pixel. On a 2× Mac
    /// it should be half that, like a capture of the same pixels.
    func testImagesAreSizedLikeACaptureFromThisScreen() throws {
        let image = try ImageImport.image(from: pngData(width: 300, height: 120), scale: 2)

        XCTAssertEqual(image.size, NSSize(width: 150, height: 60))
    }

    /// Normalizing changes the point size only; saving must keep every pixel.
    func testNormalizingKeepsThePixels() throws {
        let image = try ImageImport.image(from: pngData(width: 300, height: 120), scale: 2)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        XCTAssertEqual(cgImage.width, 300)
        XCTAssertEqual(cgImage.height, 120)
    }

    func testDataThatIsNotAnImageIsRejected() {
        XCTAssertThrowsError(try ImageImport.image(from: Data("not an image".utf8), scale: 2))
    }

    // MARK: - Pasteboard

    private func pasteboard() -> NSPasteboard {
        // A private pasteboard, so the tests never touch what the user copied.
        let name = NSPasteboard.Name("ImageImportTests-\(UUID().uuidString)")
        addTeardownBlock { NSPasteboard(name: name).releaseGlobally() }
        let pasteboard = NSPasteboard(name: name)
        pasteboard.clearContents()
        return pasteboard
    }

    func testCopiedPixelsAreRead() throws {
        let pasteboard = pasteboard()
        pasteboard.setData(try pngData(width: 40, height: 20), forType: .png)

        let image = try ImageImport.image(from: pasteboard, scale: 1)

        XCTAssertEqual(image.size, NSSize(width: 40, height: 20))
    }

    /// Copying an image file in Finder puts its URL on the pasteboard.
    func testACopiedImageFileIsRead() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ImageImportTests-\(UUID().uuidString).png")
        try pngData(width: 64, height: 32).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let pasteboard = pasteboard()
        pasteboard.writeObjects([url as NSURL])

        let image = try ImageImport.image(from: pasteboard, scale: 2)

        XCTAssertEqual(image.size, NSSize(width: 32, height: 16))
    }

    func testAPasteboardWithoutAnImageSaysSo() {
        let pasteboard = pasteboard()
        pasteboard.setString("just text", forType: .string)

        XCTAssertThrowsError(try ImageImport.image(from: pasteboard, scale: 2)) { error in
            guard case ImageImport.ImportError.noImageOnClipboard = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }
}
