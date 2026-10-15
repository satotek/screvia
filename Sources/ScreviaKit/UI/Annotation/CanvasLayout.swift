import CoreGraphics

/// Where the image sits in the editor's scroll view.
///
/// Cropping shows part of the image at the size the whole image would get,
/// so `imageRect` (the whole image, which annotation space maps onto) runs
/// past `visibleRect` (the crop) and the canvas clips to the latter.
nonisolated struct CanvasLayout: Equatable {
    /// Kept clear around the image so its edges and handles stay reachable.
    static let margin: CGFloat = 24

    let contentSize: CGSize
    let visibleRect: CGRect
    let imageRect: CGRect

    init(containerSize: CGSize, imageSize: CGSize, crop: CGRect, zoom: CGFloat) {
        let visibleSize = CGSize(width: imageSize.width * crop.width, height: imageSize.height * crop.height)
        guard visibleSize.width > 0, visibleSize.height > 0, crop.width > 0, crop.height > 0 else {
            contentSize = containerSize
            visibleRect = CGRect(origin: .zero, size: containerSize)
            imageRect = visibleRect
            return
        }

        let fitScale = min(
            max(containerSize.width - Self.margin * 2, 1) / visibleSize.width,
            max(containerSize.height - Self.margin * 2, 1) / visibleSize.height
        )
        let size = CGSize(width: visibleSize.width * fitScale * zoom, height: visibleSize.height * fitScale * zoom)

        contentSize = CGSize(
            width: max(containerSize.width, size.width + Self.margin * 2),
            height: max(containerSize.height, size.height + Self.margin * 2)
        )
        visibleRect = CGRect(
            x: max((contentSize.width - size.width) / 2, Self.margin),
            y: max((contentSize.height - size.height) / 2, Self.margin),
            width: size.width,
            height: size.height
        )

        let imageWidth = size.width / crop.width
        let imageHeight = size.height / crop.height
        imageRect = CGRect(
            x: visibleRect.minX - crop.minX * imageWidth,
            y: visibleRect.minY - crop.minY * imageHeight,
            width: imageWidth,
            height: imageHeight
        )
    }
}
