import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import ScreviaKit

final class HistoryThumbnailLoaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryThumbnailLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    /// Writes a PNG whose dimensions identify it, so a mixed-up cache entry
    /// shows up as the wrong size rather than passing silently.
    private func writePNG(named name: String, width: Int, height: Int) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let cgImage = TestImages.gradientCGImage(width: width, height: height)

        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        return url
    }

    private func size(of pngData: Data) throws -> CGSize {
        let image = try XCTUnwrap(NSImage(data: pngData))
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    func testThumbnailIsGeneratedForAnImageOnDisk() throws {
        let url = try writePNG(named: "shot.png", width: 400, height: 300)

        let data = try XCTUnwrap(HistoryThumbnailLoader.pngData(for: url, maxPixelSize: 64))

        XCTAssertEqual(try size(of: data).width, 64)
    }

    func testThumbnailIsBoundedByMaxPixelSize() throws {
        let url = try writePNG(named: "wide.png", width: 800, height: 200)

        let data = try XCTUnwrap(HistoryThumbnailLoader.pngData(for: url, maxPixelSize: 100))

        let thumbnailSize = try size(of: data)
        XCTAssertLessThanOrEqual(max(thumbnailSize.width, thumbnailSize.height), 100)
    }

    /// Regression test. The cache key was built from a literal
    /// "(url...)#(maxPixelSize)" rather than an interpolated string, so every
    /// entry shared one key and the first thumbnail loaded was handed back
    /// for every other capture in the history strip.
    func testDifferentFilesDoNotShareACacheEntry() throws {
        let tall = try writePNG(named: "tall.png", width: 100, height: 400)
        let wide = try writePNG(named: "wide2.png", width: 400, height: 100)

        let tallThumb = try size(of: try XCTUnwrap(HistoryThumbnailLoader.pngData(for: tall, maxPixelSize: 80)))
        let wideThumb = try size(of: try XCTUnwrap(HistoryThumbnailLoader.pngData(for: wide, maxPixelSize: 80)))

        XCTAssertGreaterThan(tallThumb.height, tallThumb.width, "The tall image should stay tall")
        XCTAssertGreaterThan(wideThumb.width, wideThumb.height, "The wide image should stay wide")
    }

    /// The same file at two sizes are two different cache entries.
    func testTheSameFileAtDifferentSizesDoesNotShareACacheEntry() throws {
        let url = try writePNG(named: "resize.png", width: 400, height: 400)

        let small = try size(of: try XCTUnwrap(HistoryThumbnailLoader.pngData(for: url, maxPixelSize: 32)))
        let large = try size(of: try XCTUnwrap(HistoryThumbnailLoader.pngData(for: url, maxPixelSize: 128)))

        XCTAssertEqual(small.width, 32)
        XCTAssertEqual(large.width, 128)
    }

    func testRepeatedRequestsForTheSameThumbnailAgree() throws {
        let url = try writePNG(named: "cached.png", width: 300, height: 200)

        let first = try XCTUnwrap(HistoryThumbnailLoader.pngData(for: url, maxPixelSize: 64))
        let second = try XCTUnwrap(HistoryThumbnailLoader.pngData(for: url, maxPixelSize: 64))

        XCTAssertEqual(first, second)
    }

    func testMissingFileYieldsNoThumbnail() {
        let missing = directory.appendingPathComponent("does-not-exist.png")

        XCTAssertNil(HistoryThumbnailLoader.pngData(for: missing))
    }

    func testNonImageFileYieldsNoThumbnail() throws {
        let url = directory.appendingPathComponent("notes.png")
        try Data("definitely not a png".utf8).write(to: url)

        XCTAssertNil(HistoryThumbnailLoader.pngData(for: url))
    }
}
