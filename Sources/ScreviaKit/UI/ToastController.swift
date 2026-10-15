import AppKit
import SwiftUI

/// A brief message near the top of the screen under the pointer, for
/// results that need no answer, such as text copied by OCR.
final class ToastController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, symbol: String) {
        dismissTask?.cancel()
        panel?.orderOut(nil)

        let hosting = NSHostingView(rootView: ToastView(message: message, symbol: symbol))
        let size = hosting.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        if let screen = ScreenUtilities.screenAtMouse() ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 24))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else {
                return
            }
            self?.panel?.orderOut(nil)
            self?.panel = nil
        }
    }
}

struct ToastView: View {
    let message: String
    let symbol: String

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            }
            .padding(12)
    }
}

#if DEBUG
#Preview("Toast") {
    ToastView(message: "Copied 42 characters", symbol: "text.viewfinder")
}
#endif
