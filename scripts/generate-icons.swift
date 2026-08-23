import AppKit
import CoreGraphics
import Foundation

let side: CGFloat = 18
let stroke: CGFloat = 1.6

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// A: four crop brackets around a solid centre dot.
func drawBrackets(_ c: CGContext) {
    c.setLineWidth(stroke)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.setStrokeColor(NSColor.black.cgColor)

    let inset: CGFloat = 2.2
    let arm: CGFloat = 4.6
    let lo = inset, hi = side - inset

    let corners: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: lo, y: hi - arm), CGPoint(x: lo, y: hi), CGPoint(x: lo + arm, y: hi)),
        (CGPoint(x: hi - arm, y: hi), CGPoint(x: hi, y: hi), CGPoint(x: hi, y: hi - arm)),
        (CGPoint(x: hi, y: lo + arm), CGPoint(x: hi, y: lo), CGPoint(x: hi - arm, y: lo)),
        (CGPoint(x: lo + arm, y: lo), CGPoint(x: lo, y: lo), CGPoint(x: lo, y: lo + arm))
    ]

    for (a, b, d) in corners {
        c.move(to: a)
        c.addLine(to: b)
        c.addLine(to: d)
    }
    c.strokePath()

    c.setFillColor(NSColor.black.cgColor)
    c.fillEllipse(in: CGRect(x: side / 2 - 1.7, y: side / 2 - 1.7, width: 3.4, height: 3.4))
}

/// B: an outlined frame with a solid region cut into its lower-right.
func drawRegion(_ c: CGContext) {
    c.setLineWidth(stroke)
    c.setLineJoin(.round)
    c.setStrokeColor(NSColor.black.cgColor)
    c.addPath(roundedPath(CGRect(x: 2.3, y: 2.3, width: side - 4.6, height: side - 4.6), 3.4))
    c.strokePath()

    c.setFillColor(NSColor.black.cgColor)
    c.addPath(roundedPath(CGRect(x: 7.6, y: 4.6, width: 7.4, height: 7.4), 2.2))
    c.fillPath()
}

/// C: two stacked sheets — the capture behind, the copy in front.
func drawLayers(_ c: CGContext) {
    c.setFillColor(NSColor.black.withAlphaComponent(0.38).cgColor)
    c.addPath(roundedPath(CGRect(x: 2.2, y: 5.6, width: 10.2, height: 10.2), 2.8))
    c.fillPath()

    c.setFillColor(NSColor.black.cgColor)
    c.addPath(roundedPath(CGRect(x: 5.6, y: 2.2, width: 10.2, height: 10.2), 2.8))
    c.fillPath()
}

let designs: [(String, (CGContext) -> Void)] = [
    ("brackets", drawBrackets),
    ("region", drawRegion),
    ("layers", drawLayers)
]

let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("icons")

for (name, draw) in designs {
    // Vector PDF — the asset the app ships.
    var box = CGRect(x: 0, y: 0, width: side, height: side)
    let pdfURL = dir.appendingPathComponent("\(name).pdf")
    guard let pdf = CGContext(pdfURL as CFURL, mediaBox: &box, nil) else { continue }
    pdf.beginPDFPage(nil)
    draw(pdf)
    pdf.endPDFPage()
    pdf.closePDF()

    // PNG previews: actual menu bar size, and 12x for inspection.
    for scale in [2, 12] as [Int] {
        let pixels = Int(side) * scale
        guard let bmp = CGContext(
            data: nil, width: pixels, height: pixels,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { continue }
        bmp.setFillColor(NSColor.white.cgColor)
        bmp.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        bmp.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        draw(bmp)
        guard let img = bmp.makeImage() else { continue }
        let rep = NSBitmapImageRep(cgImage: img)
        let data = rep.representation(using: .png, properties: [:])
        try? data?.write(to: dir.appendingPathComponent("\(name)@\(scale)x.png"))
    }
    print("generated \(name)")
}
