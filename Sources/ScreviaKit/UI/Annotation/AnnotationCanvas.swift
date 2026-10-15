import AppKit
import SwiftUI

struct AnnotationCanvas: View {
    /// What is on screen; may be a downsampled copy of the capture.
    let image: NSImage
    /// The full capture's size in points, the unit line widths are given in.
    let imageSize: CGSize
    let selectedTool: AnnotationTool
    @Binding var selection: Annotation.ID?
    @Binding var zoomScale: CGFloat
    @Binding var annotations: [Annotation]
    @Binding var undoStack: [[Annotation]]
    @Binding var redoStack: [[Annotation]]

    /// What the current pointer drag is doing, decided when it starts.
    private enum DragAction {
        case drawing(start: CGPoint, end: CGPoint)
        /// `original` is the annotation as the drag found it; every update is
        /// computed from it, not from the previous frame, so rounding never
        /// accumulates. `before` is the undo snapshot.
        case moving(original: Annotation, before: [Annotation])
        case resizing(original: Annotation, handle: AnnotationHandle, before: [Annotation])
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

    @State private var dragAction: DragAction?
    @State private var magnificationStart: CGFloat?
    @State private var editingTextID: UUID?
    @State private var annotationsBeforeTextEditing: [Annotation]?

    /// Filtered region images keyed by annotation id, each tagged with the
    /// bounds it was computed for so a moved or resized region is redone. A
    /// region being dragged falls back to a cheap sketch until it settles.
    @State private var filteredRegions: [UUID: FilteredRegion] = [:]

    private var selectedAnnotation: Annotation? {
        selection.flatMap { id in annotations.first { $0.id == id } }
    }

    var body: some View {
        GeometryReader { geometry in
            let contentSize = canvasContentSize(in: geometry.size)
            let imageRect = zoomedImageRect(in: contentSize, containerSize: geometry.size)

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)

                    Canvas { context, _ in
                        let pointScale = imageRect.width / max(imageSize.width, 1)
                        context.withCGContext { cgContext in
                            for annotation in annotations {
                                AnnotationRenderer.draw(
                                    annotation,
                                    in: cgContext,
                                    imageRect: imageRect,
                                    pointScale: pointScale,
                                    filteredRegion: filteredImage(for: annotation)
                                )
                            }

                            if case let .drawing(start, end) = dragAction {
                                AnnotationRenderer.draw(
                                    Annotation(tool: selectedTool, start: start, end: end),
                                    in: cgContext,
                                    imageRect: imageRect,
                                    pointScale: pointScale
                                )
                            }
                        }

                        if editingTextID == nil, let selectedAnnotation {
                            drawSelection(of: selectedAnnotation, in: &context, imageRect: imageRect)
                        }
                    }
                    .allowsHitTesting(false)

                    if let editingTextID,
                       let annotation = annotations.first(where: { $0.id == editingTextID }) {
                        let editorRect = textEditorRect(for: annotation, in: imageRect)
                        InlineTextField(
                            text: textBinding(for: editingTextID),
                            onCommit: commitTextEditing,
                            onCancel: cancelTextEditing
                        )
                        .frame(width: editorRect.width, height: editorRect.height)
                        .position(x: editorRect.midX, y: editorRect.midY)
                        .zIndex(2)
                    }
                }
                .frame(width: contentSize.width, height: contentSize.height)
                .contentShape(Rectangle())
                .gesture(
                    // Zero distance, so a plain click can select or deselect.
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragAction == nil {
                                beginDrag(at: value.startLocation, in: imageRect)
                            }
                            updateDrag(value, in: imageRect)
                        }
                        .onEnded { value in
                            endDrag(value, in: imageRect)
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
        .onChange(of: annotations, initial: true) { _, _ in
            refreshFilteredRegions()
        }
    }

    // MARK: - Dragging

    /// A handle of the selected annotation wins over everything, so a shape
    /// can be resized right after it is drawn without switching tools.
    /// Moving needs the select tool; with a drawing tool, a drag that starts
    /// on an existing shape draws a new one on top.
    private func beginDrag(at point: CGPoint, in imageRect: CGRect) {
        if editingTextID != nil {
            commitTextEditing()
        }

        if let selectedAnnotation,
           let handle = selectedAnnotation.handle(at: point, in: imageRect, radius: Self.handleHitRadius) {
            dragAction = .resizing(original: selectedAnnotation, handle: handle, before: annotations)
            return
        }

        if selectedTool == .select {
            let hit = annotations.last { $0.contains(point, in: imageRect, tolerance: Self.hitTolerance) }
            selection = hit?.id
            dragAction = hit.map { .moving(original: $0, before: annotations) } ?? .idle
            return
        }

        selection = nil
        let start = AnnotationSpace.normalizedPoint(point, in: imageRect)
        dragAction = .drawing(start: start, end: start)
    }

    private func updateDrag(_ value: DragGesture.Value, in imageRect: CGRect) {
        switch dragAction {
        case let .drawing(start, _):
            dragAction = .drawing(start: start, end: AnnotationSpace.normalizedPoint(value.location, in: imageRect))
        case let .moving(original, _):
            replace(original.moved(by: CGVector(
                dx: value.translation.width / imageRect.width,
                dy: value.translation.height / imageRect.height
            )))
        case let .resizing(original, handle, _):
            replace(original.resized(handle, to: AnnotationSpace.normalizedPoint(value.location, in: imageRect)))
        case .idle, nil:
            break
        }
    }

    private func endDrag(_ value: DragGesture.Value, in imageRect: CGRect) {
        let action = dragAction
        dragAction = nil

        switch action {
        case let .drawing(start, _):
            let end = AnnotationSpace.normalizedPoint(value.location, in: imageRect)
            if selectedTool == .text {
                let bounds = normalizedTextBounds(start: start, end: end)
                beginTextEditing(start: bounds.0, end: bounds.1)
                return
            }

            guard abs(end.x - start.x) > 0.005, abs(end.y - start.y) > 0.005 else {
                return
            }

            let annotation = Annotation(tool: selectedTool, start: start, end: end)
            undoStack.append(annotations)
            annotations.append(annotation)
            redoStack.removeAll()
            selection = annotation.id
        case let .moving(_, before), let .resizing(_, _, before):
            if annotations != before {
                undoStack.append(before)
                redoStack.removeAll()
            }
            refreshFilteredRegions()
        case .idle, nil:
            break
        }
    }

    private func replace(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else {
            return
        }
        annotations[index] = annotation
    }

    private func drawSelection(of annotation: Annotation, in context: inout GraphicsContext, imageRect: CGRect) {
        if !annotation.tool.isLine {
            let outline = AnnotationSpace.rect(annotation.bounds, in: imageRect)
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

    // MARK: - Text

    private func beginTextEditing(start: CGPoint, end: CGPoint) {
        if editingTextID != nil {
            commitTextEditing()
        }

        let annotation = Annotation(tool: .text, start: start, end: end, text: "")
        annotationsBeforeTextEditing = annotations
        annotations.append(annotation)
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
                annotations[index].text = value
            }
        )
    }

    private func commitTextEditing() {
        guard let editingTextID,
              let index = annotations.firstIndex(where: { $0.id == editingTextID }) else {
            self.editingTextID = nil
            annotationsBeforeTextEditing = nil
            return
        }

        let value = (annotations[index].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            if let previous = annotationsBeforeTextEditing {
                annotations = previous
            }
        } else {
            annotations[index].text = value
            if let previous = annotationsBeforeTextEditing {
                undoStack.append(previous)
                redoStack.removeAll()
            }
        }

        self.editingTextID = nil
        annotationsBeforeTextEditing = nil
    }

    private func cancelTextEditing() {
        if let previous = annotationsBeforeTextEditing {
            annotations = previous
        }
        editingTextID = nil
        annotationsBeforeTextEditing = nil
    }

    private func normalizedTextBounds(start: CGPoint, end: CGPoint) -> (CGPoint, CGPoint) {
        let originX = min(start.x, end.x)
        let originY = min(start.y, end.y)
        let width = min(max(abs(end.x - start.x), 0.28), 1)
        let height = min(max(abs(end.y - start.y), 0.08), 1)
        let x = min(max(originX, 0), 1 - width)
        let y = min(max(originY, 0), 1 - height)

        return (
            CGPoint(x: x, y: y),
            CGPoint(x: x + width, y: y + height)
        )
    }

    private func textEditorRect(for annotation: Annotation, in imageRect: CGRect) -> CGRect {
        // Larger than the annotation itself, so a small box still leaves room
        // to type.
        let start = AnnotationSpace.point(annotation.start, in: imageRect)
        let end = AnnotationSpace.point(annotation.end, in: imageRect)
        let baseRect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        let minimumWidth = min(max(imageRect.width * 0.24, 160), 300)
        let minimumHeight = min(max(imageRect.height * 0.08, 38), 60)
        let width = min(max(baseRect.width, minimumWidth), imageRect.width)
        let height = min(max(baseRect.height, minimumHeight), imageRect.height)
        let x = min(
            max(baseRect.midX - width / 2, imageRect.minX),
            imageRect.maxX - width
        )
        let y = min(
            max(baseRect.midY - height / 2, imageRect.minY),
            imageRect.maxY - height
        )

        return CGRect(x: x, y: y, width: width, height: height)
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

    // MARK: - Layout

    private func canvasContentSize(in containerSize: CGSize) -> CGSize {
        let imageSize = scaledImageSize(in: containerSize)
        return CGSize(
            width: max(containerSize.width, imageSize.width + 48),
            height: max(containerSize.height, imageSize.height + 48)
        )
    }

    private func zoomedImageRect(in contentSize: CGSize, containerSize: CGSize) -> CGRect {
        let size = scaledImageSize(in: containerSize)
        return CGRect(
            x: max((contentSize.width - size.width) / 2, 24),
            y: max((contentSize.height - size.height) / 2, 24),
            width: size.width,
            height: size.height
        )
    }

    private func scaledImageSize(in containerSize: CGSize) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else {
            return containerSize
        }

        let availableWidth = max(containerSize.width - 48, 1)
        let availableHeight = max(containerSize.height - 48, 1)
        let fitScale = min(
            availableWidth / image.size.width,
            availableHeight / image.size.height
        )
        let scale = fitScale * zoomScale
        return CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
    }
}
