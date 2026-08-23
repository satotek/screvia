import AppKit
import XCTest

@testable import ScreviaKit

final class ImageStoreTests: XCTestCase {
    private let store = ImageStore()
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    // MARK: - save

    func testSaveCreatesTheDirectoryIfItIsMissing() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

        _ = try store.save(
            TestImages.nsImage(width: 10, height: 10),
            directory: directory,
            format: .png,
            jpegQuality: 1
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    func testSavedFileUsesTheFormatsExtension() throws {
        for format in ImageFormat.allCases {
            let url = try store.save(
                TestImages.nsImage(width: 10, height: 10),
                directory: directory,
                format: format,
                jpegQuality: 0.9
            )

            XCTAssertEqual(url.pathExtension, format.fileExtension)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    /// Filenames are timestamped to the second, so two captures inside the
    /// same second would collide without the numeric suffix — and the second
    /// one would silently overwrite the first.
    func testCapturesWithinTheSameSecondDoNotOverwriteEachOther() throws {
        let image = TestImages.nsImage(width: 10, height: 10)

        let first = try store.save(image, directory: directory, format: .png, jpegQuality: 1)
        let second = try store.save(image, directory: directory, format: .png, jpegQuality: 1)
        let third = try store.save(image, directory: directory, format: .png, jpegQuality: 1)

        XCTAssertEqual(Set([first, second, third]).count, 3)
        for url in [first, second, third] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testSavedFilesAreNamedForTheApp() throws {
        let url = try store.save(
            TestImages.nsImage(width: 10, height: 10),
            directory: directory,
            format: .png,
            jpegQuality: 1
        )

        XCTAssertTrue(url.lastPathComponent.hasPrefix("Screenshot-"))
    }

    // MARK: - saveAndEncode

    func testSaveAndEncodeOnlyReturnsDataWhenAsked() throws {
        let image = TestImages.nsImage(width: 10, height: 10)

        let without = try store.saveAndEncode(
            image, directory: directory, format: .png, jpegQuality: 1, includeData: false
        )
        let with = try store.saveAndEncode(
            image, directory: directory, format: .png, jpegQuality: 1, includeData: true
        )

        XCTAssertNil(without.data)
        XCTAssertNotNil(with.data)
        XCTAssertEqual(with.format, .png)
    }

    func testEncodedDataMatchesWhatWasWrittenToDisk() throws {
        let saved = try store.saveAndEncode(
            TestImages.nsImage(width: 20, height: 20),
            directory: directory,
            format: .png,
            jpegQuality: 1,
            includeData: true
        )

        let onDisk = try Data(contentsOf: saved.fileURL)
        XCTAssertEqual(saved.data, onDisk)
    }

    /// Lower JPEG quality has to actually reach the encoder, or the quality
    /// slider in Preferences would be decorative.
    func testLowerJpegQualityProducesASmallerFile() throws {
        // A gradient compresses differently at different qualities; a flat
        // colour would be nearly the same size either way.
        let cgImage = TestImages.gradientCGImage(width: 200, height: 200)
        let image = NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))

        let low = try store.saveAndEncode(
            image, directory: directory, format: .jpeg, jpegQuality: 0.1, includeData: true
        )
        let high = try store.saveAndEncode(
            image, directory: directory, format: .jpeg, jpegQuality: 1, includeData: true
        )

        let lowSize = try XCTUnwrap(low.data?.count)
        let highSize = try XCTUnwrap(high.data?.count)
        XCTAssertLessThan(lowSize, highSize)
    }

    // MARK: - readImageData

    func testReadImageDataRecognisesTheFormatFromTheExtension() throws {
        let png = try store.save(
            TestImages.nsImage(width: 10, height: 10),
            directory: directory, format: .png, jpegQuality: 1
        )
        let jpeg = try store.save(
            TestImages.nsImage(width: 10, height: 10),
            directory: directory, format: .jpeg, jpegQuality: 1
        )

        XCTAssertEqual(store.readImageData(at: png)?.format, .png)
        XCTAssertEqual(store.readImageData(at: jpeg)?.format, .jpeg)
    }

    func testReadImageDataReturnsNilForAMissingFile() {
        let missing = directory.appendingPathComponent("nope.png")

        XCTAssertNil(store.readImageData(at: missing))
    }

    func testReadImageDataReturnsNilForAnUnsupportedExtension() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("notes.txt")
        try Data("not an image".utf8).write(to: url)

        XCTAssertNil(store.readImageData(at: url))
    }

    // MARK: - Clipboard

    /// The clipboard carries PNG rather than the uncompressed TIFF AppKit
    /// would otherwise hand over — this is the behaviour that fix introduced.
    func testCopyingAnImagePutsPngOnThePasteboard() {
        NSPasteboard.general.clearContents()

        store.copyToClipboard(TestImages.nsImage(width: 20, height: 20))

        let data = NSPasteboard.general.data(forType: .png)
        XCTAssertNotNil(data, "The pasteboard should carry PNG data")
        // PNG's 8-byte magic number.
        XCTAssertEqual(data?.prefix(4).map { $0 }, [0x89, 0x50, 0x4E, 0x47])
    }

    func testCopyingRawDataUsesTheMatchingPasteboardType() {
        NSPasteboard.general.clearContents()
        let payload = Data("fake tiff".utf8)

        store.copyToClipboard(data: payload, format: .tiff)

        XCTAssertEqual(NSPasteboard.general.data(forType: .tiff), payload)
    }
}
