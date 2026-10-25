import CoreGraphics
import XCTest

@testable import ScreviaKit

final class RecordingMathTests: XCTestCase {
    func testTheSourceRectIsMeasuredFromTheTop() {
        // 100 points up from the bottom of a 900-point screen is 700 down
        // from its top, less the selection's own height.
        let rect = RecordingMath.sourceRect(
            selection: CGRect(x: 40, y: 100, width: 300, height: 200),
            screenSize: CGSize(width: 1440, height: 900)
        )
        XCTAssertEqual(rect, CGRect(x: 40, y: 600, width: 300, height: 200))
    }

    func testTheSourceRectStaysOnTheScreen() {
        let rect = RecordingMath.sourceRect(
            selection: CGRect(x: -20, y: 850, width: 100, height: 100),
            screenSize: CGSize(width: 1440, height: 900)
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 80, height: 50))
    }

    func testVideoSizesAreEven() {
        let size = RecordingMath.pixelSize(points: CGSize(width: 301, height: 199.5), scale: 2)
        XCTAssertEqual(size.width, 602)
        XCTAssertEqual(size.height, 398)

        let odd = RecordingMath.pixelSize(points: CGSize(width: 301, height: 199), scale: 1)
        XCTAssertEqual(odd.width, 300)
        XCTAssertEqual(odd.height, 198)
    }

    func testElapsedTimeReadsLikeAClock() {
        XCTAssertEqual(RecordingMath.elapsedLabel(5), "0:05")
        XCTAssertEqual(RecordingMath.elapsedLabel(760), "12:40")
        XCTAssertEqual(RecordingMath.elapsedLabel(3723), "1:02:03")
        XCTAssertEqual(RecordingMath.elapsedLabel(-1), "0:00")
    }

    func testGIFFramesCoverTheClipAtTheFrameRate() {
        let times = RecordingMath.gifFrameTimes(start: 2, duration: 1, fps: 4)
        XCTAssertEqual(times, [2, 2.25, 2.5, 2.75])
    }

    func testAClipShorterThanAFrameStillHasOne() {
        XCTAssertEqual(RecordingMath.gifFrameTimes(start: 0, duration: 0.01, fps: 15), [0])
        XCTAssertEqual(RecordingMath.gifFrameTimes(start: 1, duration: 0, fps: 15), [1])
    }

    func testGIFsNarrowInProportionButNeverGrow() {
        XCTAssertEqual(
            RecordingMath.gifSize(video: CGSize(width: 1600, height: 900), maxWidth: 800),
            CGSize(width: 800, height: 450)
        )
        XCTAssertEqual(
            RecordingMath.gifSize(video: CGSize(width: 600, height: 400), maxWidth: 800),
            CGSize(width: 600, height: 400)
        )
        XCTAssertEqual(
            RecordingMath.gifSize(video: CGSize(width: 1600, height: 900), maxWidth: nil),
            CGSize(width: 1600, height: 900)
        )
    }
}
