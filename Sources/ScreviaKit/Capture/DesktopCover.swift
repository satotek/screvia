import AppKit

/// Covers the desktop icons with the wallpaper for the moment of a capture.
///
/// Finder can hide its icons only through a setting that restarts it, which
/// is too slow and too visible for one capture. A window of the wallpaper
/// one level above the icons, and below every app window, hides them
/// instead.
final class DesktopCover {
    private var windows: [NSWindow] = []

    func show() {
        hide()
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

        for screen in NSScreen.screens {
            // A screen whose wallpaper cannot be read keeps its icons: a wrong
            // backdrop would be worse in the capture than the icons are.
            guard
                let url = NSWorkspace.shared.desktopImageURL(for: screen),
                let wallpaper = NSImage(contentsOf: url)
            else {
                continue
            }

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = level
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.isReleasedWhenClosed = false

            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer?.contents = wallpaper
            // Fill Screen, the default wallpaper scaling.
            view.layer?.contentsGravity = .resizeAspectFill
            view.layer?.backgroundColor = NSColor.black.cgColor
            window.contentView = view

            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }
}
