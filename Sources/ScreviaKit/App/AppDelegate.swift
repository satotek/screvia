import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        super.init()
    }

    private let settings = ScreviaSettings()
    private lazy var captureCoordinator = CaptureCoordinator(settings: settings)
    private let windowsCoordinator = WindowsCoordinator()
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

        captureCoordinator.start()

        if !ScreenRecordingPermission.isGranted {
            ScreenRecordingPermission.request()
            windowsCoordinator.openPermissionOnboarding()
        }
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
        captureCoordinator.stop()
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
                displays: captureCoordinator.displayInfos(),
                history: captureCoordinator.captureHistory,
                onCaptureFullScreen: { [weak self] displayID in
                    self?.closeCaptureHub {
                        self?.captureCoordinator.captureFullScreen(displayID: displayID)
                    }
                },
                onCaptureArea: { [weak self] in
                    self?.closeCaptureHub {
                        self?.captureCoordinator.captureArea()
                    }
                },
                onCaptureWindow: { [weak self] in
                    self?.closeCaptureHub {
                        self?.captureCoordinator.captureWindow()
                    }
                },
                onCaptureScroll: { [weak self] in
                    self?.closeCaptureHub {
                        self?.captureCoordinator.captureScroll()
                    }
                },
                onEditHistory: { [weak self] entry in
                    self?.closeCaptureHub()
                    self?.captureCoordinator.editHistoryEntry(entry)
                },
                onCopyHistory: { [weak self] entry in
                    self?.closeCaptureHub()
                    self?.captureCoordinator.copyHistoryEntry(entry)
                },
                onPinHistory: { [weak self] entry in
                    self?.closeCaptureHub()
                    self?.captureCoordinator.pinHistoryEntry(entry)
                },
                onRemoveHistory: { [weak self] entry in
                    self?.closeCaptureHub()
                    self?.captureCoordinator.removeHistoryEntry(entry)
                },
                onOpenPreferences: { [weak self] in
                    self?.closeCaptureHub()
                    guard let self else { return }
                    self.windowsCoordinator.openPreferences(settings: self.settings)
                },
                onOpenAbout: { [weak self] in
                    self?.closeCaptureHub()
                    self?.windowsCoordinator.openAbout()
                },
                onOpenLicenses: { [weak self] in
                    self?.closeCaptureHub()
                    self?.windowsCoordinator.openLicenses()
                },
                // The guide rather than System Settings directly: it also
                // offers the restart that a new grant needs.
                onOpenScreenRecordingSettings: { [weak self] in
                    self?.closeCaptureHub()
                    self?.windowsCoordinator.openPermissionOnboarding()
                },
                onRevealFolder: { [weak self] in
                    self?.closeCaptureHub()
                    guard let self else { return }
                    do {
                        try SystemSettingsService.revealFolder(at: self.settings.saveDirectoryURL)
                    } catch {
                        ErrorPresenter.present(error)
                    }
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

    /// Closes the hub, then starts `capture` once the hub is off screen.
    ///
    /// Capturing straight after `performClose` caught the popover mid-fade
    /// in the screenshot. Closing without the animation removes the window
    /// at once, but the window server only drops it from the screen on its
    /// next frame, so the capture waits a little longer than one frame.
    private func closeCaptureHub(beforeCapture capture: @escaping () -> Void) {
        guard let popover = capturePopover, popover.isShown else {
            capture()
            return
        }

        popover.animates = false
        popover.close()
        capturePopover = nil
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            capture()
        }
    }

    private func closeCaptureHub() {
        capturePopover?.performClose(nil)
        capturePopover = nil
    }
}
