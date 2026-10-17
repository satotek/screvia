import AppKit
import SwiftUI

struct AnnotationCanvas: View {
    /// What is on screen; may be a downsampled copy of the capture.
    let image: NSImage
    /// The full capture's size in points, the unit styles are given in.
    let imageSize: CGSize
    /// A plain click on empty space switches this to the select tool.
    @Binding var selectedTool: AnnotationTool
    /// The style new annotations get.
    let style: AnnotationStyle
    @Binding var document: AnnotationDocument
    @Binding var selection: Annotation.ID?
    @Binding var zoomScale: CGFloat
    /// Set while a text field is open, so the editor can keep shortcuts such
    /// as Delete away from it.
    @Binding var isEditingText: Bool
    /// Screen points per image point, which the zoom readout shows.
    @Binding var displayScale: CGFloat
    /// While set, a click picks the colour under it instead of editing.
    let isPickingColor: Bool
    /// Called with the document as it was before each finished edit.
    let onRecordUndo: (AnnotationDocument) -> Void
    /// Where the pointer is over the visible image, in annotation space, or
    /// nil once it leaves.
    let onHover: (CGPoint?) -> Void
    /// Gets the area the eyedropper picked from, in annotation space: empty
    /// for a click, which picks the one point at its origin.
    let onPickColor: (CGRect) -> Void

    /// What the current pointer drag is doing, decided when it starts.
    private enum DragAction {
        case drawing(start: CGPoint, end: CGPoint)
        case sketching(points: [CGPoint])
        case cropping(start: CGPoint, end: CGPoint)
        /// `original` is the annotation as the drag found it; every update is
        /// computed from it, not from the previous frame, so rounding never
        /// accumulates. `before` is the undo snapshot.
        case moving(original: Annotation, before: AnnotationDocument)
        case resizing(original: Annotation, handle: AnnotationHandle, before: AnnotationDocument)
        /// Moving what a magnifier enlarges, not the magnifier.
        case aiming(original: Annotation, before: AnnotationDocument)
        /// The eyedropper dragged over an area to average.
        case sampling(start: CGPoint, end: CGPoint)
        /// A click on empty space with the select tool.
        case idle
    }

    private struct FilteredRegion {
        /// The annotation's `sampledArea` when this was made.
        let area: CGRect
        let image: CGImage
    }

    private static let handleSize: CGFloat = 8
    private static let handleHitRadius: CGFloat = 8
    private static let hitTolerance: CGFloat = 6
    /// Freehand points closer than this, in view points, add nothing visible.
    private static let sketchSpacing: CGFloat = 2

    @State private var dragAction: DragAction?
    @State private var magnificationStart: CGFloat?
    @State private var editingTextID: UUID?
    @State private var documentBeforeTextEditing: AnnotationDocument?
    @State private var lastClick: (id: UUID, time: Date)?

    /// Filtered region images keyed by annotation id, each tagged with the
    /// bounds it was computed for so a moved or resized region is redone. A
    /// region being dragged falls back to a cheap sketch until it settles.
    @State private var filteredRegions: [UUID: FilteredRegion] = [:]

    private var annotations: [Annotation] {
        document.annotations
    }

    private var selectedAnnotation: Annotation? {
        selection.flatMap { id in annotations.first { $0.id == id } }
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = CanvasLayout(
                containerSize: geometry.size,
                imageSize: image.size,
                crop: document.crop,
                zoom: zoomScale
            )

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack {
                    effectsBackdrop(layout: layout)

                    Image(nsImage: image)
                        .resizable()
                        .frame(width: layout.imageRect.width, height: layout.imageRect.height)
                        .position(x: layout.imageRect.midX, y: layout.imageRect.midY)
                        .mask {
                            Rectangle()
                                .frame(width: layout.visibleRect.width, height: layout.visibleRect.height)
                                .position(x: layout.visibleRect.midX, y: layout.visibleRect.midY)
                        }

                    Canvas { context, _ in
                        draw(in: &context, layout: layout)
                    }
                    .allowsHitTesting(false)

                    // Above the canvas and below nothing: in this mode a
                    // drag selects text instead of drawing.
                    if selectedTool == .liveText {
                        LiveTextOverlay(image: image)
                            .frame(width: layout.imageRect.width, height: layout.imageRect.height)
                            .position(x: layout.imageRect.midX, y: layout.imageRect.midY)
                            .mask {
                                Rectangle()
                                    .frame(width: layout.visibleRect.width, height: layout.visibleRect.height)
                                    .position(x: layout.visibleRect.midX, y: layout.visibleRect.midY)
                            }
                            .zIndex(3)
                    }

                    if let editingTextID,
                       let annotation = annotations.first(where: { $0.id == editingTextID }) {
                        let pointScale = layout.imageRect.width / max(imageSize.width, 1)
                        let rect = AnnotationSpace.rect(annotation.bounds, in: layout.imageRect)
                        let font = AnnotationRenderer.font(for: annotation.style, pointScale: pointScale)
                        let slack = annotation.textWidth == nil ? font.pointSize : 0
                        InlineTextField(
                            text: textBinding(for: editingTextID),
                            font: font,
                            horizontalPadding: annotation.style.fontSize * 0.45 * pointScale,
                            wraps: annotation.textWidth != nil,
                            onCommit: commitTextEditing,
                            onCancel: cancelTextEditing
                        )
                        // A caret's width of slack, so typing never clips
                        // before the box catches up. A wrapping box keeps
                        // its width; the text wraps instead.
                        .frame(width: rect.width + slack, height: rect.height)
                        .position(x: rect.midX + slack / 2, y: rect.midY)
                        .zIndex(2)
                    }
                }
                .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location) where layout.visibleRect.contains(location):
                        onHover(AnnotationSpace.normalizedPoint(location, in: layout.imageRect, within: document.crop))
                    default:
                        onHover(nil)
                    }
                }
                .gesture(
                    // Zero distance, so a plain click can select, place a
                    // step or start a text box.
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragAction == nil {
                                beginDrag(at: value.startLocation, layout: layout)
                            }
                            updateDrag(value, layout: layout)
                        }
                        .onEnded { value in
                            endDrag(value, layout: layout)
                        },
                    // Live Text handles its own drags.
                    including: selectedTool == .liveText ? .subviews : .all
                )
            }
            .onChange(of: layout, initial: true) { _, layout in
                displayScale = layout.imageRect.width / max(imageSize.width, 1)
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        if magnificationStart == nil {
                            magnificationStart = zoomScale
                        }
                        zoomScale = AnnotationZoom.clamped(
                            (magnificationStart ?? zoomScale) * value
                        )
                    }
                    .onEnded { _ in
                        magnificationStart = nil
                    }
            )
        }
        .onChange(of: document.annotations, initial: true) { _, _ in
            refreshFilteredRegions()
        }
        .onChange(of: editingTextID) { _, id in
            isEditingText = id != nil
        }
    }

    // MARK: - Drawing

    /// The border and shadow export adds, drawn behind the image: a box the
    /// border's width larger than what is visible, casting the shadow.
    @ViewBuilder
    private func effectsBackdrop(layout: CanvasLayout) -> some View {
        let effects = document.effects
        if !effects.isEmpty {
            let pointScale = layout.imageRect.width / max(imageSize.width, 1)
            let margin = effects.margin * pointScale
            let border = effects.borderThickness * pointScale
            let inner = layout.visibleRect.insetBy(dx: -margin, dy: -margin)
            let frame = inner.insetBy(dx: -border, dy: -border)
            let marginColor = effects.marginColor.map { Color(cgColor: $0.cgColor) } ?? .clear
            Rectangle()
                .fill(effects.borderColor.map { Color(cgColor: $0.cgColor) } ?? marginColor)
                .frame(width: frame.width, height: frame.height)
                .shadow(
                    color: .black.opacity(effects.hasShadow ? 0.35 : 0),
                    // SwiftUI's radius is about half a Core Graphics blur.
                    radius: ImageEffects.shadowBlur * pointScale / 2,
                    y: ImageEffects.shadowDrop * pointScale
                )
                .position(x: frame.midX, y: frame.midY)
            if margin > 0 {
                Rectangle()
                    .fill(marginColor)
                    .frame(width: inner.width, height: inner.height)
                    .position(x: inner.midX, y: inner.midY)
            }
        }
    }

    private func draw(in context: inout GraphicsContext, layout: CanvasLayout) {
        let imageRect = layout.imageRect
        let pointScale = imageRect.width / max(imageSize.width, 1)

        context.drawLayer { layer in
            layer.clip(to: Path(layout.visibleRect))
            layer.withCGContext { cgContext in
                AnnotationRenderer.draw(
                    annotationsOutsideTextField,
                    in: cgContext,
                    imageRect: imageRect,
                    pointScale: pointScale,
                    filteredRegion: filteredImage(for:)
                )

                if let preview = inProgressAnnotation() {
                    AnnotationRenderer.draw(
                        preview,
                        in: cgContext,
                        imageRect: imageRect,
                        pointScale: pointScale
                    )
                }
            }
        }

        if case let .sampling(start, end) = dragAction {
            let area = Path(AnnotationSpace.rect(Self.box(start, end), in: imageRect))
            context.stroke(area, with: .color(.black.opacity(0.6)), style: StrokeStyle(lineWidth: 1))
            context.stroke(area, with: .color(.white), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }

        // A text box being dragged out, before there is text to show.
        if case let .drawing(start, end) = dragAction, selectedTool == .text, wrapWidth(from: start, to: end) != nil {
            context.stroke(
                Path(AnnotationSpace.rect(Self.box(start, end), in: imageRect)),
                with: .color(.accentColor),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
        }

        if case let .cropping(start, end) = dragAction {
            drawCropPreview(
                AnnotationSpace.rect(Self.box(start, end), in: imageRect),
                visibleRect: layout.visibleRect,
                in: &context
            )
        }

        if editingTextID == nil, selectedTool != .liveText, let selectedAnnotation {
            drawSelection(of: selectedAnnotation, in: &context, imageRect: imageRect)
        }
    }

    /// The text being edited is shown by its text field instead. A balloon
    /// keeps its box and tail, with the field over the box.
    private var annotationsOutsideTextField: [Annotation] {
        annotations.compactMap { annotation in
            guard annotation.id == editingTextID else {
                return annotation
            }
            guard annotation.tool == .balloon else {
                return nil
            }
            var empty = annotation
            empty.text = ""
            return empty
        }
    }

    private func inProgressAnnotation() -> Annotation? {
        switch dragAction {
        case let .drawing(start, end) where selectedTool == .balloon:
            return placedBalloon(pointingAt: start, at: end)
        case let .drawing(start, end) where selectedTool != .text && selectedTool != .step:
            return Annotation(tool: selectedTool, start: start, end: end, style: style)
                .squared(imageSize: imageSize, from: start)
        case let .sketching(points):
            return Annotation(tool: .freehand, start: .zero, end: .zero, points: points, style: style)
        default:
            return nil
        }
    }

    private func drawCropPreview(_ crop: CGRect, visibleRect: CGRect, in context: inout GraphicsContext) {
        var shade = Path(visibleRect)
        shade.addRect(crop)
        context.fill(shade, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
        context.stroke(
            Path(crop),
            with: .color(.white),
            style: StrokeStyle(lineWidth: 1, dash: [5, 3])
        )
    }

    private func drawSelection(of annotation: Annotation, in context: inout GraphicsContext, imageRect: CGRect) {
        if !annotation.tool.isLine {
            let outline = AnnotationSpace.rect(annotation.bounds, in: imageRect).insetBy(dx: -3, dy: -3)
            context.stroke(
                Path(outline),
                with: .color(.accentColor),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
        }

        for handle in annotation.handles {
            let center = AnnotationSpace.point(annotation.location(of: handle), in: imageRect)
            let size = Self.handleSize
            let knob = Path(ellipseIn: CGRect(
                x: center.x - size / 2,
                y: center.y - size / 2,
                width: size,
                height: size
            ))
            context.fill(knob, with: .color(.white))
            context.stroke(knob, with: .color(.accentColor), lineWidth: 1.5)
        }
    }

    // MARK: - Dragging

    /// A handle of the selected annotation wins over everything, so a shape
    /// can be resized right after it is drawn without switching tools.
    /// A drag that starts on an existing shape moves it with any tool, except
    /// inside a see-through box with a drawing tool, which draws there.
    private func beginDrag(at point: CGPoint, layout: CanvasLayout) {
        if editingTextID != nil {
            commitTextEditing()
        }

        let imageRect = layout.imageRect
        if isPickingColor {
            let start = AnnotationSpace.normalizedPoint(point, in: imageRect, within: document.crop)
            dragAction = layout.visibleRect.contains(point) ? .sampling(start: start, end: start) : .idle
            return
        }

        if let selectedAnnotation,
           let handle = selectedAnnotation.handle(at: point, in: imageRect, radius: Self.handleHitRadius) {
            dragAction = .resizing(original: selectedAnnotation, handle: handle, before: document)
            return
        }

        let insideCounts = selectedTool == .select
        let hit = layout.visibleRect.contains(point)
            ? annotations.last {
                $0.contains(point, in: imageRect, tolerance: Self.hitTolerance, insideCounts: insideCounts)
            }
            : nil

        if let magnifier = magnifierToAim(at: point, hit: hit, imageRect: imageRect) {
            selection = magnifier.id
            dragAction = .aiming(original: magnifier, before: document)
            return
        }
        let start = AnnotationSpace.normalizedPoint(point, in: imageRect, within: document.crop)

        switch selectedTool {
        case .select:
            selection = hit?.id
            dragAction = hit.map { .moving(original: $0, before: document) } ?? .idle
        case .text where hit?.tool == .text, .balloon where hit?.tool == .balloon:
            if let hit {
                beginTextEditing(existing: hit)
            }
            dragAction = .idle
        case .crop:
            selection = nil
            dragAction = .cropping(start: start, end: start)
        default:
            // As in ShareX, any tool picks up an annotation it lands on, so
            // one just drawn can be adjusted without switching tools; empty
            // space is where drawing starts.
            if let hit {
                selection = hit.id
                dragAction = .moving(original: hit, before: document)
            } else if selectedTool == .freehand {
                selection = nil
                dragAction = .sketching(points: [start])
            } else {
                selection = nil
                dragAction = .drawing(start: start, end: start)
            }
        }
    }

    private func updateDrag(_ value: DragGesture.Value, layout: CanvasLayout) {
        let imageRect = layout.imageRect
        let point = AnnotationSpace.normalizedPoint(value.location, in: imageRect, within: document.crop)

        switch dragAction {
        case let .drawing(start, _):
            dragAction = .drawing(start: start, end: point)
        case let .cropping(start, _):
            dragAction = .cropping(start: start, end: point)
        case let .sampling(start, _):
            dragAction = .sampling(start: start, end: point)
        case let .sketching(points):
            let last = AnnotationSpace.point(points[points.count - 1], in: imageRect)
            let next = AnnotationSpace.point(point, in: imageRect)
            if hypot(next.x - last.x, next.y - last.y) >= Self.sketchSpacing {
                dragAction = .sketching(points: points + [point])
            }
        case let .moving(original, _):
            replace(original.moved(
                by: CGVector(
                    dx: value.translation.width / imageRect.width,
                    dy: value.translation.height / imageRect.height
                ),
                within: document.crop
            ))
        case let .resizing(original, handle, _):
            var resized = original.resized(handle, to: point, within: document.crop)
            if original.tool == .image, let anchor = original.anchor(opposite: handle) {
                // A picture keeps its shape from the corners; the sides
                // still stretch it, for when that is wanted.
                let box = original.bounds
                let aspect = (box.width * imageSize.width) / max(box.height * imageSize.height, .ulpOfOne)
                resized = resized.keepingAspect(aspect, imageSize: imageSize, from: anchor)
            }
            if resized.textWidth != nil {
                resized.textWidth = max(resized.bounds.width * imageSize.width, Self.minimumWrapWidth)
                resized = AnnotationRenderer.fitted(resized, imageSize: imageSize)
            }
            replace(original.anchor(opposite: handle).map { resized.squared(imageSize: imageSize, from: $0) } ?? resized)
        case let .aiming(original, _):
            replace(original.aimed(
                by: CGVector(
                    dx: value.translation.width / imageRect.width,
                    dy: value.translation.height / imageRect.height
                ),
                within: document.crop
            ))
        case .idle, nil:
            break
        }
    }

    /// The magnifier a drag at `point` aims rather than moves: ⌥-dragging
    /// one, or dragging the marked area of one aimed elsewhere. The
    /// selected magnifier counts with any tool, so one just drawn can be
    /// aimed straight away; others need the select tool, as moving does.
    private func magnifierToAim(at point: CGPoint, hit: Annotation?, imageRect: CGRect) -> Annotation? {
        let candidates = [selectedAnnotation, selectedTool == .select ? hit : nil]
            .compactMap { $0 }
            .filter { $0.tool == .magnifier }
        return candidates.first { magnifier in
            if AnnotationSpace.rect(magnifier.bounds, in: imageRect).contains(point) {
                return NSEvent.modifierFlags.contains(.option)
            }
            return magnifier.isMagnifyingElsewhere
                && AnnotationSpace.rect(magnifier.sampledArea, in: imageRect).contains(point)
        }
    }

    private func endDrag(_ value: DragGesture.Value, layout: CanvasLayout) {
        let action = dragAction
        dragAction = nil
        let end = AnnotationSpace.normalizedPoint(value.location, in: layout.imageRect, within: document.crop)

        switch action {
        case let .drawing(start, _):
            finishDrawing(from: start, to: end)
        case let .sketching(points):
            let stroke = Annotation(tool: .freehand, start: .zero, end: .zero, points: points, style: style)
            var annotation = stroke
            annotation.start = stroke.bounds.origin
            annotation.end = CGPoint(x: stroke.bounds.maxX, y: stroke.bounds.maxY)
            add(annotation)
        case let .cropping(start, _):
            let crop = Self.box(start, end)
            // A stray click must not crop to a sliver.
            guard crop.width > 0.01, crop.height > 0.01 else {
                selectedTool = .select
                return
            }
            let before = document
            document.crop = crop
            selection = nil
            onRecordUndo(before)
        case let .moving(original, before):
            if document != before {
                onRecordUndo(before)
            } else if original.tool.hasText, isDoubleClick(on: original.id) {
                beginTextEditing(existing: original)
            }
            refreshFilteredRegions()
        case let .sampling(start, _):
            let area = Self.box(start, end)
            let size = AnnotationSpace.rect(area, in: layout.imageRect).size
            // A few points of drift is still a click.
            onPickColor(max(size.width, size.height) < 4 ? CGRect(origin: start, size: .zero) : area)
        case let .resizing(_, _, before), let .aiming(_, before):
            if document != before {
                onRecordUndo(before)
            }
            refreshFilteredRegions()
        case .idle, nil:
            break
        }
    }

    private func finishDrawing(from start: CGPoint, to end: CGPoint) {
        switch selectedTool {
        case .text:
            if let width = wrapWidth(from: start, to: end) {
                beginTextEditing(.text, at: Self.box(start, end).origin, textWidth: width)
            } else {
                beginTextEditing(.text, at: start)
            }
        case .balloon:
            let balloon = placedBalloon(pointingAt: start, at: end)
            beginTextEditing(.balloon, at: balloon.start, tail: balloon.tail)
        case .step:
            // Centred on the click, then kept inside the visible image.
            let placed = AnnotationRenderer.fitted(
                Annotation(tool: .step, start: start, end: start, style: style),
                imageSize: imageSize
            )
            let offset = CGVector(dx: -placed.bounds.width / 2, dy: -placed.bounds.height / 2)
            add(placed.moved(by: offset, within: document.crop))
        default:
            let width = abs(end.x - start.x)
            let height = abs(end.y - start.y)
            // Lines may be flat; boxes need both dimensions.
            let isLongEnough = selectedTool.isLine
                ? max(width, height) > 0.005
                : min(width, height) > 0.005
            guard isLongEnough else {
                // A click where a drag would draw: done drawing. Tools a
                // click itself uses (text, balloon, step, freehand's dot)
                // never get here.
                selectedTool = .select
                return
            }
            add(Annotation(tool: selectedTool, start: start, end: end, style: style).squared(imageSize: imageSize, from: start))
        }
    }

    private func add(_ annotation: Annotation) {
        let before = document
        document.annotations.append(annotation)
        selection = annotation.id
        onRecordUndo(before)
    }

    private func replace(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else {
            return
        }
        document.annotations[index] = annotation
    }

    private func isDoubleClick(on id: UUID) -> Bool {
        let now = Date()
        defer { lastClick = (id, now) }
        guard let lastClick, lastClick.id == id else {
            return false
        }
        return now.timeIntervalSince(lastClick.time) <= NSEvent.doubleClickInterval
    }

    private static func box(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    // MARK: - Text

    /// A balloon dragged out from what it points at to where it sits. A
    /// plain click has nothing to point at yet, so the tail goes below and to
    /// the left, where the user can drag it.
    private func placedBalloon(pointingAt tip: CGPoint, at origin: CGPoint) -> Annotation {
        var balloon = AnnotationRenderer.fitted(
            Annotation(tool: .balloon, start: origin, end: origin, text: "", style: style),
            imageSize: imageSize
        )
        let box = balloon.bounds
        let dragged = hypot(origin.x - tip.x, origin.y - tip.y) > 0.01
        balloon.tail = dragged
            ? tip
            : AnnotationSpace.clamped(
                CGPoint(x: box.minX + box.width * 0.2, y: box.maxY + box.height * 0.8),
                to: document.crop
            )
        return balloon
    }

    /// Narrower than this, a drag with the text tool is a click: a box
    /// that grows with its one line.
    private static let minimumWrapWidth: CGFloat = 40

    /// The width, in image points, a text box dragged from `start` to `end`
    /// wraps at, or nil when the drag was too short to mean one.
    private func wrapWidth(from start: CGPoint, to end: CGPoint) -> CGFloat? {
        let width = abs(end.x - start.x) * imageSize.width
        return width >= Self.minimumWrapWidth ? width : nil
    }

    private func beginTextEditing(
        _ tool: AnnotationTool,
        at origin: CGPoint,
        textWidth: CGFloat? = nil,
        tail: CGPoint? = nil
    ) {
        documentBeforeTextEditing = document
        let annotation = AnnotationRenderer.fitted(
            Annotation(tool: tool, start: origin, end: origin, text: "", textWidth: textWidth, tail: tail, style: style),
            imageSize: imageSize
        )
        document.annotations.append(annotation)
        selection = annotation.id
        editingTextID = annotation.id
    }

    private func beginTextEditing(existing annotation: Annotation) {
        documentBeforeTextEditing = document
        selection = annotation.id
        editingTextID = annotation.id
    }

    private func textBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                annotations.first(where: { $0.id == id })?.text ?? ""
            },
            set: { value in
                guard let index = annotations.firstIndex(where: { $0.id == id }) else {
                    return
                }
                document.annotations[index].text = value
                document.annotations[index] = AnnotationRenderer.fitted(
                    document.annotations[index],
                    imageSize: imageSize
                )
            }
        )
    }

    /// Empty text removes the annotation, so a stray click with the text
    /// tool leaves nothing behind and clearing a label deletes it.
    private func commitTextEditing() {
        defer {
            editingTextID = nil
            documentBeforeTextEditing = nil
        }
        guard
            let editingTextID,
            let index = annotations.firstIndex(where: { $0.id == editingTextID })
        else {
            return
        }

        let value = (annotations[index].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            document.annotations.remove(at: index)
            selection = nil
        } else {
            document.annotations[index].text = value
            document.annotations[index] = AnnotationRenderer.fitted(document.annotations[index], imageSize: imageSize)
        }

        if let before = documentBeforeTextEditing, document != before {
            onRecordUndo(before)
        }
    }

    private func cancelTextEditing() {
        if let before = documentBeforeTextEditing {
            document = before
        }
        if let selection, !annotations.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
        editingTextID = nil
        documentBeforeTextEditing = nil
    }

    // MARK: - Regions that sample the image

    private func filteredImage(for annotation: Annotation) -> CGImage? {
        guard let region = filteredRegions[annotation.id], region.area == annotation.sampledArea else {
            return nil
        }
        return region.image
    }

    /// Blur and pixelation wait until a drag ends, being too slow to redo
    /// every frame. A magnifier only crops, so it follows the drag live.
    private func refreshFilteredRegions() {
        let isDragging: Bool
        switch dragAction {
        case .moving, .resizing:
            isDragging = true
        default:
            isDragging = false
        }

        let sampling = annotations.filter(\.tool.samplesImage)
        filteredRegions = filteredRegions.filter { id, region in
            sampling.contains { $0.id == id && $0.sampledArea == region.area }
        }

        guard
            sampling.contains(where: { filteredRegions[$0.id] == nil }),
            let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return
        }

        let pixels = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        for annotation in sampling where filteredRegions[annotation.id] == nil {
            if isDragging, annotation.tool.filterName != nil {
                continue
            }
            guard let filtered = sampledRegion(
                for: annotation.tool,
                of: source,
                in: AnnotationSpace.rect(annotation.sampledArea, in: pixels)
            ) else {
                continue
            }
            filteredRegions[annotation.id] = FilteredRegion(area: annotation.sampledArea, image: filtered)
        }
    }
}
