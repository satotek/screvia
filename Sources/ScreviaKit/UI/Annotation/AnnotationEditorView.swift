import AppKit
import SwiftUI

struct AnnotationEditorView: View {
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
