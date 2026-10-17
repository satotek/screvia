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
    /// The tip of a speech balloon's tail.
    case tail
    /// The middle of a line or arrow, which bends it.
    case bend
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
            return Self.box(around: points, first: first)
        }
        if bend != nil {
            return Self.box(around: curve, first: start)
        }
        return endpointBox
    }

    private static func box(around points: [CGPoint], first: CGPoint) -> CGRect {
        points.reduce(CGRect(origin: first, size: .zero)) { box, point in
            box.union(CGRect(origin: point, size: .zero))
        }
    }

    /// The control point of the quadratic curve from `start` to `end` that
    /// passes through `bend` halfway along.
    var bendControl: CGPoint? {
        bend.map { bend in
            CGPoint(x: 2 * bend.x - (start.x + end.x) / 2, y: 2 * bend.y - (start.y + end.y) / 2)
        }
    }

    /// A line or arrow as points along it, finely enough to hit and to bound
    /// a bent one; a straight one is its two ends.
    var curve: [CGPoint] {
        guard let control = bendControl else {
            return [start, end]
        }
        return (0...24).map { step in
            let t = CGFloat(step) / 24
            let u = 1 - t
            return CGPoint(
                x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
            )
        }
    }

    var handles: [AnnotationHandle] {
        if tool.isLine {
            return [.start, .end, .bend]
        }
        if tool == .balloon {
            return [.tail]
        }
        if tool == .magnifier, style.magnifierShape == .circle {
            // Corners only: a circle grows in both directions at once.
            return boxHandles.filter { handle in
                if case let .box(x, y) = handle {
                    return x != nil && y != nil
                }
                return false
            }
        }
        if tool.isSizedByFont {
            return []
        }
        return boxHandles
    }

    private var boxHandles: [AnnotationHandle] {
        let positions: [(AnnotationHandle.Edge?, AnnotationHandle.Edge?)] = [
            (.min, .min), (nil, .min), (.max, .min), (.max, nil),
            (.max, .max), (nil, .max), (.min, .max), (.min, nil)
        ]
        return positions.map { AnnotationHandle.box(x: $0.0, y: $0.1) }
    }

    /// The part of the image a sampling tool shows: what a redaction covers,
    /// or what a magnifier enlarges, which is smaller by its magnification
    /// and centred on its focus.
    var sampledArea: CGRect {
        let box = bounds
        guard tool == .magnifier else {
            return box
        }
        let zoom = max(style.magnification, 1)
        let center = focus ?? CGPoint(x: box.midX, y: box.midY)
        return CGRect(
            x: center.x - box.width / zoom / 2,
            y: center.y - box.height / zoom / 2,
            width: box.width / zoom,
            height: box.height / zoom
        )
    }

    /// The magnifier aimed `delta` away from where it was aimed, which is its
    /// own middle until it is first aimed elsewhere. The magnifier stays put.
    func aimed(by delta: CGVector, within area: CGRect = AnnotationSpace.unit) -> Annotation {
        let box = bounds
        let from = focus ?? CGPoint(x: box.midX, y: box.midY)
        var aimed = self
        aimed.focus = AnnotationSpace.clamped(CGPoint(x: from.x + delta.dx, y: from.y + delta.dy), to: area)
        return aimed
    }

    /// A round magnifier's box made square in image points, so it draws a
    /// circle rather than an ellipse. The corner at `anchor` stays put and
    /// the box takes its longer side.
    func squared(imageSize: CGSize, from anchor: CGPoint) -> Annotation {
        guard tool == .magnifier, style.magnifierShape == .circle, imageSize.width > 0, imageSize.height > 0 else {
            return self
        }
        let box = bounds
        let far = CGPoint(
            x: abs(box.minX - anchor.x) > abs(box.maxX - anchor.x) ? box.minX : box.maxX,
            y: abs(box.minY - anchor.y) > abs(box.maxY - anchor.y) ? box.minY : box.maxY
        )
        let side = max(box.width * imageSize.width, box.height * imageSize.height)
        let corner = CGPoint(
            x: anchor.x + (far.x < anchor.x ? -1 : 1) * side / imageSize.width,
            y: anchor.y + (far.y < anchor.y ? -1 : 1) * side / imageSize.height
        )

        var squared = self
        squared.start = CGPoint(x: min(anchor.x, corner.x), y: min(anchor.y, corner.y))
        squared.end = CGPoint(x: max(anchor.x, corner.x), y: max(anchor.y, corner.y))
        return squared
    }

    /// The corner opposite a corner handle, which stays put while it is
    /// dragged.
    func anchor(opposite handle: AnnotationHandle) -> CGPoint? {
        guard case let .box(.some(x), .some(y)) = handle else {
            return nil
        }
        let box = bounds
        return CGPoint(x: x == .min ? box.maxX : box.minX, y: y == .min ? box.maxY : box.minY)
    }

    /// A magnifier whose focus was dragged off its middle, so what it
    /// enlarges is marked where it is.
    var isMagnifyingElsewhere: Bool {
        guard tool == .magnifier, let focus else {
            return false
        }
        let box = bounds
        return hypot(focus.x - box.midX, focus.y - box.midY) > 0.001
    }

    func location(of handle: AnnotationHandle) -> CGPoint {
        switch handle {
        case .start:
            return start
        case .end:
            return end
        case .tail:
            return tail ?? CGPoint(x: bounds.midX, y: bounds.midY)
        case .bend:
            return bend ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
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

    /// Whether its inside covers what is under it. An unfilled box or a
    /// highlight is see-through, so a drag inside it with a drawing tool is
    /// more likely meant to draw there than to move it.
    var isOpaque: Bool {
        switch tool {
        case .rectangle, .ellipse: style.fillColor != nil
        case .highlight: false
        default: true
        }
    }

    /// Whether a click at `point` (view space) lands on this annotation.
    /// Boxes count their inside, not just their outline: a thin stroke is
    /// too hard to hit, and the inside is what the user sees as the shape.
    /// Without `insideCounts`, a see-through box counts only its outline.
    func contains(_ point: CGPoint, in imageRect: CGRect, tolerance: CGFloat, insideCounts: Bool = true) -> Bool {
        if tool.isLine {
            let path = curve.map { AnnotationSpace.point($0, in: imageRect) }
            return zip(path, path.dropFirst()).contains { a, b in
                Self.distance(from: point, toSegment: a, b) <= tolerance
            }
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
        if isMagnifyingElsewhere,
           AnnotationSpace.rect(sampledArea, in: imageRect).insetBy(dx: -tolerance, dy: -tolerance).contains(point) {
            return true
        }
        if let tail {
            // Along the middle of the tail, which is enough to grab it.
            let rect = AnnotationSpace.rect(bounds, in: imageRect)
            let tip = AnnotationSpace.point(tail, in: imageRect)
            if Self.distance(from: point, toSegment: CGPoint(x: rect.midX, y: rect.midY), tip) <= tolerance {
                return true
            }
        }
        let rect = AnnotationSpace.rect(bounds, in: imageRect)
        guard rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else {
            return false
        }
        if insideCounts || isOpaque {
            return true
        }
        if tool == .ellipse {
            // How far out from the middle, where the outline is 1.
            let a = max(rect.width / 2, .ulpOfOne)
            let b = max(rect.height / 2, .ulpOfOne)
            let reach = hypot((point.x - rect.midX) / a, (point.y - rect.midY) / b)
            return abs(reach - 1) * min(a, b) <= tolerance
        }
        return !rect.insetBy(dx: tolerance, dy: tolerance).contains(point)
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
        // The box stops at the edge, but what a balloon points at or a
        // magnifier shows may lie further out, so those are held at it.
        moved.tail = tail.map { AnnotationSpace.clamped(CGPoint(x: $0.x + dx, y: $0.y + dy), to: area) }
        moved.focus = focus.map { AnnotationSpace.clamped(CGPoint(x: $0.x + dx, y: $0.y + dy), to: area) }
        moved.bend = bend.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
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
        case .tail:
            resized.tail = point
        case .bend:
            // Dragged back onto the straight line, it is straight again, so a
            // bend can be undone by hand.
            let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            resized.bend = hypot(point.x - middle.x, point.y - middle.y) < 0.004 ? nil : point
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
