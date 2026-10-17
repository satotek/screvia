import AppKit
import XCTest

@testable import ScreviaKit

final class PixelReaderTests: XCTestCase {
    /// Red above row 10 and blue below, at 2× (40×40 pixels in 20×20
    /// points), so a flipped read would swap them.
    private func reader() throws -> PixelReader {
        let cgImage = TestImages.cgImage(width: 40, height: 40) { y in y < 10 ? (255, 0, 0) : (0, 0, 255) }
        return try XCTUnwrap(PixelReader(NSImage(cgImage: cgImage, size: NSSize(width: 20, height: 20))))
    }

    func testReadsFromTheTop() throws {
        XCTAssertEqual(try reader().color(at: CGPoint(x: 0.5, y: 0.1))?.hexString, "#FF0000")
        XCTAssertEqual(try reader().color(at: CGPoint(x: 0.5, y: 0.9))?.hexString, "#0000FF")
    }

    /// The last row and column are 1, not past the end.
    func testTheFarEdgeIsInside() throws {
        XCTAssertEqual(try reader().color(at: CGPoint(x: 1, y: 1))?.hexString, "#0000FF")
    }

    func testHexCodesAreTwoDigitsPerChannel() {
        XCTAssertEqual(AnnotationColor(red: 0, green: 0.5, blue: 1).hexString, "#0080FF")
    }

    /// A quarter red and three quarters blue: the sRGB values averaged, as
    /// design tools do, not averaged as light.
    func testAnAreaAveragesItsColours() throws {
        let average = try XCTUnwrap(try reader().averageColor(in: CGRect(x: 0, y: 0, width: 1, height: 1)))

        XCTAssertEqual(average.red * 255, 64, accuracy: 2)
        XCTAssertEqual(average.blue * 255, 191, accuracy: 2)
        XCTAssertEqual(try reader().averageColor(in: CGRect(x: 0, y: 0, width: 1, height: 0.2))?.hexString, "#FF0000")
    }

    func testColourCodes() {
        let color = AnnotationColor(red: 17 / 255, green: 123 / 255, blue: 251 / 255)

        XCTAssertEqual(ColorCodeFormat.hex.code(for: color), "#117BFB")
        XCTAssertEqual(ColorCodeFormat.hexWithoutHash.code(for: color), "117BFB")
        XCTAssertEqual(ColorCodeFormat.cssRGB.code(for: color), "rgb(17, 123, 251)")
        XCTAssertEqual(ColorCodeFormat.cssHSL.code(for: color), "hsl(213, 97%, 53%)")
        XCTAssertEqual(ColorCodeFormat.swiftUI.code(for: color), "Color(red: 0.07, green: 0.48, blue: 0.98)")
        XCTAssertEqual(ColorCodeFormat.uiColor.code(for: color), "UIColor(red: 0.07, green: 0.48, blue: 0.98, alpha: 1)")
    }

    func testGreysHaveNoHue() {
        XCTAssertEqual(ColorCodeFormat.cssHSL.code(for: AnnotationColor(red: 0.5, green: 0.5, blue: 0.5)), "hsl(0, 0%, 50%)")
    }

    /// White all round a black block: Auto Crop keeps just the block.
    func testContentBoundsLeaveOutAPlainBorder() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        // Bottom-left origin: columns 20..<70, rows 10..<30 from the top.
        context.fill(CGRect(x: 20, y: 20, width: 50, height: 20))
        let reader = try XCTUnwrap(PixelReader(NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 100, height: 50))))

        let bounds = try XCTUnwrap(reader.contentBounds())

        XCTAssertEqual(bounds.minX, 0.2, accuracy: 1e-9)
        XCTAssertEqual(bounds.minY, 0.2, accuracy: 1e-9)
        XCTAssertEqual(bounds.width, 0.5, accuracy: 1e-9)
        XCTAssertEqual(bounds.height, 0.4, accuracy: 1e-9)
    }

    func testAPlainImageHasNoContentToTrimTo() throws {
        XCTAssertNil(try XCTUnwrap(PixelReader(TestImages.nsImage(width: 10, height: 10))).contentBounds())
    }
}
