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
    @State private var selection: Annotation.ID?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            AnnotationCanvas(
                image: previewImage,
                imageSize: image.size,
                selectedTool: selectedTool,
                selection: $selection,
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
        dropStaleSelection()
    }

    private func performRedo() {
        guard let next = redoStack.popLast() else {
            return
        }
        undoStack.append(annotations)
        annotations = next
        dropStaleSelection()
    }

    private func deleteSelection() {
        guard let selection else {
            return
        }
        undoStack.append(annotations)
        annotations.removeAll { $0.id == selection }
        redoStack.removeAll()
        self.selection = nil
    }

    private func dropStaleSelection() {
        if let selection, !annotations.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
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

            Button(action: deleteSelection) {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil)
            .keyboardShortcut(.delete, modifiers: [])
            .help("\(L10n.text("annotation.delete"))  ⌫")

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
        AnnotationRenderer.flatten(image, annotations: annotations)
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
