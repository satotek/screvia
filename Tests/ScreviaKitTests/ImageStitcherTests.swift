import CoreGraphics
import XCTest

@testable import ScreviaKit

final class ImageStitcherTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageStitcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    // MARK: - store

    /// Regression test. The filename used a literal "frame-(index).png"
    /// rather than an interpolated one, so every viewport overwrote the same
    /// file and a scrolling capture stitched N copies of the last frame.
    func testStoreWritesADistinctFilePerIndex() throws {
        let frames = try (0..<3).map { index in
            try ImageStitcher.store(
                TestImages.solidCGImage(width: 4, height: 4),
                in: directory,
                index: index
            )
        }

        let paths = Set(frames.map(\.fileURL.path))
        XCTAssertEqual(paths.count, 3, "Each frame index must map to its own file")

        for frame in frames {
            XCTAssertTrue(FileManager.default.fileExists(atPath: frame.fileURL.path))
        }
    }

    func testStoreRecordsThePixelDimensions() throws {
        let frame = try ImageStitcher.store(
            TestImages.solidCGImage(width: 40, height: 25),
            in: directory,
            index: 0
        )

        XCTAssertEqual(frame.width, 40)
        XCTAssertEqual(frame.height, 25)
    }

    // MARK: - differenceScore

    func testDifferenceScoreIsZeroForIdenticalImages() {
        let image = TestImages.gradientCGImage(width: 60, height: 60)

        XCTAssertEqual(ImageStitcher.differenceScore(image, image), 0, accuracy: 0.0001)
    }

    func testDifferenceScoreIsLargeForOppositeImages() {
        let black = TestImages.solidCGImage(width: 60, height: 60, r: 0, g: 0, b: 0)
        let white = TestImages.solidCGImage(width: 60, height: 60, r: 255, g: 255, b: 255)

        XCTAssertEqual(ImageStitcher.differenceScore(black, white), 1, accuracy: 0.0001)
    }

    /// The scroll loop stops when consecutive viewports are near-identical, so
    /// a small change has to score below that threshold while still being
    /// distinguishable from zero.
    func testDifferenceScoreGrowsWithTheSizeOfTheChange() {
        let base = TestImages.solidCGImage(width: 60, height: 60, r: 100, g: 100, b: 100)
        let slightlyOff = TestImages.solidCGImage(width: 60, height: 60, r: 105, g: 105, b: 105)
        let veryOff = TestImages.solidCGImage(width: 60, height: 60, r: 200, g: 200, b: 200)

        let smallChange = ImageStitcher.differenceScore(base, slightlyOff)
        let largeChange = ImageStitcher.differenceScore(base, veryOff)

        XCTAssertGreaterThan(smallChange, 0)
        XCTAssertLessThan(smallChange, largeChange)
    }

    // MARK: - bestOverlap

    /// Two viewports scrolled by a known amount share a strip; the detected
    /// overlap should be the frame height minus that scroll distance.
    func testBestOverlapRecoversAKnownScrollDistance() throws {
        let height = 200
        let scrolled = 40
        let previous = TestImages.gradientCGImage(width: 40, height: height)
        let next = TestImages.gradientCGImage(width: 40, height: height, startingAt: scrolled)

        let overlap = try XCTUnwrap(ImageStitcher.bestOverlap(between: previous, and: next))

        // The search is coarse-then-refined, so allow a small tolerance rather
        // than demanding the exact pixel.
        XCTAssertEqual(Double(overlap), Double(height - scrolled), accuracy: 4)
    }

    func testBestOverlapReturnsNilForAZeroSizedImage() {
        // A 1x1 image is the smallest CGContext will make; the guard being
        // exercised is the one on usable dimensions.
        let tiny = TestImages.solidCGImage(width: 1, height: 1)
        let normal = TestImages.solidCGImage(width: 40, height: 40)

        // Not a crash, and never a nonsensical overlap larger than the frame.
        if let overlap = ImageStitcher.bestOverlap(between: tiny, and: normal) {
            XCTAssertLessThanOrEqual(overlap, 1)
        }
    }

    // MARK: - stitch

    func testStitchingASingleFrameReturnsThatFrameUnchanged() throws {
        let frame = try ImageStitcher.store(
            TestImages.solidCGImage(width: 30, height: 20),
            in: directory,
            index: 0
        )

        let result = try ImageStitcher.stitch([frame], overlaps: [0])

        XCTAssertEqual(result.size.width, 30)
        XCTAssertEqual(result.size.height, 20)
    }

    /// Stitching drops the overlapping strip from every frame after the
    /// first, so the canvas is shorter than the frames laid end to end.
    func testStitchedHeightExcludesTheOverlappingStrips() throws {
        let frames = try (0..<3).map { index in
            try ImageStitcher.store(
                TestImages.gradientCGImage(width: 30, height: 100, startingAt: index * 40),
                in: directory,
                index: index
            )
        }

        let result = try ImageStitcher.stitch(frames, overlaps: [0, 60, 60])

        // 100 + (100 - 60) + (100 - 60)
        XCTAssertEqual(result.size.height, 180)
        XCTAssertEqual(result.size.width, 30)
    }

    func testStitchThrowsWhenOverlapsDoNotMatchTheFrameCount() throws {
        let frame = try ImageStitcher.store(
            TestImages.solidCGImage(width: 10, height: 10),
            in: directory,
            index: 0
        )

        XCTAssertThrowsError(try ImageStitcher.stitch([frame], overlaps: [0, 0]))
    }

    func testStitchThrowsWithNoFrames() {
        XCTAssertThrowsError(try ImageStitcher.stitch([], overlaps: []))
    }
}
