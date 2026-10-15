import CoreGraphics
import CoreImage

// CIContext is thread-safe and expensive to create; the canvas filters again
// on every edit to a blurred region, so it shares one.
private nonisolated let filterContext = CIContext()

/// Runs `filterName` over the `rect` region of `image` and returns just that
/// region, filtered.
///
/// Both the on-canvas preview and the flattened output go through here, so the
/// blur the user sees while editing is the blur that gets saved. Keeping them
/// on separate code paths is how they drifted apart in the first place.
///
/// `rect` is in the image's pixels with a top-left origin, as `CGImage`
/// cropping expects.
nonisolated func filteredRegion(
    of image: CGImage,
    in rect: CGRect,
    filterName: String
) -> CGImage? {
    let rect = rect.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard
        rect.width > 1, rect.height > 1,
        let region = image.cropping(to: rect),
        let filter = CIFilter(name: filterName)
    else {
        return nil
    }

    let input = CIImage(cgImage: region)
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

    guard let output = filter.outputImage?.cropped(to: input.extent) else {
        return nil
    }
    return filterContext.createCGImage(output, from: input.extent)
}
