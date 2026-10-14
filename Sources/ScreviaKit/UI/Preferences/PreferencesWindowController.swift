import AppKit
import SwiftUI

final class PreferencesWindowController {
    private var window: NSWindow?

    func show(settings: ScreviaSettings) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("preferences.title")
        window.minSize = NSSize(width: 640, height: 500)
        window.contentView = NSHostingView(rootView: PreferencesView(settings: settings))
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
