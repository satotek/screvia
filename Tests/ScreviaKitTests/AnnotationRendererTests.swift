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

        let flattened = AnnotationRenderer.flatten(threeTimesImage(), annotations: [annotation])
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

        let flattened = AnnotationRenderer.flatten(threeTimesImage(), annotations: [annotation])

        XCTAssertLessThan(pixel(of: flattened, x: 30, y: 30).b, 200, "top-left should be highlighted")
        XCTAssertEqual(pixel(of: flattened, x: 30, y: 120).b, 255, "bottom-left should be untouched")
    }

    func testAnUnannotatedImageIsReturnedAsIs() {
        let image = threeTimesImage()

        XCTAssertIdentical(AnnotationRenderer.flatten(image, annotations: []), image)
    }
}
