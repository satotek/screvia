import AppKit
import SwiftUI

/// The Settings window, laid out as Mac apps' settings are: a toolbar of
/// panes, a title naming the open pane, and a fixed size for each.
final class PreferencesWindowController {
    private var window: NSWindow?

    func show(settings: ScreviaSettings) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for tab in PreferencesTab.allCases {
            let pane = NSHostingController(rootView: PreferencesPane(tab: tab, settings: settings))
            // The window takes each pane's size as it is chosen.
            pane.sizingOptions = .preferredContentSize
            // The tab view controller titles the window after the open pane.
            pane.title = tab.title
            let item = NSTabViewItem(viewController: pane)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        // Neither resizable nor full-screen: tiling window managers such as
        // AeroSpace float a window without a working full-screen button, as
        // they do System Settings, instead of stretching it over the screen.
        window.styleMask = [.titled, .closable]
        window.collectionBehavior.insert(.fullScreenNone)
        window.toolbarStyle = .preference
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Otherwise the file name template opens selected, as if to be typed over.
        window.makeFirstResponder(nil)
    }
}
