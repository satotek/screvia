import XCTest

@testable import ScreviaKit

final class SelectionLoupeTests: XCTestCase {
    /// A 2× screen of 100 × 50 points: 200 × 100 pixels, the top half red
    /// and the bottom half blue.
    private func loupe() -> SelectionLoupe {
        let image = TestImages.cgImage(width: 200, height: 100) { y in
            y < 50 ? (255, 0, 0) : (0, 0, 255)
        }
        return SelectionLoupe(screenImage: image, screenSize: CGSize(width: 100, height: 50))
    }

    func testAPointMapsToThePixelUnderItCountedFromTheTop() {
        let loupe = loupe()

        // AppKit's points count up from the bottom; pixels count down.
        XCTAssertTrue(loupe.pixel(at: CGPoint(x: 0, y: 50)) == (0, 0))
        XCTAssertTrue(loupe.pixel(at: CGPoint(x: 10.4, y: 40)) == (20, 20))
        // The far edges stay inside the image.
        XCTAssertTrue(loupe.pixel(at: CGPoint(x: 100, y: 0)) == (199, 99))
    }

    func testThePixelUnderThePointerIsInTheMiddleEvenAtAnEdge() {
        let loupe = loupe()
        let half = SelectionLoupe.pixelsAcross / 2

        let corner = loupe.sampledPixels(around: CGPoint(x: 0, y: 50))

        XCTAssertEqual(corner.minX, CGFloat(-half))
        XCTAssertEqual(corner.minY, CGFloat(-half))
        XCTAssertEqual(corner.width, CGFloat(SelectionLoupe.pixelsAcross))
    }

    func testTheColourIsReadFromTheStillOfTheScreen() throws {
        let loupe = loupe()

        let top = try XCTUnwrap(loupe.color(at: CGPoint(x: 50, y: 45)))
        let bottom = try XCTUnwrap(loupe.color(at: CGPoint(x: 50, y: 5)))

        XCTAssertGreaterThan(top.red, 0.8)
        XCTAssertLessThan(top.blue, 0.2)
        XCTAssertGreaterThan(bottom.blue, 0.8)
        XCTAssertLessThan(bottom.red, 0.2)
    }

    func testTheLoupeSitsBelowAndRightOfThePointer() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

        let frame = SelectionLoupe.frame(for: CGPoint(x: 300, y: 500), in: bounds)

        XCTAssertGreaterThan(frame.minX, 300)
        XCTAssertLessThan(frame.maxY, 500)
        XCTAssertTrue(bounds.contains(frame))
    }

    func testTheLoupeMovesToTheOtherSideNearTheRightAndBottomEdges() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

        let frame = SelectionLoupe.frame(for: CGPoint(x: 990, y: 10), in: bounds)

        XCTAssertLessThan(frame.maxX, 990)
        XCTAssertGreaterThan(frame.minY, 10)
        XCTAssertTrue(bounds.contains(frame))
    }
}
