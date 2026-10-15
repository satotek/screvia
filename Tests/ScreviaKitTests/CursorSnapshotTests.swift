import AppKit
import XCTest

@testable import ScreviaKit

final class CursorSnapshotTests: XCTestCase {
    private func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return data[0]
    }

    /// A 10×10 red square as the pointer, hot spot at its top-left, over a
    /// black 2× screen of 100×100 points.
    func testThePointerLandsAtItsHotSpotInPixels() {
        let red = TestImages.solidCGImage(width: 10, height: 10, r: 255, g: 0, b: 0)
        let screen = TestImages.solidCGImage(width: 200, height: 200, r: 0, g: 0, b: 0)
        let cursor = CursorSnapshot(
            image: red,
            size: CGSize(width: 10, height: 10),
            hotSpot: .zero,
            location: CGPoint(x: 20, y: 30)
        )

        let result = cursor.drawn(onto: screen, pixelsPerPoint: 2)

        // Red channel, counted from the top: inside starts at (40, 60).
        XCTAssertEqual(alpha(of: result, x: 45, y: 65), 255, "inside the pointer")
        XCTAssertEqual(alpha(of: result, x: 35, y: 65), 0, "left of it")
        XCTAssertEqual(alpha(of: result, x: 45, y: 55), 0, "above it")
    }

    /// The hot spot, not the image's corner, goes where the pointer was.
    func testTheHotSpotShiftsTheImage() {
        let red = TestImages.solidCGImage(width: 10, height: 10, r: 255, g: 0, b: 0)
        let screen = TestImages.solidCGImage(width: 100, height: 100, r: 0, g: 0, b: 0)
        let cursor = CursorSnapshot(
            image: red,
            size: CGSize(width: 10, height: 10),
            hotSpot: CGPoint(x: 5, y: 5),
            location: CGPoint(x: 50, y: 50)
        )

        let result = cursor.drawn(onto: screen, pixelsPerPoint: 1)

        XCTAssertEqual(alpha(of: result, x: 46, y: 46), 255)
        XCTAssertEqual(alpha(of: result, x: 56, y: 56), 0)
    }
}
