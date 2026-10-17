import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AnnotationEditorController {
    private var window: NSWindow?
    private var closeObserver: (any NSObjectProtocol)?

    /// `suggestedName` seeds Save As, without an extension. `replacing` is
    /// the file Save writes over, when `image` and `document` are a saved
    /// edit opened again.
    func show(
        image: NSImage,
        document: AnnotationDocument = AnnotationDocument(),
        replacing: URL? = nil,
        suggestedName: String,
        style: AnnotationStyle,
        colorFormat: ColorCodeFormat,
        onStyleChange: @escaping (AnnotationStyle) -> Void,
        onColorFormatChange: @escaping (ColorCodeFormat) -> Void,
        onSave: @escaping (NSImage, AnnotationDocument) -> Void,
        onSaveAs: @escaping (NSImage, AnnotationDocument, URL) -> Void,
        onCopy: @escaping (NSImage) -> Void,
        onCopyText: @escaping (NSImage) -> Void,
        onCopyColor: @escaping (String) -> Void
    ) {
        window?.close()

        let editor = AnnotationEditorView(
            image: image,
            previewImage: ImagePreview.downsample(image),
            initialStyle: style,
            initialColorFormat: colorFormat,
            initialDocument: document,
            replacingFileName: replacing?.lastPathComponent,
            onStyleChange: onStyleChange,
            onColorFormatChange: onColorFormatChange,
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
            onCopyText: onCopyText,
            onCopyColor: onCopyColor
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
        showInDock(while: window)
        window.makeKeyAndOrderFront(nil)
    }

    /// A menu bar app has no Dock icon, which leaves an editor window
    /// unreachable from the Dock and ⌘-Tab once it is behind another app.
    /// While the editor is open the app is a regular one. That also lets it
    /// become active reliably, which AppKit needs before it shows tooltips.
    private func showInDock(while window: NSWindow) {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // Posted on the main queue, as asked above.
            MainActor.assumeIsolated {
                NSApp.setActivationPolicy(.accessory)
                if let observer = self?.closeObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self?.closeObserver = nil
                }
            }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
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
