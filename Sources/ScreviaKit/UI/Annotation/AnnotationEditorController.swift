import AppKit
import SwiftUI

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
