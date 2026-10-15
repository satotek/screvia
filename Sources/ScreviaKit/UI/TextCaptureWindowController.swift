import AppKit
import SwiftUI

/// Shows what Capture Text read: the image, where Live Text picks out any
/// part, and the full text, which can be edited before copying.
final class TextCaptureWindowController {
    private var window: NSWindow?
    private var hosting: NSHostingView<TextCaptureView>?

    /// Opens the window with `text` still being recognized; call `update`
    /// when it is ready.
    func show(image: NSImage, onCopyAll: @escaping (String) -> Void) {
        window?.close()

        let hosting = NSHostingView(rootView: TextCaptureView(image: image, text: nil, onCopyAll: onCopyAll))
        // See AnnotationEditorController: the window is sized here and by
        // the user, never by the content.
        hosting.sizingOptions = [.minSize]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("textCapture.title")
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        self.hosting = hosting
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// `nil` text means nothing was found.
    func update(text: String?) {
        guard let hosting else {
            return
        }
        let view = hosting.rootView
        hosting.rootView = TextCaptureView(
            image: view.image,
            text: .some(text ?? ""),
            onCopyAll: view.onCopyAll
        )
    }
}

struct TextCaptureView: View {
    let image: NSImage
    /// `nil` while recognizing; empty when the image has no text.
    let text: String?
    let onCopyAll: (String) -> Void

    @State private var editedText = ""

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let fitted = Self.aspectFit(image.size, in: geometry.size)
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: fitted.width, height: fitted.height)
                    LiveTextOverlay(image: image)
                        .frame(width: fitted.width, height: fitted.height)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .padding(16)
            .frame(minHeight: 160)
            .background(Color(nsColor: .underPageBackgroundColor))

            Divider()

            Group {
                if text == nil {
                    ProgressView(L10n.text("textCapture.recognizing"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if text?.isEmpty == true {
                    Text(L10n.text("error.noTextFound"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TextEditor(text: $editedText)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                }
            }
            .frame(minHeight: 140)

            Divider()

            HStack {
                Text(L10n.text("textCapture.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("textCapture.copyAll")) {
                    onCopyAll(editedText)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editedText.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 460, minHeight: 420)
        .onChange(of: text, initial: true) { _, newValue in
            editedText = newValue ?? ""
        }
    }

    private static func aspectFit(_ size: CGSize, in container: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else {
            return container
        }
        let scale = min(container.width / size.width, container.height / size.height, 1)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

#if DEBUG
#Preview("Text capture") {
    TextCaptureView(image: PreviewFixtures.sampleImage(), text: "Hello Screvia\n画面を撮影する", onCopyAll: { _ in })
        .frame(width: 640, height: 560)
}
#endif
