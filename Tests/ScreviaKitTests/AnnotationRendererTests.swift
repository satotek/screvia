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

    func testOtherToolsAreNotResizedByFitting() {
        let rectangle = Annotation(tool: .rectangle, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.4, y: 0.6))

        XCTAssertEqual(AnnotationRenderer.fitted(rectangle, imageSize: CGSize(width: 100, height: 100)), rectangle)
    }
}
