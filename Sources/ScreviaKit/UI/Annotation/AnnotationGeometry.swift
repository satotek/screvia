import CoreGraphics

/// Converts between annotation space (fractions of the image, top-left
/// origin) and a view or context where the image occupies `imageRect`.
nonisolated enum AnnotationSpace {
    static func point(_ normalized: CGPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + normalized.x * imageRect.width,
            y: imageRect.minY + normalized.y * imageRect.height
        )
    }

    static func rect(_ normalized: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + normalized.minX * imageRect.width,
            y: imageRect.minY + normalized.minY * imageRect.height,
            width: normalized.width * imageRect.width,
            height: normalized.height * imageRect.height
        )
    }

    /// Clamped, so a drag that leaves the image pins to its edge.
    static func normalizedPoint(_ point: CGPoint, in imageRect: CGRect) -> CGPoint {
        clamped(CGPoint(
            x: (point.x - imageRect.minX) / imageRect.width,
            y: (point.y - imageRect.minY) / imageRect.height
        ))
    }

    static func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }
}

/// A grip on a selected annotation that resizes it when dragged.
nonisolated enum AnnotationHandle: Hashable {
    case start
    case end
    /// A point on the bounding box. A nil axis means the middle of that side,
    /// so `.box(x: .max, y: nil)` is the middle of the right edge.
    case box(x: Edge?, y: Edge?)

    enum Edge: Hashable {
        case min
        case max
    }
}

nonisolated extension Annotation {
    /// The bounding box in annotation space, whichever way it was drawn.
    var bounds: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    var handles: [AnnotationHandle] {
        if tool.isLine {
            return [.start, .end]
        }
        let positions: [(AnnotationHandle.Edge?, AnnotationHandle.Edge?)] = [
            (.min, .min), (nil, .min), (.max, .min), (.max, nil),
            (.max, .max), (nil, .max), (.min, .max), (.min, nil)
        ]
        return positions.map { AnnotationHandle.box(x: $0.0, y: $0.1) }
    }

    func location(of handle: AnnotationHandle) -> CGPoint {
        switch handle {
        case .start:
            return start
        case .end:
            return end
        case let .box(x, y):
            let bounds = bounds
            return CGPoint(
                x: Self.coordinate(x, from: bounds.minX, to: bounds.maxX),
                y: Self.coordinate(y, from: bounds.minY, to: bounds.maxY)
            )
        }
    }

    /// The topmost handle within `radius` of `point`, both in view space.
    func handle(at point: CGPoint, in imageRect: CGRect, radius: CGFloat) -> AnnotationHandle? {
        handles.first { handle in
            let location = AnnotationSpace.point(location(of: handle), in: imageRect)
            return hypot(location.x - point.x, location.y - point.y) <= radius
        }
    }

    /// Whether a click at `point` (view space) lands on this annotation.
    /// Boxes count their inside, not just their outline: a thin stroke is
    /// too hard to hit, and the inside is what the user sees as the shape.
    func contains(_ point: CGPoint, in imageRect: CGRect, tolerance: CGFloat) -> Bool {
        if tool.isLine {
            let a = AnnotationSpace.point(start, in: imageRect)
            let b = AnnotationSpace.point(end, in: imageRect)
            return Self.distance(from: point, toSegment: a, b) <= tolerance
        }
        return AnnotationSpace.rect(bounds, in: imageRect)
            .insetBy(dx: -tolerance, dy: -tolerance)
            .contains(point)
    }

    /// Moves the annotation, stopping at the image's edges so it can never be
    /// dragged out of reach.
    func moved(by delta: CGVector) -> Annotation {
        let bounds = bounds
        let dx = min(max(delta.dx, -bounds.minX), 1 - bounds.maxX)
        let dy = min(max(delta.dy, -bounds.minY), 1 - bounds.maxY)

        var moved = self
        moved.start = CGPoint(x: start.x + dx, y: start.y + dy)
        moved.end = CGPoint(x: end.x + dx, y: end.y + dy)
        return moved
    }

    /// The annotation with `handle` dragged to `point` (annotation space).
    ///
    /// Call it on the annotation as it was when the drag began. Dragging a box
    /// handle past the opposite side flips the box, and only the original
    /// still knows which side the handle started on.
    func resized(_ handle: AnnotationHandle, to point: CGPoint) -> Annotation {
        let point = AnnotationSpace.clamped(point)
        var resized = self

        switch handle {
        case .start:
            resized.start = point
        case .end:
            resized.end = point
        case let .box(x, y):
            let bounds = bounds
            var (minX, maxX, minY, maxY) = (bounds.minX, bounds.maxX, bounds.minY, bounds.maxY)
            switch x {
            case .min: minX = point.x
            case .max: maxX = point.x
            case nil: break
            }
            switch y {
            case .min: minY = point.y
            case .max: maxY = point.y
            case nil: break
            }
            resized.start = CGPoint(x: min(minX, maxX), y: min(minY, maxY))
            resized.end = CGPoint(x: max(minX, maxX), y: max(minY, maxY))
        }

        return resized
    }

    private static func coordinate(_ edge: AnnotationHandle.Edge?, from low: CGFloat, to high: CGFloat) -> CGFloat {
        switch edge {
        case .min: low
        case .max: high
        case nil: (low + high) / 2
        }
    }

    private static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - a.x, point.y - a.y)
        }
        let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }
}
