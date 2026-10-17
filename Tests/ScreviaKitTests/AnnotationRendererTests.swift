import AppKit
import XCTest

@testable import ScreviaKit

final class AnnotationRendererTests: XCTestCase {
    /// RGBA of one pixel, `y` counted from the top.
    private func pixel(of image: NSImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(
            cgImage,
            in: CGRect(x: -x, y: y - cgImage.height + 1, width: cgImage.width, height: cgImage.height)
        )
        return (data[0], data[1], data[2])
    }

    /// A 3× capture: 300×150 pixels in a 100×50 point image.
    private func threeTimesImage() -> NSImage {
        NSImage(
            cgImage: TestImages.solidCGImage(width: 300, height: 150, r: 255, g: 255, b: 255),
            size: NSSize(width: 100, height: 50)
        )
    }

    /// Drawing through `lockFocus` produced an image at the main screen's
    /// scale, not the capture's, so a capture from a sharper screen than the
    /// main one was saved at reduced resolution.
    func testFlatteningKeepsTheCapturesPixels() {
        let annotation = Annotation(tool: .rectangle, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.5, y: 0.5))

        let flattened = AnnotationRenderer.flatten(threeTimesImage(), document: AnnotationDocument(annotations: [annotation]))
        let cgImage = flattened.cgImage(forProposedRect: nil, context: nil, hints: nil)!

        XCTAssertEqual(cgImage.width, 300)
        XCTAssertEqual(cgImage.height, 150)
        XCTAssertEqual(flattened.size, NSSize(width: 100, height: 50))
    }

    /// Annotation space has a top-left origin and CGImage drawing a bottom-left
    /// one; a missing flip would put the shape in the bottom half.
    func testShapesLandWhereTheyWereDrawn() {
        // The top-left quarter, with a 4-point (12-pixel) stroke.
        let annotation = Annotation(tool: .highlight, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0.5, y: 0.5))

        let flattened = AnnotationRenderer.flatten(threeTimesImage(), document: AnnotationDocument(annotations: [annotation]))

        XCTAssertLessThan(pixel(of: flattened, x: 30, y: 30).b, 200, "top-left should be highlighted")
        XCTAssertEqual(pixel(of: flattened, x: 30, y: 120).b, 255, "bottom-left should be untouched")
    }

    func testAnUnannotatedImageIsReturnedAsIs() {
        let image = threeTimesImage()

        XCTAssertIdentical(AnnotationRenderer.flatten(image, document: AnnotationDocument()), image)
    }

    // MARK: - Crop

    /// The crop is in annotation space; export turns it into pixels, so a
    /// 3× capture cropped to its right half is 150 pixels wide, not 50.
    func testCroppingKeepsFullResolution() {
        let document = AnnotationDocument(crop: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))

        let flattened = AnnotationRenderer.flatten(threeTimesImage(), document: document)
        let cgImage = flattened.cgImage(forProposedRect: nil, context: nil, hints: nil)!

        XCTAssertEqual(cgImage.width, 150)
        XCTAssertEqual(cgImage.height, 150)
        XCTAssertEqual(flattened.size, NSSize(width: 50, height: 50))
    }

    /// Cropping counts from the top, like annotation space: keeping the top
    /// half must keep the highlight drawn there.
    func testCroppingKeepsTheTopWhenAskedForTheTop() {
        let document = AnnotationDocument(
            annotations: [
                Annotation(tool: .highlight, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1, y: 0.5))
            ],
            crop: CGRect(x: 0, y: 0, width: 1, height: 0.5)
        )

        let flattened = AnnotationRenderer.flatten(threeTimesImage(), document: document)

        XCTAssertLessThan(pixel(of: flattened, x: 150, y: 40).b, 200)
    }

    // MARK: - Sizing

    /// Text boxes follow the font size, not the drag, and keep their corner.
    func testTextBoxesGrowWithTheFontSize() {
        var style = AnnotationStyle.standard
        style.fontSize = 20
        let small = AnnotationRenderer.fitted(
            Annotation(tool: .text, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.1, y: 0.1), text: "Hello", style: style),
            imageSize: CGSize(width: 1000, height: 1000)
        )
        style.fontSize = 40
        var large = small
        large.style = style
        large = AnnotationRenderer.fitted(large, imageSize: CGSize(width: 1000, height: 1000))

        XCTAssertEqual(small.bounds.origin, CGPoint(x: 0.1, y: 0.1))
        XCTAssertEqual(large.bounds.origin, CGPoint(x: 0.1, y: 0.1))
        XCTAssertGreaterThan(large.bounds.width, small.bounds.width * 1.6)
        XCTAssertGreaterThan(large.bounds.height, small.bounds.height * 1.6)
    }

    /// A step is a circle whatever the image's shape, so its box is square
    /// in image points even though annotation space is not.
    func testStepsAreSquareInImagePoints() {
        let step = AnnotationRenderer.fitted(
            Annotation(tool: .step, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5)),
            imageSize: CGSize(width: 800, height: 200)
        )

        XCTAssertEqual(step.bounds.width * 800, step.bounds.height * 200, accuracy: 1e-6)
    }

    /// Switching a magnifier to round makes it the largest circle inside
    /// its box, around the same middle.
    func testFittingARoundMagnifierMakesItACircle() {
        let magnifier = Annotation(tool: .magnifier, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.5, y: 0.3))

        let fitted = AnnotationRenderer.fitted(magnifier, imageSize: CGSize(width: 100, height: 100))

        XCTAssertEqual(fitted.bounds.width, 0.2, accuracy: 1e-9)
        XCTAssertEqual(fitted.bounds.height, 0.2, accuracy: 1e-9)
        XCTAssertEqual(fitted.bounds.midX, 0.3, accuracy: 1e-9)
    }

    func testOtherToolsAreNotResizedByFitting() {
        let rectangle = Annotation(tool: .rectangle, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.4, y: 0.6))

        XCTAssertEqual(AnnotationRenderer.fitted(rectangle, imageSize: CGSize(width: 100, height: 100)), rectangle)
    }

    // MARK: - Balloons and the magnifier

    func testABalloonsTailReachesWhatItPointsAt() {
        var style = AnnotationStyle.standard
        style.fillColor = .blue
        let balloon = Annotation(
            tool: .balloon,
            start: CGPoint(x: 0.1, y: 0.1),
            end: CGPoint(x: 0.4, y: 0.3),
            text: "",
            tail: CGPoint(x: 0.8, y: 0.9),
            style: style
        )

        let flattened = AnnotationRenderer.flatten(threeTimesImage(), document: AnnotationDocument(annotations: [balloon]))

        // Near the tip, on the line from the box's middle: (0.745, 0.83).
        XCTAssertLessThan(pixel(of: flattened, x: 223, y: 124).g, 200, "the tail should reach its tip")
        XCTAssertEqual(pixel(of: flattened, x: 223, y: 30).g, 255, "beside the tail should be untouched")
    }

    /// Black above row 30 and white below. Shown as it is, the top of a
    /// magnifier covering the whole height would be black; enlarged twice
    /// about the middle, it starts at a quarter of the way down, in white.
    func testTheMagnifierEnlargesTheMiddleOfItsRegion() {
        let image = NSImage(
            cgImage: TestImages.cgImage(width: 300, height: 150) { y in y < 30 ? (0, 0, 0) : (255, 255, 255) },
            size: NSSize(width: 100, height: 50)
        )
        let magnifier = Annotation(tool: .magnifier, start: CGPoint(x: 0.1, y: 0), end: CGPoint(x: 0.9, y: 1))

        let flattened = AnnotationRenderer.flatten(image, document: AnnotationDocument(annotations: [magnifier]))

        XCTAssertEqual(pixel(of: flattened, x: 150, y: 20).b, 255, "inside should be enlarged")
        XCTAssertEqual(pixel(of: flattened, x: 10, y: 20).b, 0, "outside should be as it was")
    }

    // MARK: - Image effects

    /// Six points on each side of a 3× capture is 18 pixels, and the image
    /// itself keeps every pixel inside it.
    func testABorderFramesTheImageAtFullResolution() {
        var document = AnnotationDocument()
        document.effects.borderColor = .black
        document.effects.borderWidth = 6

        let flattened = AnnotationRenderer.flatten(threeTimesImage(), document: document)
        let cgImage = flattened.cgImage(forProposedRect: nil, context: nil, hints: nil)!

        XCTAssertEqual(cgImage.width, 336)
        XCTAssertEqual(cgImage.height, 186)
        XCTAssertEqual(flattened.size, NSSize(width: 112, height: 62))
        XCTAssertEqual(pixel(of: flattened, x: 9, y: 93).b, 0, "the border")
        XCTAssertEqual(pixel(of: flattened, x: 168, y: 93).b, 255, "the image")
    }

    func testAShadowLeavesRoomAroundTheImage() {
        var document = AnnotationDocument()
        document.effects.hasShadow = true

        let flattened = AnnotationRenderer.flatten(threeTimesImage(), document: document)

        let margin = ImageEffects.shadowMargin
        XCTAssertEqual(flattened.size, NSSize(width: 100 + margin * 2, height: 50 + margin * 2))
    }

    /// Effects frame what is kept, not the whole capture.
    func testEffectsFrameTheCrop() {
        var document = AnnotationDocument(crop: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        document.effects.borderColor = .red
        document.effects.borderWidth = 2

        let flattened = AnnotationRenderer.flatten(threeTimesImage(), document: document)

        XCTAssertEqual(flattened.size, NSSize(width: 54, height: 54))
    }

    /// Black above row 30 and white below, at 3× (300×150 pixels).
    private func blackTopImage() -> NSImage {
        NSImage(
            cgImage: TestImages.cgImage(width: 300, height: 150) { y in y < 30 ? (0, 0, 0) : (255, 255, 255) },
            size: NSSize(width: 100, height: 50)
        )
    }

    /// Placed in the white bottom half and aimed at the black top, the
    /// magnifier shows black.
    func testAMagnifierShowsItsFocusNotWhatIsUnderIt() {
        let magnifier = Annotation(
            tool: .magnifier,
            start: CGPoint(x: 0.5, y: 0.5),
            end: CGPoint(x: 0.9, y: 0.95),
            focus: CGPoint(x: 0.2, y: 0.05)
        )

        let flattened = AnnotationRenderer.flatten(blackTopImage(), document: AnnotationDocument(annotations: [magnifier]))

        XCTAssertEqual(pixel(of: flattened, x: 210, y: 110).b, 0, "the magnifier should show the black top")
        XCTAssertEqual(pixel(of: flattened, x: 210, y: 60).b, 255, "outside it, the image is as it was")
    }

    /// A round magnifier leaves its box's corners alone.
    func testARoundMagnifierEnlargesOnlyInsideTheCircle() {
        var style = AnnotationStyle.standard
        style.magnifierShape = .circle
        style.lineWidth = 1
        let magnifier = Annotation(
            tool: .magnifier,
            start: CGPoint(x: 0.1, y: 0.4),
            end: CGPoint(x: 0.9, y: 1),
            focus: CGPoint(x: 0.5, y: 0.1),
            style: style
        )

        let flattened = AnnotationRenderer.flatten(blackTopImage(), document: AnnotationDocument(annotations: [magnifier]))

        XCTAssertEqual(pixel(of: flattened, x: 150, y: 105).b, 0, "the middle is enlarged black")
        XCTAssertEqual(pixel(of: flattened, x: 36, y: 64).b, 255, "the corner is untouched")
    }

    /// Aimed past the edge, the area slides back inside rather than being
    /// cut, which would stretch it to fill the magnifier.
    func testAMagnifierAimedPastTheEdgeKeepsItsProportions() throws {
        let image = TestImages.solidCGImage(width: 100, height: 100)

        let region = try XCTUnwrap(sampledRegion(for: .magnifier, of: image, in: CGRect(x: 80, y: -10, width: 40, height: 20)))

        XCTAssertEqual(region.width, 40)
        XCTAssertEqual(region.height, 20)
    }

    // MARK: - Arrows and corners

    /// A white 3× image (300×150 pixels), red arrow across the middle.
    private func flattenedArrow(_ configure: (inout AnnotationStyle) -> Void, bend: CGPoint? = nil) -> NSImage {
        var style = AnnotationStyle.standard
        style.lineWidth = 2
        configure(&style)
        let arrow = Annotation(
            tool: .arrow,
            start: CGPoint(x: 0.1, y: 0.5),
            end: CGPoint(x: 0.9, y: 0.5),
            bend: bend,
            style: style
        )
        return AnnotationRenderer.flatten(threeTimesImage(), document: AnnotationDocument(annotations: [arrow]))
    }

    /// Inside the head, a little behind the tip and off the line: an open
    /// head leaves it white, a filled one covers it.
    func testAFilledHeadIsFilled() {
        // The tip is at x 270; the head runs back 36 pixels at ±30°.
        XCTAssertEqual(pixel(of: flattenedArrow { $0.arrowHead = .open }, x: 250, y: 80).g, 255)
        XCTAssertLessThan(pixel(of: flattenedArrow { $0.arrowHead = .filled }, x: 250, y: 80).g, 100)
    }

    func testHeadsAtBothEnds() {
        let single = flattenedArrow { $0.arrowHead = .filled }
        let double = flattenedArrow { $0.arrowHead = .filled; $0.arrowBothEnds = true }

        XCTAssertEqual(pixel(of: single, x: 50, y: 80).g, 255, "no head at the start")
        XCTAssertLessThan(pixel(of: double, x: 50, y: 80).g, 100, "a head at the start")
    }

    /// Bent up through (0.5, 0.2): the middle of the image's width is
    /// drawn at the bend, not on the straight line below it.
    func testABentArrowIsDrawnThroughItsBend() {
        let bent = flattenedArrow({ _ in }, bend: CGPoint(x: 0.5, y: 0.2))

        XCTAssertLessThan(pixel(of: bent, x: 150, y: 30).g, 100, "at the bend")
        XCTAssertEqual(pixel(of: bent, x: 150, y: 75).g, 255, "not on the straight line")
    }

    /// The corner of the box is left out once it is rounded.
    func testRoundedCornersLeaveTheCornerOut() {
        func corner(radius: CGFloat) -> UInt8 {
            var style = AnnotationStyle.standard
            style.lineWidth = 2
            style.cornerRadius = radius
            let box = Annotation(tool: .rectangle, start: CGPoint(x: 0.1, y: 0.2), end: CGPoint(x: 0.9, y: 0.8), style: style)
            let flattened = AnnotationRenderer.flatten(threeTimesImage(), document: AnnotationDocument(annotations: [box]))
            return pixel(of: flattened, x: 30, y: 30).g
        }

        XCTAssertLessThan(corner(radius: 0), 100)
        XCTAssertEqual(corner(radius: 16), 255)
    }
}
