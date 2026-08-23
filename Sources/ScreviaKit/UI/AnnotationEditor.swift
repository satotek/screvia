import AppKit
import CoreImage
import SwiftUI

@MainActor
final class AnnotationEditorController {
    private var window: NSWindow?

    func show(
        capture: CaptureItem,
        onSave: @escaping (NSImage) -> Void,
        onCopy: @escaping (NSImage) -> Void
    ) {
        window?.close()

        let editor = AnnotationEditorView(
            image: capture.image,
            previewImage: ImagePreview.downsample(capture.image),
            onSave: { [weak self] image in
                onSave(image)
                self?.window?.close()
                self?.window = nil
            },
            onCopy: onCopy
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_020, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("annotation.editorTitle")
        window.minSize = NSSize(width: 720, height: 500)
        window.contentView = NSHostingView(rootView: editor)
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private enum AnnotationTool: String, CaseIterable, Identifiable {
    case rectangle
    case ellipse
    case arrow
    case highlight
    case text
    case blur
    case pixelate

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .rectangle:
            return "rectangle"
        case .ellipse:
            return "circle"
        case .arrow:
            return "arrow.up.right"
        case .highlight:
            return "highlighter"
        case .text:
            return "textformat"
        case .blur:
            return "eye.slash"
        case .pixelate:
            return "square.grid.3x3"
        }
    }

    var title: String {
        L10n.text("annotation.\(rawValue)")
    }

    /// Core Image filter backing this tool, if it is a redaction tool.
    var filterName: String? {
        switch self {
        case .blur:
            return "CIGaussianBlur"
        case .pixelate:
            return "CIPixellate"
        default:
            return nil
        }
    }
}

private enum AnnotationZoom {
    static let minimum: CGFloat = 0.5
    static let maximum: CGFloat = 3.0
    static let step: CGFloat = 0.1

    static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}

private struct Annotation: Identifiable {
    let id: UUID
    let tool: AnnotationTool
    let start: CGPoint
    let end: CGPoint
    var text: String?

    init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        start: CGPoint,
        end: CGPoint,
        text: String? = nil
    ) {
        self.id = id
        self.tool = tool
        self.start = start
        self.end = end
        self.text = text
    }
}

private struct AnnotationEditorView: View {
    let image: NSImage
    let previewImage: NSImage
    let onSave: (NSImage) -> Void
    let onCopy: (NSImage) -> Void

    @State private var selectedTool: AnnotationTool = .rectangle
    @State private var annotations: [Annotation] = []
    @State private var undoStack: [[Annotation]] = []
    @State private var redoStack: [[Annotation]] = []
    @State private var zoomScale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            AnnotationCanvas(
                image: previewImage,
                selectedTool: selectedTool,
                zoomScale: $zoomScale,
                annotations: $annotations,
                undoStack: $undoStack,
                redoStack: $redoStack
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))

            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 500)
    }

    // Undo/redo live here rather than inline in the buttons so the toolbar
    // and the ⌘Z / ⇧⌘Z shortcuts drive the same code path.
    private func performUndo() {
        guard let previous = undoStack.popLast() else {
            return
        }
        redoStack.append(annotations)
        annotations = previous
    }

    private func performRedo() {
        guard let next = redoStack.popLast() else {
            return
        }
        undoStack.append(annotations)
        annotations = next
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            ForEach(AnnotationTool.allCases) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    Label(tool.title, systemImage: tool.symbolName)
                        .labelStyle(.iconOnly)
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(.borderless)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selectedTool == tool ? Color.accentColor.opacity(0.18) : .clear)
                )
                .help(tool.title)
            }

            Divider()
                .frame(height: 22)
                .padding(.horizontal, 4)

            Button(action: performUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(undoStack.isEmpty)
            .keyboardShortcut("z", modifiers: [.command])
            .help("\(L10n.text("app.undo"))  ⌘Z")

            Button(action: performRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(redoStack.isEmpty)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("\(L10n.text("app.redo"))  ⇧⌘Z")

            Spacer()

            zoomControls

            Text(L10n.text("app.nonDestructive"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button {
                adjustZoom(by: -AnnotationZoom.step)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(zoomScale <= AnnotationZoom.minimum)
            .keyboardShortcut("-", modifiers: [.command])
            .help(L10n.text("annotation.zoomOut"))

            Text(L10n.format("annotation.zoomPercent", Int((zoomScale * 100).rounded())))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 48)

            Button {
                adjustZoom(by: AnnotationZoom.step)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(zoomScale >= AnnotationZoom.maximum)
            .keyboardShortcut("+", modifiers: [.command])
            .help(L10n.text("annotation.zoomIn"))

            Button {
                zoomScale = 1
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("0", modifiers: [.command])
            .help(L10n.text("annotation.zoomFit"))
        }
        .padding(3)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private func adjustZoom(by amount: CGFloat) {
        zoomScale = AnnotationZoom.clamped(zoomScale + amount)
    }

    private var footer: some View {
        HStack {
            Text(
                L10n.format(
                    annotations.count == 1 ? "annotation.count.one" : "annotation.count.many",
                    annotations.count
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(L10n.text("app.copy")) {
                onCopy(flattenedImage())
            }
            .keyboardShortcut("c", modifiers: [.command])

            Button(L10n.text("app.save")) {
                onSave(flattenedImage())
            }
            .keyboardShortcut("s", modifiers: [.command])
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func flattenedImage() -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )

        for annotation in annotations {
            draw(annotation, on: result)
        }

        result.unlockFocus()
        return result
    }

    private func draw(_ annotation: Annotation, on image: NSImage) {
        let imageRect = NSRect(origin: .zero, size: image.size)
        let rect = annotationRect(annotation, in: imageRect)
        let color = NSColor.systemRed

        switch annotation.tool {
        case .rectangle:
            color.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 4
            path.stroke()
        case .ellipse:
            color.setStroke()
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = 4
            path.stroke()
        case .highlight:
            NSColor.systemYellow.withAlphaComponent(0.34).setFill()
            NSBezierPath(rect: rect).fill()
        case .text:
            drawText(annotation.text ?? "", in: rect, on: image)
        case .blur, .pixelate:
            if let filterName = annotation.tool.filterName {
                drawFilteredRegion(rect, on: image, filterName: filterName)
            }
        case .arrow:
            color.setStroke()
            let start = imagePoint(annotation.start, in: imageRect)
            let end = imagePoint(annotation.end, in: imageRect)
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            path.lineWidth = 4
            path.stroke()

            let angle = atan2(end.y - start.y, end.x - start.x)
            let wingLength: CGFloat = 14
            let left = CGPoint(
                x: end.x - wingLength * cos(angle - .pi / 6),
                y: end.y - wingLength * sin(angle - .pi / 6)
            )
            let right = CGPoint(
                x: end.x - wingLength * cos(angle + .pi / 6),
                y: end.y - wingLength * sin(angle + .pi / 6)
            )
            path.move(to: left)
            path.line(to: end)
            path.line(to: right)
            path.stroke()
        }
    }

    private func drawText(_ value: String, in rect: CGRect, on image: NSImage) {
        guard !value.isEmpty else {
            return
        }

        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()

        let fontSize = max(13, min(34, rect.height * 0.52))
        value.draw(
            in: rect.insetBy(dx: 9, dy: 5),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        )
    }

    private func drawFilteredRegion(
        _ rect: CGRect,
        on image: NSImage,
        filterName: String
    ) {
        guard let filtered = filteredRegion(of: image, in: rect, filterName: filterName) else {
            return
        }

        filtered.draw(
            in: rect,
            from: NSRect(origin: .zero, size: filtered.size),
            operation: .sourceOver,
            fraction: 1
        )
    }

    private func annotationRect(_ annotation: Annotation, in imageRect: CGRect) -> CGRect {
        let start = imagePoint(annotation.start, in: imageRect)
        let end = imagePoint(annotation.end, in: imageRect)
        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func imagePoint(_ point: CGPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + point.x * imageRect.width,
            y: imageRect.minY + (1 - point.y) * imageRect.height
        )
    }
}


/// Runs `filterName` over the `rect` region of `image` and returns just that
/// region, filtered.
///
/// Both the on-canvas preview and the flattened output go through here, so the
/// blur the user sees while editing is the blur that gets saved. Keeping them
/// on separate code paths is how they drifted apart in the first place.
///
/// `rect` is in the image's own (bottom-left origin) coordinate space.
func filteredRegion(
    of image: NSImage,
    in rect: CGRect,
    filterName: String
) -> NSImage? {
    guard rect.width > 1, rect.height > 1 else {
        return nil
    }

    let regionSize = NSSize(width: rect.width, height: rect.height)
    let region = NSImage(size: regionSize)
    region.lockFocus()
    image.draw(
        in: NSRect(origin: .zero, size: regionSize),
        from: rect,
        operation: .copy,
        fraction: 1
    )
    region.unlockFocus()

    var proposedRect = NSRect(origin: .zero, size: regionSize)
    guard
        let regionImage = region.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ),
        let filter = CIFilter(name: filterName)
    else {
        return nil
    }

    let input = CIImage(cgImage: regionImage)
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

    guard
        let output = filter.outputImage?.cropped(to: input.extent),
        let outputImage = CIContext().createCGImage(output, from: input.extent)
    else {
        return nil
    }

    return NSImage(cgImage: outputImage, size: regionSize)
}

/// Maps a normalized annotation (0...1, top-left origin) onto the image's own
/// bottom-left origin pixel space.
func imageSpaceRect(start: CGPoint, end: CGPoint, imageSize: CGSize) -> CGRect {
    let startPoint = CGPoint(x: start.x * imageSize.width, y: (1 - start.y) * imageSize.height)
    let endPoint = CGPoint(x: end.x * imageSize.width, y: (1 - end.y) * imageSize.height)
    return CGRect(
        x: min(startPoint.x, endPoint.x),
        y: min(startPoint.y, endPoint.y),
        width: abs(endPoint.x - startPoint.x),
        height: abs(endPoint.y - startPoint.y)
    )
}

private struct AnnotationCanvas: View {
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

private struct InlineTextField: View {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(L10n.text("annotation.textPlaceholder"))
                .foregroundStyle(.white.opacity(0.55))
        )
        .textFieldStyle(.plain)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(ScreviaTheme.accent, lineWidth: 2)
        }
        .shadow(color: ScreviaTheme.accent.opacity(0.3), radius: 12)
        .focused($isFocused)
        .onSubmit {
            onCommit()
        }
        .onExitCommand {
            onCancel()
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .accessibilityLabel(L10n.text("annotation.text"))
    }
}

#if DEBUG
#Preview("Annotation editor") {
    AnnotationEditorView(
        image: PreviewFixtures.sampleImage(),
        previewImage: PreviewFixtures.sampleImage(),
        onSave: { _ in },
        onCopy: { _ in }
    )
}
#endif
