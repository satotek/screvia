import AppKit
import CoreImage

/// Reads single pixels of an image, for the editor's colour readout and
/// eyedropper.
///
/// It reads the full image, not the downsampled copy the canvas shows,
/// whose pixels are averages of their neighbours.
nonisolated struct PixelReader {
    let image: CGImage

    init?(_ image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        self.image = cgImage
    }

    /// The colour at `point`, a fraction of the image with a top-left
    /// origin, converted to sRGB as the annotation colours are.
    func color(at point: CGPoint) -> AnnotationColor? {
        let x = min(max(Int(point.x * CGFloat(image.width)), 0), image.width - 1)
        let y = min(max(Int(point.y * CGFloat(image.height)), 0), image.height - 1)
        // Cropping to the one pixel first keeps each read cheap however
        // large the capture is. CGImage cropping counts from the top.
        guard
            let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }

        var data = [UInt8](repeating: 0, count: 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else {
            return nil
        }

        // Shown and copied opaque: a hex code reads as the colour seen.
        let alpha = Double(data[3]) / 255
        func channel(_ value: UInt8) -> Double {
            alpha > 0 ? min(Double(value) / 255 / alpha, 1) : 0
        }
        return AnnotationColor(red: channel(data[0]), green: channel(data[1]), blue: channel(data[2]))
    }
}

nonisolated extension PixelReader {
    /// The part of the image inside a plain border, as a fraction with a
    /// top-left origin, for Auto Crop: rows and columns at the edges that
    /// are all within `tolerance` of the top-left corner's colour are left
    /// out. Nil when there is no such border, or nothing but it.
    func contentBounds(tolerance: Int = 8) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return nil
        }

        // The bitmap's first row is the image's top.
        let corner = Array(pixels[0..<4])
        func isBorder(_ x: Int, _ y: Int) -> Bool {
            let offset = (y * width + x) * 4
            return (0..<4).allSatisfy { abs(Int(pixels[offset + $0]) - Int(corner[$0])) <= tolerance }
        }
        func rowIsBorder(_ y: Int) -> Bool { (0..<width).allSatisfy { isBorder($0, y) } }
        func columnIsBorder(_ x: Int, from top: Int, to bottom: Int) -> Bool {
            (top...bottom).allSatisfy { isBorder(x, $0) }
        }

        var top = 0
        while top < height, rowIsBorder(top) { top += 1 }
        guard top < height else {
            return nil
        }
        var bottom = height - 1
        while bottom > top, rowIsBorder(bottom) { bottom -= 1 }
        var left = 0
        while left < width, columnIsBorder(left, from: top, to: bottom) { left += 1 }
        var right = width - 1
        while right > left, columnIsBorder(right, from: top, to: bottom) { right -= 1 }

        guard top > 0 || left > 0 || bottom < height - 1 || right < width - 1 else {
            return nil
        }
        return CGRect(
            x: CGFloat(left) / CGFloat(width),
            y: CGFloat(top) / CGFloat(height),
            width: CGFloat(right - left + 1) / CGFloat(width),
            height: CGFloat(bottom - top + 1) / CGFloat(height)
        )
    }
}

// CIContext is expensive to create, and the eyedropper may average often.
// It averages the sRGB values themselves, as design tools do; Core Image's
// default linear space would make red and blue average to a lighter purple.
private nonisolated let averagingContext = CIContext(options: [
    .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
])

nonisolated extension PixelReader {
    /// The average colour of `area`, a part of the image in fractions with a
    /// top-left origin, as Shottr's Copy Average Color gives.
    func averageColor(in area: CGRect) -> AnnotationColor? {
        let pixels = CGRect(
            x: area.minX * CGFloat(image.width),
            y: area.minY * CGFloat(image.height),
            width: area.width * CGFloat(image.width),
            height: area.height * CGFloat(image.height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard
            !pixels.isEmpty,
            let region = image.cropping(to: pixels),
            let filter = CIFilter(name: "CIAreaAverage"),
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }

        let input = CIImage(cgImage: region)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: input.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else {
            return nil
        }

        var data = [UInt8](repeating: 0, count: 4)
        averagingContext.render(
            output,
            toBitmap: &data,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: sRGB
        )
        return AnnotationColor(red: Double(data[0]) / 255, green: Double(data[1]) / 255, blue: Double(data[2]) / 255)
    }
}

/// How a picked colour is written when copied: the forms Shottr and design
/// tools offer, for pasting into CSS, Swift or a design tool.
nonisolated enum ColorCodeFormat: String, CaseIterable, Identifiable {
    case hex
    case hexWithoutHash
    case cssRGB
    case cssHSL
    case swiftUI
    case uiColor

    var id: String { rawValue }

    var title: String {
        L10n.text("colorFormat.\(rawValue)")
    }

    func code(for color: AnnotationColor) -> String {
        func byte(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        func fraction(_ value: Double) -> String {
            String(format: "%.2f", min(max(value, 0), 1))
        }

        switch self {
        case .hex:
            return color.hexString
        case .hexWithoutHash:
            return String(color.hexString.dropFirst())
        case .cssRGB:
            return "rgb(\(byte(color.red)), \(byte(color.green)), \(byte(color.blue)))"
        case .cssHSL:
            let hsl = color.hsl
            return "hsl(\(Int(hsl.hue.rounded())), \(Int((hsl.saturation * 100).rounded()))%, \(Int((hsl.lightness * 100).rounded()))%)"
        case .swiftUI:
            return "Color(red: \(fraction(color.red)), green: \(fraction(color.green)), blue: \(fraction(color.blue)))"
        case .uiColor:
            return "UIColor(red: \(fraction(color.red)), green: \(fraction(color.green)), blue: \(fraction(color.blue)), alpha: 1)"
        }
    }
}

nonisolated extension AnnotationColor {
    /// Hue in degrees, saturation and lightness from 0 to 1, as CSS's hsl().
    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let lightness = (high + low) / 2
        let chroma = high - low
        guard chroma > 0 else {
            return (0, 0, lightness)
        }

        let saturation = chroma / (1 - abs(2 * lightness - 1))
        let hue: Double
        switch high {
        case red:
            hue = (green - blue) / chroma + (green < blue ? 6 : 0)
        case green:
            hue = (blue - red) / chroma + 2
        default:
            hue = (red - green) / chroma + 4
        }
        return (hue * 60, saturation, lightness)
    }
}
