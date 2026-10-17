import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AnnotationEditorController {
    private var window: NSWindow?

    /// `suggestedName` seeds Save As, without an extension. `replacing` is
    /// the file Save writes over, when `image` and `document` are a saved
    /// edit opened again.
    func show(
        image: NSImage,
        document: AnnotationDocument = AnnotationDocument(),
        replacing: URL? = nil,
        suggestedName: String,
        style: AnnotationStyle,
        onStyleChange: @escaping (AnnotationStyle) -> Void,
        onSave: @escaping (NSImage, AnnotationDocument) -> Void,
        onSaveAs: @escaping (NSImage, AnnotationDocument, URL) -> Void,
        onCopy: @escaping (NSImage) -> Void,
        onCopyText: @escaping (NSImage) -> Void
    ) {
        window?.close()

        let editor = AnnotationEditorView(
            image: image,
            previewImage: ImagePreview.downsample(image),
            initialStyle: style,
            initialDocument: document,
            replacingFileName: replacing?.lastPathComponent,
            onStyleChange: onStyleChange,
            onSave: { [weak self] image, document in
                onSave(image, document)
                self?.window?.close()
                self?.window = nil
            },
            onSaveAs: { [weak self] image, document in
                self?.chooseDestination(suggestedName: suggestedName) { url in
                    onSaveAs(image, document, url)
                }
            },
            onCopy: onCopy,
            onCopyText: onCopyText
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_020, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("annotation.editorTitle")
        // Says which file Save will replace.
        window.subtitle = replacing?.lastPathComponent ?? ""
        window.minSize = NSSize(width: 720, height: 500)
        // Only the minimum size comes from SwiftUI. By default the hosting
        // view also resizes the window to the content's ideal size, and the
        // canvas sizes itself from the window, so the two can chase each
        // other until AppKit aborts with too many constraint passes.
        let hosting = NSHostingView(rootView: editor)
        hosting.sizingOptions = [.minSize]
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// A sheet on the editor, so it is clear which image is being saved.
    /// The format follows the extension the user picks.
    private func chooseDestination(suggestedName: String, completion: @escaping (URL) -> Void) {
        guard let window else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.nameFieldStringValue = "\(suggestedName)-edited.png"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
                completion(url)
            }
        }
    }
}
