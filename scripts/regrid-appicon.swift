import AppKit

// Apple's macOS icon grid: the artwork body occupies 824pt of a 1024pt canvas,
// leaving 100pt of transparency on every side. Filling the canvas edge to edge
// makes macOS wrap the icon in a second container of its own.
let canvas = 1024
let bodyWidth: CGFloat = 824

let srcURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let src = CGImageSourceCreateWithURL(srcURL as CFURL, nil),
      let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { exit(1) }

// Find the artwork's own bounds so the rescale is driven by the visible mark,
// not by whatever transparent padding the source happens to carry.
let w = cg.width, h = cg.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let probe = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
probe.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

var minX = w, minY = h, maxX = -1, maxY = -1
for y in 0..<h {
    for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 8 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
let bboxW = CGFloat(maxX - minX + 1), bboxH = CGFloat(maxY - minY + 1)
let scale = bodyWidth / bboxW

let out = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
out.interpolationQuality = .high

let drawW = CGFloat(w) * scale, drawH = CGFloat(h) * scale
// Offset so the artwork's bbox lands centred on the canvas.
let originX = (CGFloat(canvas) - bboxW * scale) / 2 - CGFloat(minX) * scale
let originY = (CGFloat(canvas) - bboxH * scale) / 2 - CGFloat(h - 1 - maxY) * scale
out.draw(cg, in: CGRect(x: originX, y: originY, width: drawW, height: drawH))

guard let image = out.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: outURL)
print("wrote \(outURL.lastPathComponent): body \(Int(bodyWidth))/\(canvas)")
