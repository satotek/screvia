import CoreGraphics
import XCTest

@testable import ScreviaKit

final class AnnotationGeometryTests: XCTestCase {
    /// A 200×100 view with the image filling it, so 0.1 is 20 points across
    /// and 10 points down.
    private let imageRect = CGRect(x: 0, y: 0, width: 200, height: 100)

    private func box(_ start: CGPoint, _ end: CGPoint, tool: AnnotationTool = .rectangle) -> Annotation {
        Annotation(tool: tool, start: start, end: end)
    }

    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-9, file: file, line: line)
    }

    private func assertRect(_ actual: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        assertPoint(actual.origin, expected.origin, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 1e-9, file: file, line: line)
    }

    // MARK: - Hit testing

    func testBoxesAreHitAnywhereInside() {
        let annotation = box(CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.5))

        XCTAssertTrue(annotation.contains(CGPoint(x: 60, y: 30), in: imageRect, tolerance: 0))
        XCTAssertFalse(annotation.contains(CGPoint(x: 150, y: 80), in: imageRect, tolerance: 0))
    }

    func testArrowsAreHitOnlyNearTheLine() {
        let arrow = box(CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), tool: .arrow)

        XCTAssertTrue(arrow.contains(CGPoint(x: 100, y: 52), in: imageRect, tolerance: 6))
        // Inside the bounding box, but far from the diagonal.
        XCTAssertFalse(arrow.contains(CGPoint(x: 180, y: 10), in: imageRect, tolerance: 6))
    }

    func testHandlesAreFoundInViewSpace() {
        let annotation = box(CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.5))

        XCTAssertEqual(
            annotation.handle(at: CGPoint(x: 101, y: 51), in: imageRect, radius: 4),
            .box(x: .max, y: .max)
        )
        XCTAssertEqual(
            annotation.handle(at: CGPoint(x: 60, y: 10), in: imageRect, radius: 4),
            .box(x: nil, y: .min)
        )
        XCTAssertNil(annotation.handle(at: CGPoint(x: 60, y: 30), in: imageRect, radius: 4))
    }

    func testArrowsHaveOnlyEndpointHandles() {
        let arrow = box(CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.2, y: 0.8), tool: .arrow)

        XCTAssertEqual(arrow.handles, [.start, .end])
        assertPoint(arrow.location(of: .start), CGPoint(x: 0.9, y: 0.1))
    }

    // MARK: - Moving

    func testMovingShiftsBothEnds() {
        let moved = box(CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.3, y: 0.4))
            .moved(by: CGVector(dx: 0.1, dy: 0.2))

        assertPoint(moved.start, CGPoint(x: 0.2, y: 0.4))
        assertPoint(moved.end, CGPoint(x: 0.4, y: 0.6))
    }

    /// Stopping at the edge keeps the shape whole; letting it slide off would
    /// leave a handle nobody can reach.
    func testMovingStopsAtTheImageEdge() {
        let moved = box(CGPoint(x: 0.6, y: 0.1), CGPoint(x: 0.9, y: 0.3))
            .moved(by: CGVector(dx: 0.5, dy: -0.5))

        assertPoint(moved.start, CGPoint(x: 0.7, y: 0))
        assertPoint(moved.end, CGPoint(x: 1, y: 0.2))
    }

    // MARK: - Resizing

    func testDraggingACornerKeepsTheOppositeCorner() {
        let resized = box(CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.4, y: 0.4))
            .resized(.box(x: .max, y: .max), to: CGPoint(x: 0.7, y: 0.6))

        assertRect(resized.bounds, CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.4))
    }

    func testDraggingAnEdgeChangesOneAxis() {
        let resized = box(CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.4, y: 0.4))
            .resized(.box(x: .min, y: nil), to: CGPoint(x: 0.1, y: 0.9))

        assertRect(resized.bounds, CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.2))
    }

    /// Dragging the right edge past the left one flips the box instead of
    /// giving it a negative width.
    func testDraggingPastTheOppositeSideFlipsTheBox() {
        let resized = box(CGPoint(x: 0.4, y: 0.2), CGPoint(x: 0.6, y: 0.4))
            .resized(.box(x: .max, y: nil), to: CGPoint(x: 0.1, y: 0.3))

        XCTAssertEqual(resized.bounds.minX, 0.1, accuracy: 1e-9)
        XCTAssertEqual(resized.bounds.maxX, 0.4, accuracy: 1e-9)
    }

    func testDraggingAnArrowEndpointKeepsItsDirection() {
        let resized = box(CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.2, y: 0.8), tool: .arrow)
            .resized(.end, to: CGPoint(x: 0.5, y: 1.4))

        assertPoint(resized.start, CGPoint(x: 0.9, y: 0.1))
        assertPoint(resized.end, CGPoint(x: 0.5, y: 1))
    }
}
