import AppKit
import SwiftUI

final class PermissionOnboardingWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(
            rootView: PermissionOnboardingView(
                onOpenSettings: {
                    SystemSettingsService.openScreenRecordingSettings()
                },
                onRelaunch: {
                    ScreenRecordingPermission.relaunch()
                },
                onLater: { [weak self] in
                    self?.window?.close()
                }
            )
        )
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
