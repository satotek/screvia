import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AnnotationEditorController {
    private var window: NSWindow?

    /// `suggestedName` seeds Save As, without an extension.
    func show(
        image: NSImage,
        suggestedName: String,
        style: AnnotationStyle,
        onStyleChange: @escaping (AnnotationStyle) -> Void,
        onSave: @escaping (NSImage) -> Void,
        onSaveAs: @escaping (NSImage, URL) -> Void,
        onCopy: @escaping (NSImage) -> Void,
        onCopyText: @escaping (NSImage) -> Void
    ) {
        window?.close()

        let editor = AnnotationEditorView(
            image: image,
            previewImage: ImagePreview.downsample(image),
            initialStyle: style,
            onStyleChange: onStyleChange,
            onSave: { [weak self] image in
                onSave(image)
                self?.window?.close()
                self?.window = nil
            },
            onSaveAs: { [weak self] image in
                self?.chooseDestination(suggestedName: suggestedName) { url in
                    onSaveAs(image, url)
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
        window.minSize = NSSize(width: 720, height: 500)
        window.contentView = NSHostingView(rootView: editor)
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
