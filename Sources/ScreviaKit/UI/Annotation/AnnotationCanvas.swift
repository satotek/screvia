import AppKit
import SwiftUI

struct AnnotationCanvas: View {
    let image: NSImage
    let selectedTool: AnnotationTool
    @Binding var zoomScale: CGFloat
    @Binding var annotations: [Annotation]
    @Binding var undoStack: [[Annotation]]
    @Binding var redoStack: [[Annotation]]

    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    @State private var magnificationStart: CGFloat?
    @State private var editingTextID: UUID?
    @State private var annotationsBeforeTextEditing: [Annotation]?

    /// Filtered region images keyed by annotation id. Committed annotations
    /// never change shape, so each one is computed once; the in-progress drag
    /// annotation is deliberately absent and falls back to a cheap sketch.
    @State private var filteredRegions: [UUID: NSImage] = [:]

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
                        for annotation in annotations {
                            draw(annotation, in: &context, imageRect: imageRect)
                        }

                        if let dragStart, let dragEnd {
                            let preview = Annotation(tool: selectedTool, start: dragStart, end: dragEnd)
                            draw(preview, in: &context, imageRect: imageRect)
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
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if editingTextID != nil, dragStart == nil {
                                commitTextEditing()
                            }

                            let point = normalizedPoint(value.location, in: imageRect)
                            if dragStart == nil {
                                dragStart = normalizedPoint(value.startLocation, in: imageRect)
                            }
                            dragEnd = point
                        }
                        .onEnded { value in
                            defer {
                                dragStart = nil
                                dragEnd = nil
                            }

                            let start = normalizedPoint(value.startLocation, in: imageRect)
                            let end = normalizedPoint(value.location, in: imageRect)
                            if selectedTool == .text {
                                let bounds = normalizedTextBounds(start: start, end: end)
                                beginTextEditing(start: bounds.0, end: bounds.1)
                                return
                            }

                            guard abs(end.x - start.x) > 0.005, abs(end.y - start.y) > 0.005 else {
                                return
                            }

                            undoStack.append(annotations)
                            annotations.append(
                                Annotation(
                                    tool: selectedTool,
                                    start: start,
                                    end: end
                                )
                            )
                            redoStack.removeAll()
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
        .onChange(of: annotations.map(\.id), initial: true) { _, _ in
            refreshFilteredRegions()
        }
    }

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
        // `annotationRect` belongs to AnnotationEditorView, which works in the
        // image's own coordinates. Here we need view coordinates, so build the
        // rect from the same normalized endpoints `draw` uses.
        let start = point(annotation.start, in: imageRect)
        let end = point(annotation.end, in: imageRect)
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

    private func refreshFilteredRegions() {
        let live = Set(annotations.map(\.id))
        filteredRegions = filteredRegions.filter { live.contains($0.key) }

        for annotation in annotations {
            guard
                filteredRegions[annotation.id] == nil,
                let filterName = annotation.tool.filterName
            else {
                continue
            }

            let rect = imageSpaceRect(
                start: annotation.start,
                end: annotation.end,
                imageSize: image.size
            )
            filteredRegions[annotation.id] = filteredRegion(
                of: image,
                in: rect,
                filterName: filterName
            )
        }
    }

    private func draw(_ annotation: Annotation, in context: inout GraphicsContext, imageRect: CGRect) {
        let start = point(annotation.start, in: imageRect)
        let end = point(annotation.end, in: imageRect)
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        let red = Color.red

        switch annotation.tool {
        case .rectangle:
            context.stroke(Path(rect), with: .color(red), lineWidth: 3)
        case .ellipse:
            context.stroke(Path(ellipseIn: rect), with: .color(red), lineWidth: 3)
        case .highlight:
            context.fill(Path(rect), with: .color(.yellow.opacity(0.35)))
        case .text:
            context.fill(Path(rect), with: .color(.black.opacity(0.62)))
            if let text = annotation.text, !text.isEmpty {
                context.draw(
                    Text(text)
                        .font(.system(size: max(13, min(34, rect.height * 0.52)), weight: .semibold))
                        .foregroundStyle(.white),
                    at: CGPoint(x: rect.minX + 9, y: rect.minY + 6),
                    anchor: .topLeading
                )
            }
        case .blur:
            if let filtered = filteredRegions[annotation.id] {
                context.draw(Image(nsImage: filtered), in: rect)
            } else {
                context.fill(Path(rect), with: .color(.black.opacity(0.28)))
                drawBlurPreview(in: rect, context: &context)
            }
        case .pixelate:
            if let filtered = filteredRegions[annotation.id] {
                context.draw(Image(nsImage: filtered), in: rect)
            } else {
                drawPixelatePreview(in: rect, context: &context)
            }
        case .arrow:
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(red), lineWidth: 3)

            let angle = atan2(end.y - start.y, end.x - start.x)
            let wingLength: CGFloat = 12
            let left = CGPoint(
                x: end.x - wingLength * cos(angle - .pi / 6),
                y: end.y - wingLength * sin(angle - .pi / 6)
            )
            let right = CGPoint(
                x: end.x - wingLength * cos(angle + .pi / 6),
                y: end.y - wingLength * sin(angle + .pi / 6)
            )
            path.move(to: left)
            path.addLine(to: end)
            path.addLine(to: right)
            context.stroke(path, with: .color(red), lineWidth: 3)
        }
    }

    private func drawBlurPreview(in rect: CGRect, context: inout GraphicsContext) {
        let step: CGFloat = 9
        for index in 0..<max(1, Int(rect.width / step)) {
            let x = rect.minX + CGFloat(index) * step
            let stripe = CGRect(x: x, y: rect.minY, width: step / 2, height: rect.height)
            context.fill(Path(stripe), with: .color(.white.opacity(0.08)))
        }
    }

    private func drawPixelatePreview(in rect: CGRect, context: inout GraphicsContext) {
        let step: CGFloat = 12
        let columns = max(1, Int(rect.width / step))
        let rows = max(1, Int(rect.height / step))

        for column in 0..<columns {
            for row in 0..<rows {
                guard (column + row).isMultiple(of: 2) else {
                    continue
                }

                let block = CGRect(
                    x: rect.minX + CGFloat(column) * step,
                    y: rect.minY + CGFloat(row) * step,
                    width: step,
                    height: step
                )
                context.fill(Path(block), with: .color(.white.opacity(0.22)))
            }
        }
    }

    private func point(_ normalized: CGPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + normalized.x * imageRect.width,
            y: imageRect.minY + normalized.y * imageRect.height
        )
    }

    private func normalizedPoint(_ point: CGPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max((point.x - imageRect.minX) / imageRect.width, 0), 1),
            y: min(max((point.y - imageRect.minY) / imageRect.height, 0), 1)
        )
    }

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
