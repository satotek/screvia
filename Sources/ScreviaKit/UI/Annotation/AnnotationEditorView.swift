import AppKit
import SwiftUI

struct AnnotationEditorView: View {
    let image: NSImage
    let previewImage: NSImage
    let initialStyle: AnnotationStyle
    /// The file Save replaces, when this is a saved edit opened again.
    let replacingFileName: String?
    let onStyleChange: (AnnotationStyle) -> Void
    /// Get the flattened image and the document it came from, so the edit
    /// can be opened again.
    let onSave: (NSImage, AnnotationDocument) -> Void
    let onSaveAs: (NSImage, AnnotationDocument) -> Void
    let onCopy: (NSImage) -> Void
    let onCopyText: (NSImage) -> Void

    @State private var selectedTool: AnnotationTool = .rectangle
    @State private var document: AnnotationDocument
    @State private var undoStack: [AnnotationDocument] = []
    @State private var redoStack: [AnnotationDocument] = []
    @State private var zoomScale: CGFloat = 1
    @State private var selection: Annotation.ID?
    @State private var style: AnnotationStyle
    @State private var isEditingText = false

    init(
        image: NSImage,
        previewImage: NSImage,
        initialStyle: AnnotationStyle,
        initialDocument: AnnotationDocument = AnnotationDocument(),
        replacingFileName: String? = nil,
        onStyleChange: @escaping (AnnotationStyle) -> Void,
        onSave: @escaping (NSImage, AnnotationDocument) -> Void,
        onSaveAs: @escaping (NSImage, AnnotationDocument) -> Void,
        onCopy: @escaping (NSImage) -> Void,
        onCopyText: @escaping (NSImage) -> Void
    ) {
        self.image = image
        self.previewImage = previewImage
        self.initialStyle = initialStyle
        self.replacingFileName = replacingFileName
        self.onStyleChange = onStyleChange
        self.onSave = onSave
        self.onSaveAs = onSaveAs
        self.onCopy = onCopy
        self.onCopyText = onCopyText
        _style = State(initialValue: initialStyle)
        _document = State(initialValue: initialDocument)
    }

    private var selectedAnnotation: Annotation? {
        selection.flatMap { id in document.annotations.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            styleBar
            Divider()

            AnnotationCanvas(
                image: previewImage,
                imageSize: image.size,
                selectedTool: $selectedTool,
                style: style,
                document: $document,
                selection: $selection,
                zoomScale: $zoomScale,
                isEditingText: $isEditingText,
                onRecordUndo: recordUndo
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))

            Divider()
            footer
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    // MARK: - Edits

    private func recordUndo(_ before: AnnotationDocument) {
        undoStack.append(before)
        redoStack.removeAll()
    }

    /// Applies `edit` to `document` as one undoable step.
    private func change(_ edit: (inout AnnotationDocument) -> Void) {
        let before = document
        edit(&document)
        if document != before {
            recordUndo(before)
        }
        dropStaleSelection()
    }

    // Undo/redo live here rather than inline in the buttons so the toolbar
    // and the ⌘Z / ⇧⌘Z shortcuts drive the same code path.
    private func performUndo() {
        guard let previous = undoStack.popLast() else {
            return
        }
        redoStack.append(document)
        document = previous
        dropStaleSelection()
    }

    private func performRedo() {
        guard let next = redoStack.popLast() else {
            return
        }
        undoStack.append(document)
        document = next
        dropStaleSelection()
    }

    private func deleteSelection() {
        guard let selection else {
            return
        }
        change { $0.annotations.removeAll { $0.id == selection } }
    }

    private func deleteAll() {
        change { $0.annotations.removeAll() }
    }

    /// The copy lands slightly down and to the right, where it is visibly a
    /// second shape, and becomes the selection.
    private func duplicateSelection() {
        guard let selectedAnnotation else {
            return
        }
        let copy = selectedAnnotation.duplicated().moved(by: CGVector(dx: 0.02, dy: 0.02), within: document.crop)
        change { $0.annotations.append(copy) }
        selection = copy.id
    }

    /// A style change becomes the style for new annotations and, when an
    /// annotation is selected, changes that one setting on it too.
    private func applyStyle(_ edit: @escaping (inout AnnotationStyle) -> Void) {
        edit(&style)
        onStyleChange(style)

        guard let selection, let index = document.annotations.firstIndex(where: { $0.id == selection }) else {
            return
        }
        let imageSize = image.size
        change { document in
            edit(&document.annotations[index].style)
            document.annotations[index] = AnnotationRenderer.fitted(document.annotations[index], imageSize: imageSize)
        }
    }

    private func dropStaleSelection() {
        if let selection, !document.annotations.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    // MARK: - Bars

    private var toolbar: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationTool.allCases) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    Label(tool.title, systemImage: tool.symbolName)
                        .labelStyle(.iconOnly)
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(.borderless)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selectedTool == tool ? Color.accentColor.opacity(0.18) : .clear)
                )
                .help("\(tool.title)\n\(tool.usage)")
            }

            Divider()
                .frame(height: 22)
                .padding(.horizontal, 4)

            // Undo, redo, duplicate and delete are disabled while typing: a
            // shortcut on a button fires even when a text field has focus,
            // and would act on the document instead of the text.
            iconButton("arrow.uturn.backward", action: performUndo)
                .disabled(undoStack.isEmpty || isEditingText)
                .keyboardShortcut("z", modifiers: [.command])
                .help("\(L10n.text("app.undo"))  ⌘Z")

            iconButton("arrow.uturn.forward", action: performRedo)
                .disabled(redoStack.isEmpty || isEditingText)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("\(L10n.text("app.redo"))  ⇧⌘Z")

            Divider()
                .frame(height: 22)
                .padding(.horizontal, 4)

            iconButton("plus.square.on.square", action: duplicateSelection)
                .disabled(selection == nil || isEditingText)
                .keyboardShortcut("d", modifiers: [.command])
                .help("\(L10n.text("annotation.duplicate"))  ⌘D")

            iconButton("trash", action: deleteSelection)
                .disabled(selection == nil || isEditingText)
                .keyboardShortcut(.delete, modifiers: [])
                .help("\(L10n.text("annotation.delete"))  ⌫")

            Menu {
                Button(L10n.text("annotation.deleteAll"), role: .destructive, action: deleteAll)
                    .disabled(document.annotations.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.text("annotation.more"))

            Divider()
                .frame(height: 22)
                .padding(.horizontal, 4)

            effectsMenu

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var styleBar: some View {
        HStack {
            AnnotationStyleBar(
                style: selectedAnnotation?.style ?? style,
                // Live Text shows its hint even with a shape still selected.
                tool: selectedTool == .liveText ? .liveText : (selectedAnnotation?.tool ?? selectedTool),
                onChange: applyStyle
            )

            Spacer(minLength: 12)

            zoomControls
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 40)
    }

    /// Effects frame the whole image, so they sit apart from the tools and
    /// apply whatever is selected.
    private var effectsMenu: some View {
        Menu {
            Section(L10n.text("effects.border")) {
                Button(L10n.text("effects.noBorder")) {
                    change { $0.effects.borderColor = nil }
                }
                ForEach(AnnotationColor.palette, id: \.self) { color in
                    Button {
                        change { $0.effects.borderColor = color }
                    } label: {
                        Label { Text(color.name) } icon: { Image(nsImage: AnnotationStyleBar.swatchImage(color)) }
                    }
                }
                Picker(L10n.text("effects.borderWidth"), selection: Binding(
                    get: { document.effects.borderWidth },
                    set: { width in change { $0.effects.borderWidth = width } }
                )) {
                    ForEach(ImageEffects.borderWidths, id: \.self) { width in
                        Text(L10n.format("effects.points", Int(width))).tag(width)
                    }
                }
                .disabled(document.effects.borderColor == nil)
            }

            Toggle(L10n.text("effects.shadow"), isOn: Binding(
                get: { document.effects.hasShadow },
                set: { isOn in change { $0.effects.hasShadow = isOn } }
            ))
        } label: {
            Label(L10n.text("effects.title"), systemImage: "photo.artframe")
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(document.effects.isEmpty ? .clear : Color.accentColor.opacity(0.18))
        )
        .help("\(L10n.text("effects.title"))\n\(L10n.text("effects.usage"))")
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
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
            .help("\(L10n.text("annotation.zoomOut"))  ⌘−")

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
            .help("\(L10n.text("annotation.zoomIn"))  ⌘+")

            Button {
                zoomScale = 1
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("0", modifiers: [.command])
            .help("\(L10n.text("annotation.zoomFit"))  ⌘0")
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
                    document.annotations.count == 1 ? "annotation.count.one" : "annotation.count.many",
                    document.annotations.count
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(L10n.text("annotation.copyText")) {
                onCopyText(flattenedImage())
            }
            .help(L10n.text("annotation.copyTextHelp"))

            Button(L10n.text("app.copy")) {
                onCopy(flattenedImage())
            }
            .keyboardShortcut("c", modifiers: [.command])
            // ⌘C belongs to the selected text while typing, and in Live Text.
            .disabled(isEditingText || selectedTool == .liveText)

            Button(L10n.text("app.saveAs")) {
                onSaveAs(flattenedImage(), document)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button(L10n.text("app.save")) {
                onSave(flattenedImage(), document)
            }
            .keyboardShortcut("s", modifiers: [.command])
            .help(replacingFileName.map { L10n.format("annotation.saveReplacesHelp", $0) } ?? "")
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func flattenedImage() -> NSImage {
        AnnotationRenderer.flatten(image, document: document)
    }
}

#if DEBUG
#Preview("Annotation editor") {
    AnnotationEditorView(
        image: PreviewFixtures.sampleImage(),
        previewImage: PreviewFixtures.sampleImage(),
        initialStyle: .standard,
        onStyleChange: { _ in },
        onSave: { _, _ in },
        onSaveAs: { _, _ in },
        onCopy: { _ in },
        onCopyText: { _ in }
    )
}
#endif
