import AppKit
import XCTest

@testable import ScreviaKit

final class StillCropTests: XCTestCase {
    /// A 20×20-point screen at 2×: red in the top quarter, blue below, so
    /// a crop measured from the wrong edge comes out the wrong colour.
    private let still = TestImages.cgImage(width: 40, height: 40) { y in y < 10 ? (255, 0, 0) : (0, 0, 255) }
    private let screenSize = CGSize(width: 20, height: 20)

    /// The top of the screen is at the top of a selection's y range in
    /// AppKit's bottom-up points, and at the top of the still.
    func testASelectionAtTheTopCropsTheTopOfTheStill() throws {
        let image = try CaptureService().capture(
            selection: CGRect(x: 2, y: 16, width: 10, height: 4),
            of: still,
            screenSize: screenSize
        )

        XCTAssertEqual(image.size, NSSize(width: 10, height: 4))
        let reader = try XCTUnwrap(PixelReader(image))
        XCTAssertEqual(reader.color(at: CGPoint(x: 0.5, y: 0.5))?.hexString, "#FF0000")
    }

    func testTheCropKeepsTheStillsPixelsPerPoint() throws {
        let image = try CaptureService().capture(
            selection: CGRect(x: 0, y: 0, width: 10, height: 5),
            of: still,
            screenSize: screenSize
        )

        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(cgImage.width, 20)
        XCTAssertEqual(cgImage.height, 10)
        XCTAssertEqual(try XCTUnwrap(PixelReader(image)).color(at: CGPoint(x: 0.5, y: 0.5))?.hexString, "#0000FF")
    }

    func testASelectionOffTheScreenFails() {
        XCTAssertThrowsError(try CaptureService().capture(
            selection: CGRect(x: 30, y: 30, width: 10, height: 10),
            of: still,
            screenSize: screenSize
        ))
    }
}
