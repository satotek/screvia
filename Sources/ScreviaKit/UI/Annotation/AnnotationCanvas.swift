import AppKit
import SwiftUI

struct AnnotationCanvas: View {
    /// What is on screen; may be a downsampled copy of the capture.
    let image: NSImage
    /// The full capture's size in points, the unit styles are given in.
    let imageSize: CGSize
    let selectedTool: AnnotationTool
    /// The style new annotations get.
    let style: AnnotationStyle
    @Binding var document: AnnotationDocument
    @Binding var selection: Annotation.ID?
    @Binding var zoomScale: CGFloat
    /// Set while a text field is open, so the editor can keep shortcuts such
    /// as Delete away from it.
    @Binding var isEditingText: Bool
    /// Called with the document as it was before each finished edit.
    let onRecordUndo: (AnnotationDocument) -> Void

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
        /// A click on empty space with the select tool.
        case idle
    }

    private struct FilteredRegion {
        let bounds: CGRect
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

                    if let editingTextID,
                       let annotation = annotations.first(where: { $0.id == editingTextID }) {
                        let pointScale = layout.imageRect.width / max(imageSize.width, 1)
                        let rect = AnnotationSpace.rect(annotation.bounds, in: layout.imageRect)
                        let font = AnnotationRenderer.font(for: annotation.style, pointScale: pointScale)
                        InlineTextField(
                            text: textBinding(for: editingTextID),
                            font: font,
                            horizontalPadding: annotation.style.fontSize * 0.45 * pointScale,
                            onCommit: commitTextEditing,
                            onCancel: cancelTextEditing
                        )
                        // A caret's width of slack, so typing never clips
                        // before the box catches up.
                        .frame(width: rect.width + font.pointSize, height: rect.height)
                        .position(x: rect.midX + font.pointSize / 2, y: rect.midY)
                        .zIndex(2)
                    }
                }
                .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                .contentShape(Rectangle())
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
                        }
                )
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

    private func draw(in context: inout GraphicsContext, layout: CanvasLayout) {
        let imageRect = layout.imageRect
        let pointScale = imageRect.width / max(imageSize.width, 1)

        context.drawLayer { layer in
            layer.clip(to: Path(layout.visibleRect))
            layer.withCGContext { cgContext in
                // The text being edited is shown by its text field instead.
                AnnotationRenderer.draw(
                    annotations.filter { $0.id != editingTextID },
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

        if case let .cropping(start, end) = dragAction {
            drawCropPreview(
                AnnotationSpace.rect(Self.box(start, end), in: imageRect),
                visibleRect: layout.visibleRect,
                in: &context
            )
        }

        if editingTextID == nil, let selectedAnnotation {
            drawSelection(of: selectedAnnotation, in: &context, imageRect: imageRect)
        }
    }

    private func inProgressAnnotation() -> Annotation? {
        switch dragAction {
        case let .drawing(start, end) where selectedTool != .text && selectedTool != .step:
            return Annotation(tool: selectedTool, start: start, end: end, style: style)
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
    /// Moving needs the select tool; with a drawing tool, a drag that starts
    /// on an existing shape draws a new one on top.
    private func beginDrag(at point: CGPoint, layout: CanvasLayout) {
        if editingTextID != nil {
            commitTextEditing()
        }

        let imageRect = layout.imageRect
        if let selectedAnnotation,
           let handle = selectedAnnotation.handle(at: point, in: imageRect, radius: Self.handleHitRadius) {
            dragAction = .resizing(original: selectedAnnotation, handle: handle, before: document)
            return
        }

        let hit = layout.visibleRect.contains(point)
            ? annotations.last { $0.contains(point, in: imageRect, tolerance: Self.hitTolerance) }
            : nil
        let start = AnnotationSpace.normalizedPoint(point, in: imageRect, within: document.crop)

        switch selectedTool {
        case .select:
            selection = hit?.id
            dragAction = hit.map { .moving(original: $0, before: document) } ?? .idle
        case .text where hit?.tool == .text:
            if let hit {
                beginTextEditing(existing: hit)
            }
            dragAction = .idle
        case .crop:
            selection = nil
            dragAction = .cropping(start: start, end: start)
        case .freehand:
            selection = nil
            dragAction = .sketching(points: [start])
        default:
            selection = nil
            dragAction = .drawing(start: start, end: start)
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
            replace(original.resized(handle, to: point, within: document.crop))
        case .idle, nil:
            break
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
                return
            }
            let before = document
            document.crop = crop
            selection = nil
            onRecordUndo(before)
        case let .moving(original, before):
            if document != before {
                onRecordUndo(before)
            } else if original.tool == .text, isDoubleClick(on: original.id) {
                beginTextEditing(existing: original)
            }
            refreshFilteredRegions()
        case let .resizing(_, _, before):
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
            beginTextEditing(at: start)
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
                return
            }
            add(Annotation(tool: selectedTool, start: start, end: end, style: style))
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

    private func beginTextEditing(at origin: CGPoint) {
        documentBeforeTextEditing = document
        let annotation = AnnotationRenderer.fitted(
            Annotation(tool: .text, start: origin, end: origin, text: "", style: style),
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

    // MARK: - Redaction filters

    private func filteredImage(for annotation: Annotation) -> CGImage? {
        guard let region = filteredRegions[annotation.id], region.bounds == annotation.bounds else {
            return nil
        }
        return region.image
    }

    private func refreshFilteredRegions() {
        switch dragAction {
        case .moving, .resizing:
            return
        default:
            break
        }

        let redactions = annotations.filter { $0.tool.filterName != nil }
        filteredRegions = filteredRegions.filter { id, region in
            redactions.contains { $0.id == id && $0.bounds == region.bounds }
        }

        guard
            redactions.contains(where: { filteredRegions[$0.id] == nil }),
            let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return
        }

        let pixels = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        for annotation in redactions where filteredRegions[annotation.id] == nil {
            guard
                let filterName = annotation.tool.filterName,
                let filtered = filteredRegion(
                    of: source,
                    in: AnnotationSpace.rect(annotation.bounds, in: pixels),
                    filterName: filterName
                )
            else {
                continue
            }
            filteredRegions[annotation.id] = FilteredRegion(bounds: annotation.bounds, image: filtered)
        }
    }
}
