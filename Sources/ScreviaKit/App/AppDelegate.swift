import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        super.init()
    }

    private let model = ScreviaModel()
    private var statusItem: NSStatusItem?
    private var capturePopover: NSPopover?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarImage()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleCaptureHub)
        self.statusItem = statusItem

        model.start()
    }

    /// The status bar glyph.
    ///
    /// A vector PDF rather than an SF Symbol, so the menu bar carries Screvia's
    /// own mark instead of one shared with every other capture tool. Template
    /// mode has to be set explicitly here — SF Symbols get it for free, bundled
    /// images do not, and without it the glyph goes solid black in dark mode.
    private static func menuBarImage() -> NSImage? {
        // Deliberately not Bundle.module: SwiftPM's generated accessor calls
        // fatalError when the resource bundle is missing, which would turn a
        // missing icon into a launch crash. Locate the bundle by hand so the
        // fallback below can actually run.
        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL.appendingPathComponent("Screvia_ScreviaKit.bundle/Resources"),
            Bundle.main.bundleURL.appendingPathComponent(
                "Contents/Resources/Screvia_ScreviaKit.bundle/Resources"
            )
        ].compactMap { $0?.appendingPathComponent("MenuBarIcon.pdf") }

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                image.accessibilityDescription = "Screvia"
                return image
            }
        }

        Log.ui.error("MenuBarIcon.pdf missing from the bundle; falling back to an SF Symbol")
        return NSImage(
            systemSymbolName: "camera.viewfinder",
            accessibilityDescription: "Screvia"
        )
    }

    public func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    @objc private func toggleCaptureHub() {
        guard let button = statusItem?.button else {
            return
        }

        if let capturePopover, capturePopover.isShown {
            capturePopover.performClose(nil)
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: CaptureHubView(
                displays: model.displayInfos(),
                history: model.captureHistory,
                onCaptureFullScreen: { [weak self] displayID in
                    self?.closeCaptureHub()
                    self?.model.captureFullScreen(displayID: displayID)
                },
                onCaptureArea: { [weak self] in
                    self?.closeCaptureHub()
                    self?.model.captureArea()
                },
                onCaptureWindow: { [weak self] in
                    self?.closeCaptureHub()
                    self?.model.captureWindow()
                },
                onCaptureScroll: { [weak self] in
                    self?.closeCaptureHub()
                    self?.model.captureScroll()
                },
                onEditHistory: { [weak self] entry in
                    self?.closeCaptureHub()
                    self?.model.editHistoryEntry(entry)
                },
                onCopyHistory: { [weak self] entry in
                    self?.closeCaptureHub()
                    self?.model.copyHistoryEntry(entry)
                },
                onPinHistory: { [weak self] entry in
                    self?.closeCaptureHub()
                    self?.model.pinHistoryEntry(entry)
                },
                onRemoveHistory: { [weak self] entry in
                    self?.closeCaptureHub()
                    self?.model.removeHistoryEntry(entry)
                },
                onOpenPreferences: { [weak self] in
                    self?.closeCaptureHub()
                    self?.model.openPreferences()
                },
                onOpenAbout: { [weak self] in
                    self?.closeCaptureHub()
                    self?.model.openAbout()
                },
                onOpenLicenses: { [weak self] in
                    self?.closeCaptureHub()
                    self?.model.openLicenses()
                },
                onOpenScreenRecordingSettings: { [weak self] in
                    self?.closeCaptureHub()
                    self?.model.openScreenRecordingSettings()
                },
                onRevealFolder: { [weak self] in
                    self?.closeCaptureHub()
                    self?.model.revealCaptureFolder()
                },
                onQuit: { [weak self] in
                    self?.closeCaptureHub()
                    NSApp.terminate(nil)
                }
            )
        )
        capturePopover = popover
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closeCaptureHub() {
        capturePopover?.performClose(nil)
        capturePopover = nil
    }
}
