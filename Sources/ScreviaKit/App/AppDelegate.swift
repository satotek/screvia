import AppKit
import SwiftUI
import UniformTypeIdentifiers

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        // AppKit's own tooltips, sooner than the system's delay of over a
        // second: the editor's icon-only tools depend on them to say what
        // they do. A registered default, so a value set with `defaults`
        // still wins.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 500])
        super.init()
    }

    private let settings = ScreviaSettings()
    private lazy var captureCoordinator = CaptureCoordinator(settings: settings)
    private let windowsCoordinator = WindowsCoordinator()
    private var statusItem: NSStatusItem?
    private var capturePopover: NSPopover?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = makeMainMenu()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarImage()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleCaptureHub)
        // Dropping an image on the icon opens it in the editor. The button
        // itself cannot be a drop target, so its window is, with this
        // delegate receiving the drag; see the NSDraggingDestination below.
        statusItem.button?.window?.registerForDraggedTypes([.fileURL])
        statusItem.button?.window?.delegate = self
        self.statusItem = statusItem

        captureCoordinator.onCountdown = { [weak self] remaining in
            self?.showCountdown(remaining)
        }
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

    /// Finder's Open With, and files dropped on the app in the Finder.
    public func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: Self.isImage) else {
            return
        }
        captureCoordinator.editImage(at: url)
    }

    /// A click on the Dock icon, there while the editor is open, brings the
    /// editor forward.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        return false
    }

    /// Shown only while the app is a regular one, when the editor is open.
    /// Just the app menu: an Edit menu's ⌘Z and ⌘C would take those keys from
    /// the editor's own undo and copy.
    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.text("about.menuTitle"), action: #selector(openAbout), keyEquivalent: "")
            .target = self
        appMenu.addItem(withTitle: L10n.text("app.settings"), action: #selector(openPreferences), keyEquivalent: ",")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.text("app.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.text("app.quitScrevia"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        return mainMenu
    }

    @objc private func openAbout() {
        windowsCoordinator.openAbout()
    }

    @objc private func openPreferences() {
        windowsCoordinator.openPreferences(settings: settings)
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
                onCaptureText: { [weak self] in
                    self?.closeCaptureHub {
                        self?.captureCoordinator.captureText()
                    }
                },
                onCaptureLastArea: { [weak self] in
                    self?.closeCaptureHub {
                        self?.captureCoordinator.captureLastArea()
                    }
                },
                captureDelay: settings.captureDelay,
                onCaptureDelayChange: { [weak self] seconds in
                    self?.settings.captureDelay = seconds
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
                onOpenImage: { [weak self] in
                    self?.closeCaptureHub()
                    self?.captureCoordinator.chooseImageToEdit()
                },
                onEditClipboard: { [weak self] in
                    self?.closeCaptureHub()
                    self?.captureCoordinator.editClipboardImage()
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

    /// The self-timer's remaining seconds beside the menu bar icon, the one
    /// place that is on screen whatever the user is setting up.
    private func showCountdown(_ remaining: Int?) {
        guard let statusItem, let button = statusItem.button else {
            return
        }
        if let remaining {
            statusItem.length = NSStatusItem.variableLength
            button.title = " \(remaining)"
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
            statusItem.length = NSStatusItem.squareLength
        }
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

// MARK: - Dropping images on the menu bar icon

extension AppDelegate: NSWindowDelegate {
    private static func isImage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?
            .conforms(to: .image) == true
    }

    private static func droppedImage(_ sender: NSDraggingInfo) -> URL? {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return urls?.first(where: isImage)
    }

    @objc func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.droppedImage(sender) == nil ? [] : .copy
    }

    @objc func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = Self.droppedImage(sender) else {
            return false
        }
        closeCaptureHub()
        captureCoordinator.editImage(at: url)
        return true
    }
}
