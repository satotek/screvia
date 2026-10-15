import CoreGraphics
import XCTest

@testable import ScreviaKit

final class CanvasLayoutTests: XCTestCase {
    private let container = CGSize(width: 448, height: 248)

    /// A 400×200 image in a 448×248 view fits exactly inside the margin.
    func testAnUncroppedImageFillsTheVisibleRect() {
        let layout = CanvasLayout(
            containerSize: container,
            imageSize: CGSize(width: 400, height: 200),
            crop: AnnotationSpace.unit,
            zoom: 1
        )

        XCTAssertEqual(layout.visibleRect, CGRect(x: 24, y: 24, width: 400, height: 200))
        XCTAssertEqual(layout.imageRect, layout.visibleRect)
    }

    /// Cropping to the right half shows that half at the size the view
    /// allows, and the whole image extends off to the left of it.
    func testACroppedImageRunsPastTheVisibleRect() {
        let layout = CanvasLayout(
            containerSize: container,
            imageSize: CGSize(width: 400, height: 200),
            crop: CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
            zoom: 1
        )

        XCTAssertEqual(layout.visibleRect.size, CGSize(width: 200, height: 200))
        XCTAssertEqual(layout.imageRect.width, 400)
        XCTAssertEqual(layout.imageRect.maxX, layout.visibleRect.maxX)
        XCTAssertEqual(
            AnnotationSpace.point(CGPoint(x: 0.5, y: 0), in: layout.imageRect),
            layout.visibleRect.origin
        )
    }

    func testZoomingPastTheViewGrowsTheScrollableContent() {
        let layout = CanvasLayout(
            containerSize: container,
            imageSize: CGSize(width: 400, height: 200),
            crop: AnnotationSpace.unit,
            zoom: 2
        )

        XCTAssertEqual(layout.contentSize, CGSize(width: 848, height: 448))
    }
}
