import AppKit
import CoreImage

/// Runs `filterName` over the `rect` region of `image` and returns just that
/// region, filtered.
///
/// Both the on-canvas preview and the flattened output go through here, so the
/// blur the user sees while editing is the blur that gets saved. Keeping them
/// on separate code paths is how they drifted apart in the first place.
///
/// `rect` is in the image's own (bottom-left origin) coordinate space.
func filteredRegion(
    of image: NSImage,
    in rect: CGRect,
    filterName: String
) -> NSImage? {
    guard rect.width > 1, rect.height > 1 else {
        return nil
    }

    let regionSize = NSSize(width: rect.width, height: rect.height)
    let region = NSImage(size: regionSize)
    region.lockFocus()
    image.draw(
        in: NSRect(origin: .zero, size: regionSize),
        from: rect,
        operation: .copy,
        fraction: 1
    )
    region.unlockFocus()

    var proposedRect = NSRect(origin: .zero, size: regionSize)
    guard
        let regionImage = region.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ),
        let filter = CIFilter(name: filterName)
    else {
        return nil
    }

    let input = CIImage(cgImage: regionImage)
    // Gaussian blur samples outside the source rect and would otherwise fade
    // the region's edges to transparent.
    let filterInput = filterName == "CIGaussianBlur" ? input.clampedToExtent() : input
    filter.setValue(filterInput, forKey: kCIInputImageKey)

    switch filterName {
    case "CIGaussianBlur":
        filter.setValue(max(5, min(rect.width, rect.height) * 0.08), forKey: kCIInputRadiusKey)
    case "CIPixellate":
        filter.setValue(max(8, min(rect.width, rect.height) * 0.06), forKey: kCIInputScaleKey)
    default:
        break
    }

    guard
        let output = filter.outputImage?.cropped(to: input.extent),
        let outputImage = CIContext().createCGImage(output, from: input.extent)
    else {
        return nil
    }

    return NSImage(cgImage: outputImage, size: regionSize)
}

/// Maps a normalized annotation (0...1, top-left origin) onto the image's own
/// bottom-left origin pixel space.
func imageSpaceRect(start: CGPoint, end: CGPoint, imageSize: CGSize) -> CGRect {
    let startPoint = CGPoint(x: start.x * imageSize.width, y: (1 - start.y) * imageSize.height)
    let endPoint = CGPoint(x: end.x * imageSize.width, y: (1 - end.y) * imageSize.height)
    return CGRect(
        x: min(startPoint.x, endPoint.x),
        y: min(startPoint.y, endPoint.y),
        width: abs(endPoint.x - startPoint.x),
        height: abs(endPoint.y - startPoint.y)
    )
}
