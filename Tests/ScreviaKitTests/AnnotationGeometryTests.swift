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

    /// With a drawing tool, an unfilled box is see-through: its outline
    /// picks it up, and inside is left for drawing.
    func testSeeThroughBoxesAreHitOnTheirOutlineWithADrawingTool() {
        let box = box(CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.5))
        var filled = box
        filled.style.fillColor = .blue

        XCTAssertFalse(box.contains(CGPoint(x: 60, y: 30), in: imageRect, tolerance: 6, insideCounts: false))
        XCTAssertTrue(box.contains(CGPoint(x: 21, y: 30), in: imageRect, tolerance: 6, insideCounts: false))
        XCTAssertTrue(filled.contains(CGPoint(x: 60, y: 30), in: imageRect, tolerance: 6, insideCounts: false))
    }

    func testSeeThroughEllipsesAreHitOnTheirCurve() {
        // A circle 80 wide around (60, 30) in a 200×100 view: 0.1...0.5
        // across, 0.1...0.5 down, so 80×40.
        let ellipse = box(CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.5), tool: .ellipse)

        XCTAssertTrue(ellipse.contains(CGPoint(x: 100, y: 30), in: imageRect, tolerance: 6, insideCounts: false))
        XCTAssertFalse(ellipse.contains(CGPoint(x: 60, y: 30), in: imageRect, tolerance: 6, insideCounts: false))
        // Inside the box, but outside the curve.
        XCTAssertFalse(ellipse.contains(CGPoint(x: 26, y: 13), in: imageRect, tolerance: 2, insideCounts: false))
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

    // MARK: - Freehand

    private func scribble() -> Annotation {
        let points = [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.3, y: 0.6), CGPoint(x: 0.5, y: 0.4)]
        return Annotation(tool: .freehand, start: CGPoint(x: 0.1, y: 0.2), end: CGPoint(x: 0.5, y: 0.6), points: points)
    }

    func testFreehandBoundsComeFromItsPoints() {
        assertRect(scribble().bounds, CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.4))
    }

    /// Hit on the stroke, not anywhere in its box.
    func testFreehandIsHitOnlyNearTheStroke() {
        let annotation = scribble()

        XCTAssertTrue(annotation.contains(CGPoint(x: 40, y: 40), in: imageRect, tolerance: 4))
        XCTAssertFalse(annotation.contains(CGPoint(x: 90, y: 25), in: imageRect, tolerance: 4))
    }

    func testResizingFreehandScalesItsPoints() {
        let resized = scribble().resized(.box(x: .max, y: .max), to: CGPoint(x: 0.9, y: 1))

        assertRect(resized.bounds, CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.8))
        // The middle point sat half way across and all the way down.
        assertPoint(resized.points[1], CGPoint(x: 0.5, y: 1))
    }

    func testMovingFreehandMovesItsPoints() {
        let moved = scribble().moved(by: CGVector(dx: 0.1, dy: 0.1))

        assertPoint(moved.points[0], CGPoint(x: 0.2, y: 0.3))
        assertRect(moved.bounds, CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.4))
    }

    // MARK: - Font-sized tools

    func testTextAndStepsHaveNoResizeHandles() {
        XCTAssertEqual(box(.zero, CGPoint(x: 0.2, y: 0.1), tool: .text).handles, [])
        XCTAssertEqual(box(.zero, CGPoint(x: 0.1, y: 0.1), tool: .step).handles, [])
    }

    func testStepsAreNumberedInOrderAndRenumberOnDelete() {
        let first = box(.zero, .zero, tool: .step)
        let arrow = box(.zero, CGPoint(x: 1, y: 1), tool: .arrow)
        let second = box(.zero, .zero, tool: .step)
        let third = box(.zero, .zero, tool: .step)

        XCTAssertEqual(Annotation.stepNumbers(in: [first, arrow, second, third])[third.id], 3)
        XCTAssertEqual(Annotation.stepNumbers(in: [arrow, second, third])[third.id], 2)
        XCTAssertNil(Annotation.stepNumbers(in: [first, arrow])[arrow.id])
    }

    // MARK: - Within a crop

    func testMovingStopsAtTheCrop() {
        let crop = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let moved = box(CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.4, y: 0.4))
            .moved(by: CGVector(dx: 0.9, dy: -0.9), within: crop)

        assertRect(moved.bounds, CGRect(x: 0.6, y: 0.2, width: 0.1, height: 0.1))
    }

    /// After a crop a shape can sit partly outside. Moving it must not snap
    /// it inside on the first frame, only stop it going further out.
    func testAShapeAlreadyPastTheCropDoesNotJump() {
        let crop = CGRect(x: 0.2, y: 0, width: 0.8, height: 1)
        let outside = box(CGPoint(x: 0.1, y: 0.3), CGPoint(x: 0.3, y: 0.4))

        assertRect(outside.moved(by: CGVector(dx: 0, dy: 0.1), within: crop).bounds,
                   CGRect(x: 0.1, y: 0.4, width: 0.2, height: 0.1))
        assertRect(outside.moved(by: CGVector(dx: -0.1, dy: 0), within: crop).bounds,
                   CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.1))
    }

    func testDuplicatesGetANewIdentity() {
        let original = scribble()
        let copy = original.duplicated()

        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.points, original.points)
    }

    // MARK: - Speech balloons

    private func balloon() -> Annotation {
        Annotation(
            tool: .balloon,
            start: CGPoint(x: 0.1, y: 0.1),
            end: CGPoint(x: 0.3, y: 0.2),
            text: "Hi",
            tail: CGPoint(x: 0.6, y: 0.8)
        )
    }

    /// The box follows the font, so the tail's tip is the only grip.
    func testBalloonsAreDraggedOnlyByTheirTail() throws {
        let dragged = balloon().resized(.tail, to: CGPoint(x: 0.9, y: 0.1))

        XCTAssertEqual(balloon().handles, [.tail])
        assertPoint(try XCTUnwrap(dragged.tail), CGPoint(x: 0.9, y: 0.1))
        assertRect(dragged.bounds, balloon().bounds)
    }

    func testMovingABalloonTakesItsTailAlong() throws {
        let moved = balloon().moved(by: CGVector(dx: 0.1, dy: 0.1))

        assertPoint(try XCTUnwrap(moved.tail), CGPoint(x: 0.7, y: 0.9))
    }

    /// The box can still move, but the tip stays where it can be grabbed.
    func testABalloonsTailStaysInsideTheCrop() throws {
        let crop = CGRect(x: 0, y: 0, width: 0.7, height: 1)

        let moved = balloon().moved(by: CGVector(dx: 0.2, dy: 0), within: crop)

        assertPoint(try XCTUnwrap(moved.tail), CGPoint(x: 0.7, y: 0.8))
        XCTAssertEqual(moved.bounds.minX, 0.3, accuracy: 1e-9)
    }

    /// The tail reaches well outside the box, and grabbing it should pick
    /// the balloon.
    func testABalloonIsHitOnItsTail() {
        // The tail runs from the box's middle (40, 15) to its tip (120, 80).
        XCTAssertTrue(balloon().contains(CGPoint(x: 100, y: 64), in: imageRect, tolerance: 6))
        XCTAssertFalse(balloon().contains(CGPoint(x: 100, y: 20), in: imageRect, tolerance: 6))
    }

    // MARK: - Magnifier

    private func magnifier(focus: CGPoint? = nil, zoom: CGFloat = 2) -> Annotation {
        var style = AnnotationStyle.standard
        style.magnification = zoom
        return Annotation(
            tool: .magnifier,
            start: CGPoint(x: 0.4, y: 0.4),
            end: CGPoint(x: 0.8, y: 0.8),
            focus: focus,
            style: style
        )
    }

    /// Smaller by the magnification, centred on the magnifier until its
    /// focus is dragged elsewhere.
    func testAMagnifierEnlargesAnAreaAroundItsFocus() {
        assertRect(magnifier().sampledArea, CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2))
        assertRect(magnifier(zoom: 4).sampledArea, CGRect(x: 0.55, y: 0.55, width: 0.1, height: 0.1))
        assertRect(
            magnifier(focus: CGPoint(x: 0.1, y: 0.2)).sampledArea,
            CGRect(x: 0, y: 0.1, width: 0.2, height: 0.2)
        )
    }

    /// Aiming moves what it enlarges, starting from its own middle, and
    /// leaves the magnifier where it is.
    func testAimingAMagnifierLeavesItInPlace() throws {
        let aimed = magnifier().aimed(by: CGVector(dx: -0.5, dy: -0.4))
        let again = aimed.aimed(by: CGVector(dx: 0.1, dy: 0))

        assertPoint(try XCTUnwrap(aimed.focus), CGPoint(x: 0.1, y: 0.2))
        assertPoint(try XCTUnwrap(again.focus), CGPoint(x: 0.2, y: 0.2))
        assertRect(aimed.bounds, magnifier().bounds)
        XCTAssertTrue(aimed.isMagnifyingElsewhere)
        XCTAssertFalse(magnifier().isMagnifyingElsewhere)
    }

    func testAimingStopsAtTheCrop() throws {
        let crop = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)

        let aimed = magnifier().aimed(by: CGVector(dx: -0.9, dy: 0), within: crop)

        assertPoint(try XCTUnwrap(aimed.focus), CGPoint(x: 0.2, y: 0.6))
    }

    /// No handle in the middle, where it would take the drag that moves the
    /// magnifier; a round one has only corners, since it grows both ways.
    func testARoundMagnifierHasOnlyCornerHandles() {
        var square = magnifier()
        square.style.magnifierShape = .rectangle

        XCTAssertEqual(magnifier().handles.count, 4)
        XCTAssertEqual(square.handles.count, 8)
        XCTAssertFalse(magnifier().handles.contains(.tail))
    }

    /// Square in image points, not in annotation space: on a 200×100 image
    /// a circle is half as wide in fractions as it is tall.
    func testARoundMagnifierStaysACircleFromItsAnchor() {
        let drawn = Annotation(tool: .magnifier, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.6, y: 0.9))
        let squared = drawn.squared(imageSize: CGSize(width: 200, height: 100), from: CGPoint(x: 0.5, y: 0.5))

        // The longer side is 40 points tall, so 0.2 of the width.
        assertRect(squared.bounds, CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.4))

        let upward = drawn.squared(imageSize: CGSize(width: 200, height: 100), from: CGPoint(x: 0.6, y: 0.9))
        assertRect(upward.bounds, CGRect(x: 0.4, y: 0.5, width: 0.2, height: 0.4))
    }

    func testDraggingACornerAnchorsTheOppositeOne() {
        XCTAssertEqual(magnifier().anchor(opposite: .box(x: .max, y: .min)), CGPoint(x: 0.4, y: 0.8))
        XCTAssertNil(magnifier().anchor(opposite: .box(x: .max, y: nil)))
    }

    func testMovingAMagnifierTakesItsFocusAlong() throws {
        let moved = magnifier(focus: CGPoint(x: 0.1, y: 0.2)).moved(by: CGVector(dx: 0.1, dy: 0.1))

        assertPoint(try XCTUnwrap(moved.focus), CGPoint(x: 0.2, y: 0.3))
    }

    /// The marked area away from the magnifier is part of it, so a click
    /// there selects it.
    func testAMagnifierIsHitOnTheAreaItEnlarges() {
        // The area is x 0...0.2, y 0.1...0.3: (0...40, 10...30) in view space.
        XCTAssertTrue(magnifier(focus: CGPoint(x: 0.1, y: 0.2)).contains(CGPoint(x: 20, y: 20), in: imageRect, tolerance: 0))
        XCTAssertFalse(magnifier().contains(CGPoint(x: 20, y: 20), in: imageRect, tolerance: 0))
    }
}
