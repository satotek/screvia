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

    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Clamped to `area`, so a drag that leaves the visible image pins to its
    /// edge.
    static func normalizedPoint(_ point: CGPoint, in imageRect: CGRect, within area: CGRect = unit) -> CGPoint {
        clamped(
            CGPoint(
                x: (point.x - imageRect.minX) / imageRect.width,
                y: (point.y - imageRect.minY) / imageRect.height
            ),
            to: area
        )
    }

    static func clamped(_ point: CGPoint, to area: CGRect = unit) -> CGPoint {
        CGPoint(
            x: min(max(point.x, area.minX), area.maxX),
            y: min(max(point.y, area.minY), area.maxY)
        )
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
        if tool == .freehand, let first = points.first {
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { box, point in
                box.union(CGRect(origin: point, size: .zero))
            }
        }
        return endpointBox
    }

    var handles: [AnnotationHandle] {
        if tool.isLine {
            return [.start, .end]
        }
        if tool.isSizedByFont {
            return []
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
        if tool == .freehand {
            let stroke = points.map { AnnotationSpace.point($0, in: imageRect) }
            if stroke.count == 1 {
                return hypot(stroke[0].x - point.x, stroke[0].y - point.y) <= tolerance
            }
            return zip(stroke, stroke.dropFirst()).contains { a, b in
                Self.distance(from: point, toSegment: a, b) <= tolerance
            }
        }
        return AnnotationSpace.rect(bounds, in: imageRect)
            .insetBy(dx: -tolerance, dy: -tolerance)
            .contains(point)
    }

    /// Moves the annotation, stopping at the edges of `area` so it can never
    /// be dragged out of reach. One already past an edge, as after a crop,
    /// may stay there but not go further.
    func moved(by delta: CGVector, within area: CGRect = AnnotationSpace.unit) -> Annotation {
        let bounds = bounds
        let dx = Self.clamp(delta.dx, min(area.minX - bounds.minX, 0), max(area.maxX - bounds.maxX, 0))
        let dy = Self.clamp(delta.dy, min(area.minY - bounds.minY, 0), max(area.maxY - bounds.maxY, 0))

        var moved = self
        moved.start = CGPoint(x: start.x + dx, y: start.y + dy)
        moved.end = CGPoint(x: end.x + dx, y: end.y + dy)
        moved.points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        return moved
    }

    /// The annotation with `handle` dragged to `point` (annotation space).
    ///
    /// Call it on the annotation as it was when the drag began. Dragging a box
    /// handle past the opposite side flips the box, and only the original
    /// still knows which side the handle started on.
    func resized(_ handle: AnnotationHandle, to point: CGPoint, within area: CGRect = AnnotationSpace.unit) -> Annotation {
        let point = AnnotationSpace.clamped(point, to: area)
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
            resized.points = Self.rescale(points, from: bounds, to: resized.endpointBox)
        }

        return resized
    }

    /// The box `start` and `end` describe, even for a freehand drawing whose
    /// `bounds` come from its points.
    private var endpointBox: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    /// Maps each point's position in `old` to the same position in `new`. A
    /// flat axis has no position to keep, so points stay at its start.
    private static func rescale(_ points: [CGPoint], from old: CGRect, to new: CGRect) -> [CGPoint] {
        points.map { point in
            CGPoint(
                x: new.minX + (old.width > 0 ? (point.x - old.minX) / old.width : 0) * new.width,
                y: new.minY + (old.height > 0 ? (point.y - old.minY) / old.height : 0) * new.height
            )
        }
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), high)
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
