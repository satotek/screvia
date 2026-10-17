import AppKit
import XCTest

@testable import ScreviaKit

final class ImageOrientationTests: XCTestCase {
    /// Where a point of the original lands as shown, worked out from the
    /// orientation alone: mirrored first, then turned clockwise.
    private func shown(_ point: CGPoint, _ orientation: ImageOrientation) -> CGPoint {
        var point = orientation.isMirrored ? CGPoint(x: 1 - point.x, y: point.y) : point
        for _ in 0..<orientation.quarterTurns {
            point = ImageOrientationChange.rotateRight.map(point)
        }
        return point
    }

    /// Any run of changes leaves an orientation that shows each point where
    /// making those changes one by one would have put it.
    func testChangesComposeIntoOneOrientation() {
        let runs: [[ImageOrientationChange]] = [
            [.rotateRight], [.rotateLeft], [.flipHorizontal], [.flipVertical],
            [.rotateRight, .flipHorizontal], [.flipHorizontal, .rotateRight],
            [.rotateLeft, .flipVertical, .rotateLeft], [.flipVertical, .flipHorizontal, .rotateRight, .rotateRight]
        ]
        let point = CGPoint(x: 0.2, y: 0.1)
        for run in runs {
            let orientation = run.reduce(ImageOrientation()) { $0.applying($1) }
            let expected = run.reduce(point) { $1.map($0) }
            let actual = shown(point, orientation)
            XCTAssertEqual(actual.x, expected.x, accuracy: 1e-9, "\(run)")
            XCTAssertEqual(actual.y, expected.y, accuracy: 1e-9, "\(run)")
        }
    }

    func testFourTurnsAndTwoFlipsAreNothing() {
        let turned = (0..<4).reduce(ImageOrientation()) { orientation, _ in orientation.applying(.rotateRight) }
        let flipped = ImageOrientation().applying(.flipHorizontal).applying(.flipHorizontal)

        XCTAssertTrue(turned.isIdentity)
        XCTAssertTrue(flipped.isIdentity)
    }

    /// Red in the top-left quarter of a 40×20 image; turned right, it is
    /// 20×40 with the red at the top right.
    func testTurningTheImage() throws {
        let cgImage = TestImages.cgImage(width: 40, height: 20) { _ in (255, 255, 255) }
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 40, height: 20))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        // Bottom-left origin: the top-left quarter.
        context.fill(CGRect(x: 0, y: 10, width: 20, height: 10))
        let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: 40, height: 20))

        let turned = ImageOrientation(quarterTurns: 1).applied(to: image)
        let reader = try XCTUnwrap(PixelReader(turned))

        XCTAssertEqual(turned.size, NSSize(width: 20, height: 40))
        // Device red, read back in sRGB, is not quite #FF0000.
        let topRight = try XCTUnwrap(reader.color(at: CGPoint(x: 0.75, y: 0.25)))
        XCTAssertGreaterThan(topRight.red, 0.9)
        XCTAssertLessThan(topRight.green, 0.3)
        XCTAssertEqual(reader.color(at: CGPoint(x: 0.25, y: 0.25))?.hexString, "#FFFFFF")
    }

    /// A box turns with the picture; a label keeps its size in points and
    /// moves by its middle.
    func testAnnotationsTurnWithTheImage() {
        let box = Annotation(tool: .rectangle, start: CGPoint(x: 0.1, y: 0.2), end: CGPoint(x: 0.3, y: 0.4))
        // 40×20 points on a 200×100 image.
        let label = Annotation(tool: .text, start: CGPoint(x: 0.1, y: 0.6), end: CGPoint(x: 0.3, y: 0.8), text: "A")
        let document = AnnotationDocument(annotations: [box, label], crop: CGRect(x: 0, y: 0, width: 0.5, height: 1))

        let turned = document.reoriented(.rotateRight, imageSize: CGSize(width: 200, height: 100))

        XCTAssertEqual(turned.orientation, ImageOrientation(quarterTurns: 1))
        XCTAssertEqual(turned.crop.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(turned.crop.height, 0.5, accuracy: 1e-9)
        let turnedBox = turned.annotations[0].bounds
        XCTAssertEqual(turnedBox.minX, 0.6, accuracy: 1e-9)
        XCTAssertEqual(turnedBox.minY, 0.1, accuracy: 1e-9)
        // Now 100×200: still 40×20 points, around the turned middle.
        let turnedLabel = turned.annotations[1].bounds
        XCTAssertEqual(turnedLabel.width * 100, 40, accuracy: 1e-9)
        XCTAssertEqual(turnedLabel.height * 200, 20, accuracy: 1e-9)
        XCTAssertEqual(turnedLabel.midX, 0.3, accuracy: 1e-9)
        XCTAssertEqual(turnedLabel.midY, 0.2, accuracy: 1e-9)
    }
}
