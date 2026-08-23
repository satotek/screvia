import AppKit
import XCTest

@testable import ScreviaKit

final class ImageProcessorTests: XCTestCase {
    private let processor = ImageProcessor()

    private func options(
        background: BackgroundStyle = .none,
        padding: CGFloat = 0,
        cornerRadius: CGFloat = 0,
        shadow: Bool = false
    ) -> CaptureStyleOptions {
        CaptureStyleOptions(
            backgroundStyle: background,
            padding: padding,
            cornerRadius: cornerRadius,
            shadowEnabled: shadow
        )
    }

    // MARK: - Pass-through

    /// With no background, no padding and no shadow there is nothing to draw,
    /// so the processor must hand back the original rather than paying for a
    /// full redraw on every capture.
    func testUnstyledCapturesAreReturnedUntouched() {
        let image = TestImages.nsImage(width: 100, height: 50)

        let result = processor.process(image, options: options())

        XCTAssertIdentical(result, image)
    }

    func testCornerRadiusAloneDoesNotTriggerARedraw() {
        // Rounding needs something to round against; with no background or
        // padding there is no visible frame to apply it to.
        let image = TestImages.nsImage(width: 100, height: 50)

        let result = processor.process(image, options: options(cornerRadius: 20))

        XCTAssertIdentical(result, image)
    }

    // MARK: - Padding

    func testPaddingGrowsTheCanvasOnEverySide() {
        let image = TestImages.nsImage(width: 100, height: 50)

        let result = processor.process(image, options: options(padding: 20))

        XCTAssertEqual(result.size.width, 140)
        XCTAssertEqual(result.size.height, 90)
    }

    func testBackgroundAloneKeepsTheOriginalDimensions() {
        let image = TestImages.nsImage(width: 100, height: 50)

        let result = processor.process(image, options: options(background: .mist))

        XCTAssertNotIdentical(result, image)
        XCTAssertEqual(result.size.width, 100)
        XCTAssertEqual(result.size.height, 50)
    }

    // MARK: - Shadow

    /// The shadow is drawn outside the image, so the canvas has to reserve
    /// room for it or it would be clipped away.
    func testShadowReservesAMarginAroundTheImage() {
        let image = TestImages.nsImage(width: 100, height: 50)

        let result = processor.process(image, options: options(shadow: true))

        XCTAssertEqual(result.size.width, 100 + 32 * 2)
        XCTAssertEqual(result.size.height, 50 + 32 * 2)
    }

    func testPaddingAndShadowMarginsAccumulate() {
        let image = TestImages.nsImage(width: 100, height: 50)

        let result = processor.process(
            image,
            options: options(background: .paper, padding: 10, shadow: true)
        )

        XCTAssertEqual(result.size.width, 100 + (10 + 32) * 2)
        XCTAssertEqual(result.size.height, 50 + (10 + 32) * 2)
    }

    // MARK: - Robustness

    func testAVeryLargeCornerRadiusDoesNotProduceAnInvalidCanvas() {
        let image = TestImages.nsImage(width: 40, height: 20)

        // The radius is clamped to half the shorter side internally; the point
        // here is that an extreme value still yields a drawable image.
        let result = processor.process(
            image,
            options: options(background: .midnight, padding: 5, cornerRadius: 9_999)
        )

        XCTAssertEqual(result.size.width, 50)
        XCTAssertEqual(result.size.height, 30)
        XCTAssertNotNil(result.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    func testEveryBackgroundStyleProducesADrawableImage() {
        let image = TestImages.nsImage(width: 30, height: 30)

        for style in BackgroundStyle.allCases {
            let result = processor.process(
                image,
                options: options(background: style, padding: 8)
            )

            XCTAssertNotNil(
                result.cgImage(forProposedRect: nil, context: nil, hints: nil),
                "\(style.rawValue) should render"
            )
        }
    }
}
