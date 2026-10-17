import AppKit

/// How the image is turned and mirrored, as the user sees it.
///
/// The original stays as it was captured, and the turn is applied when it
/// is shown and exported. That keeps undo, which only knows the document,
/// and re-editing, which keeps the original beside it, working unchanged.
/// The mirror is applied before the turn.
nonisolated struct ImageOrientation: Codable, Equatable {
    /// Clockwise quarter turns, 0 through 3.
    var quarterTurns = 0
    /// Mirrored left to right.
    var isMirrored = false

    var isIdentity: Bool {
        quarterTurns == 0 && !isMirrored
    }

    /// Whether width and height trade places.
    var isSideways: Bool {
        quarterTurns % 2 == 1
    }

    func size(of size: CGSize) -> CGSize {
        isSideways ? CGSize(width: size.height, height: size.width) : size
    }

    /// The orientation after one more change, as the user sees the image now.
    func applying(_ change: ImageOrientationChange) -> ImageOrientation {
        var next = self
        switch change {
        case .rotateRight:
            next.quarterTurns = (quarterTurns + 1) % 4
        case .rotateLeft:
            next.quarterTurns = (quarterTurns + 3) % 4
        case .flipHorizontal:
            // Mirroring a turned image is mirroring first and turning back.
            next.quarterTurns = (4 - quarterTurns) % 4
            next.isMirrored.toggle()
        case .flipVertical:
            next.quarterTurns = (6 - quarterTurns) % 4
            next.isMirrored.toggle()
        }
        return next
    }

    /// `image` turned and mirrored, at full resolution.
    func applied(to image: NSImage) -> NSImage {
        guard
            !isIdentity,
            let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return image
        }
        let pixels = size(of: CGSize(width: source.width, height: source.height))
        guard let context = CGContext(
            data: nil,
            width: Int(pixels.width),
            height: Int(pixels.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: source.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        // Core Graphics turns counterclockwise with its origin at the bottom
        // left; a clockwise turn as seen is a negative angle here.
        context.translateBy(x: pixels.width / 2, y: pixels.height / 2)
        context.rotate(by: -CGFloat(quarterTurns) * .pi / 2)
        if isMirrored {
            context.scaleBy(x: -1, y: 1)
        }
        context.draw(
            source,
            in: CGRect(x: -CGFloat(source.width) / 2, y: -CGFloat(source.height) / 2, width: CGFloat(source.width), height: CGFloat(source.height))
        )

        guard let turned = context.makeImage() else {
            return image
        }
        return NSImage(cgImage: turned, size: size(of: image.size))
    }
}

nonisolated enum ImageOrientationChange: CaseIterable {
    case rotateLeft
    case rotateRight
    case flipHorizontal
    case flipVertical

    /// Where a point in annotation space lands after this change.
    func map(_ point: CGPoint) -> CGPoint {
        switch self {
        case .rotateRight: CGPoint(x: 1 - point.y, y: point.x)
        case .rotateLeft: CGPoint(x: point.y, y: 1 - point.x)
        case .flipHorizontal: CGPoint(x: 1 - point.x, y: point.y)
        case .flipVertical: CGPoint(x: point.x, y: 1 - point.y)
        }
    }

    func map(_ rect: CGRect) -> CGRect {
        let a = map(CGPoint(x: rect.minX, y: rect.minY))
        let b = map(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    var isTurn: Bool {
        self == .rotateLeft || self == .rotateRight
    }
}

nonisolated extension AnnotationDocument {
    /// The document after the image is turned or mirrored: the orientation
    /// changes, and the crop and every annotation move with the picture.
    /// `imageSize` is the image's size in points as shown before the change.
    ///
    /// What is measured in points keeps its size and moves by its middle:
    /// text, steps, balloons, pictures and round magnifiers would otherwise
    /// be squashed by a turn's change of aspect.
    func reoriented(_ change: ImageOrientationChange, imageSize: CGSize) -> AnnotationDocument {
        var document = self
        document.orientation = orientation.applying(change)
        document.crop = change.map(crop)

        let newSize = change.isTurn ? CGSize(width: imageSize.height, height: imageSize.width) : imageSize
        document.annotations = annotations.map { annotation in
            var moved = annotation
            moved.start = change.map(annotation.start)
            moved.end = change.map(annotation.end)
            moved.points = annotation.points.map(change.map)
            moved.tail = annotation.tail.map(change.map)
            moved.bend = annotation.bend.map(change.map)
            moved.focus = annotation.focus.map(change.map)

            guard annotation.keepsItsSize, newSize.width > 0, newSize.height > 0 else {
                return moved
            }
            let box = annotation.bounds
            let middle = change.map(CGPoint(x: box.midX, y: box.midY))
            let width = box.width * imageSize.width / newSize.width
            let height = box.height * imageSize.height / newSize.height
            moved.start = CGPoint(x: middle.x - width / 2, y: middle.y - height / 2)
            moved.end = CGPoint(x: middle.x + width / 2, y: middle.y + height / 2)
            return moved
        }
        return document
    }
}

nonisolated extension Annotation {
    /// Measured in points rather than by the picture under it, so turning
    /// the image moves it without reshaping it.
    var keepsItsSize: Bool {
        switch tool {
        case .text, .step, .balloon, .image: true
        case .magnifier: style.magnifierShape == .circle
        default: false
        }
    }
}
