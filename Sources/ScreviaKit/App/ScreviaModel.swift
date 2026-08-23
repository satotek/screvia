import AppKit
import Combine
import CoreGraphics
import Foundation

struct CaptureItem {
    let image: NSImage
    let fileURL: URL
    let displayID: UInt32
    let kind: CaptureKind

    init(
        image: NSImage,
        fileURL: URL,
        displayID: UInt32,
        kind: CaptureKind = .standard
    ) {
        self.image = image
        self.fileURL = fileURL
        self.displayID = displayID
        self.kind = kind
    }
}

@MainActor
final class ScreviaModel: ObservableObject {
    let settings = ScreviaSettings()

    private let captureService = CaptureService()
    private let scrollingCaptureService = ScrollingCaptureService()
    private let imageStore = ImageStore()
    private let captureProcessingPipeline = CaptureProcessingPipeline()
    private let shortcutMonitor = GlobalShortcutMonitor()
    private let thumbnailController = FloatingThumbnailController()
    private let pinnedImageController = PinnedImageController()
    private let editorController = AnnotationEditorController()
    private let preferencesController = PreferencesWindowController()
    private let aboutController = AboutWindowController()
    private let licensesController = LicensesWindowController()
    private let historyStore = CaptureHistoryStore()

    private var areaSelectionController: AreaSelectionController?
    private var windowSelectionController: WindowSelectionController?

    @Published private(set) var captureHistory: [CaptureHistoryEntry]

    init() {
        captureHistory = historyStore.entries
    }

    func start() {
        shortcutMonitor.start { [weak self] action in
            guard let self else {
                return
            }

            switch action {
            case .captureFullScreen:
                self.captureFullScreen()
            case .captureArea:
                self.captureArea()
            case .captureWindow:
                self.captureWindow()
            case .captureScroll:
                self.captureScroll()
            }
        }
    }

    func stop() {
        shortcutMonitor.stop()
    }

    func displayInfos() -> [DisplayInfo] {
        ScreenUtilities.displayInfos()
    }

    func captureFullScreen(displayID: UInt32? = nil) {
        guard let screen = displayID.flatMap(ScreenUtilities.screen(for:))
            ?? ScreenUtilities.screenAtMouse()
            ?? NSScreen.screens.first else {
            showError(CaptureService.CaptureError.noScreenAvailable)
            return
        }

        do {
            let image = try captureService.captureMainDisplay(on: screen)
            finishCapture(image, on: screen)
        } catch {
            showError(error)
        }
    }

    func captureArea() {
        let controller = AreaSelectionController()
        areaSelectionController = controller
        controller.start { [weak self] selection, screen in
            guard let self else {
                return
            }

            self.areaSelectionController = nil

            do {
                let image = try self.captureService.capture(selection: selection, on: screen)
                self.finishCapture(image, on: screen)
            } catch {
                self.showError(error)
            }
        }
    }

    func captureWindow() {
        let controller = WindowSelectionController()
        windowSelectionController = controller
        controller.start { [weak self] selectedWindow, screen in
            guard let self else {
                return
            }

            self.windowSelectionController = nil

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                do {
                    let image = try await self.captureService.captureWindow(
                        windowID: selectedWindow.id,
                        includeShadow: self.settings.includeWindowShadow
                    )
                    self.finishCapture(image, on: screen)
                } catch {
                    self.showError(error)
                }
            }
        }
    }

    func captureScroll() {
        let controller = WindowSelectionController()
        windowSelectionController = controller
        controller.start(hint: L10n.text("selection.scrollWindowHint")) { [weak self] selectedWindow, screen in
            guard let self else {
                return
            }

            self.windowSelectionController = nil

            // The selection overlay consumes the click, so explicitly make
            // the selected application active before posting scroll events.
            if let targetApplication = NSRunningApplication(processIdentifier: selectedWindow.processID) {
                // Since macOS 14, activation is cooperative. The status-bar
                // app is active while the selection overlay is shown, so give
                // Safari (or the selected app) an explicit activation yield
                // before asking it to become active.
                NSApp.yieldActivation(to: targetApplication)
                _ = targetApplication.activate(options: [])
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                do {
                    let image = try await self.scrollingCaptureService.capture(
                        windowID: selectedWindow.id,
                        processID: selectedWindow.processID,
                        windowBounds: selectedWindow.bounds
                    )
                    self.finishCapture(image, on: screen, kind: .scrolling)
                } catch {
                    self.showError(error)
                }
            }
        }
    }

    func openPreferences() {
        preferencesController.show(settings: settings)
    }

    func openAbout() {
        aboutController.show()
    }

    func openLicenses() {
        licensesController.show()
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealCaptureFolder() {
        do {
            try FileManager.default.createDirectory(
                at: settings.saveDirectoryURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(settings.saveDirectoryURL)
        } catch {
            showError(error)
        }
    }

    func editHistoryEntry(_ entry: CaptureHistoryEntry) {
        Task { @MainActor [weak self] in
            guard let self, let capture = await self.capture(from: entry) else {
                return
            }
            self.openEditor(for: capture)
        }
    }

    func copyHistoryEntry(_ entry: CaptureHistoryEntry) {
        let fileURL = entry.fileURL
        let imageStore = self.imageStore
        Task { @MainActor [weak self] in
            let imageData = await Task.detached(priority: .utility) {
                imageStore.readImageData(at: fileURL)
            }.value

            guard let self, let imageData else {
                return
            }
            self.imageStore.copyToClipboard(data: imageData.data, format: imageData.format)
        }
    }

    func pinHistoryEntry(_ entry: CaptureHistoryEntry) {
        Task { @MainActor [weak self] in
            guard let self, let capture = await self.capture(from: entry) else {
                return
            }
            self.pinnedImageController.pin(capture.image, displayID: capture.displayID)
        }
    }

    func removeHistoryEntry(_ entry: CaptureHistoryEntry) {
        historyStore.remove(entry)
        captureHistory = historyStore.entries
    }

    private func finishCapture(
        _ image: NSImage,
        on screen: NSScreen,
        kind: CaptureKind = .standard
    ) {
        let displayID = ScreenUtilities.displayID(for: screen) ?? 0
        let styleOptions = settings.styleOptions
        let saveDirectory = settings.saveDirectoryURL
        let format = settings.imageFormat
        let jpegQuality = settings.jpegQuality
        let copyToClipboard = settings.copyToClipboard
        let showThumbnail = settings.showThumbnail
        let playSound = settings.playSound
        let pipeline = captureProcessingPipeline

        Task { @MainActor [weak self] in
            do {
                let result = try await pipeline.processAndSave(
                    image: image,
                    styleOptions: styleOptions,
                    directory: saveDirectory,
                    format: format,
                    jpegQuality: jpegQuality,
                    includeClipboardData: copyToClipboard
                )

                guard let self else {
                    return
                }

                if copyToClipboard {
                    if let data = result.savedImage.data {
                        self.imageStore.copyToClipboard(data: data, format: format)
                    } else {
                        self.imageStore.copyToClipboard(result.image)
                    }
                }
                if playSound {
                    NSSound(named: NSSound.Name("Tink"))?.play()
                }

                self.publishCapture(
                    CaptureItem(
                        image: result.image,
                        fileURL: result.savedImage.fileURL,
                        displayID: displayID,
                        kind: kind
                    ),
                    showThumbnail: showThumbnail
                )
            } catch {
                self?.showError(error)
            }
        }
    }

    private func publishCapture(_ capture: CaptureItem, showThumbnail: Bool) {
        historyStore.record(
            fileURL: capture.fileURL,
            displayID: capture.displayID,
            kind: capture.kind
        )
        captureHistory = historyStore.entries

        guard showThumbnail else {
            return
        }

        thumbnailController.show(
            capture: capture,
            settings: settings,
            onEdit: { [weak self] in
                self?.openEditor(for: capture)
            },
            onPin: { [weak self] in
                self?.pinnedImageController.pin(capture.image, displayID: capture.displayID)
            },
            onCopy: { [weak self] in
                self?.imageStore.copyToClipboard(capture.image)
            }
        )
    }

    private func capture(from entry: CaptureHistoryEntry) async -> CaptureItem? {
        let fileURL = entry.fileURL
        let data = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: fileURL)
        }.value

        guard let data, let image = NSImage(data: data) else {
            removeHistoryEntry(entry)
            return nil
        }

        return CaptureItem(
            image: image,
            fileURL: entry.fileURL,
            displayID: entry.displayID,
            kind: entry.kind
        )
    }

    private func openEditor(for capture: CaptureItem) {
        editorController.show(
            capture: capture,
            onSave: { [weak self] annotatedImage in
                guard let self else {
                    return
                }

                let saveDirectory = self.settings.saveDirectoryURL
                let format = self.settings.imageFormat
                let jpegQuality = self.settings.jpegQuality
                let copyToClipboard = self.settings.copyToClipboard
                let showThumbnail = self.settings.showThumbnail
                let displayID = capture.displayID
                let kind = capture.kind
                let pipeline = self.captureProcessingPipeline

                Task { @MainActor [weak self] in
                    do {
                        let result = try await pipeline.processAndSave(
                            image: annotatedImage,
                            styleOptions: CaptureStyleOptions(
                                backgroundStyle: .none,
                                padding: 0,
                                cornerRadius: 0,
                                shadowEnabled: false
                            ),
                            directory: saveDirectory,
                            format: format,
                            jpegQuality: jpegQuality,
                            includeClipboardData: copyToClipboard
                        )

                        guard let self else {
                            return
                        }

                        if copyToClipboard {
                            if let data = result.savedImage.data {
                                self.imageStore.copyToClipboard(data: data, format: format)
                            } else {
                                self.imageStore.copyToClipboard(result.image)
                            }
                        }

                        self.publishCapture(
                            CaptureItem(
                                image: result.image,
                                fileURL: result.savedImage.fileURL,
                                displayID: displayID,
                                kind: kind
                            ),
                            showThumbnail: showThumbnail
                        )
                    } catch {
                        self?.showError(error)
                    }
                }
            },
            onCopy: { [weak self] annotatedImage in
                self?.imageStore.copyToClipboard(annotatedImage)
            }
        )
    }

    private func showError(_ error: Error) {
        // Every failure path in this file funnels through here, so this single
        // call gives the alert a paper trail. The alert itself is transient;
        // Console.app keeps this.
        Log.app.error(
            """
            Surfaced error: \(String(describing: type(of: error)), privacy: .public) \
            — \(error.localizedDescription, privacy: .public)
            """
        )

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screvia"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.text("app.ok"))

        let captureError = error as? CaptureService.CaptureError
        if captureError?.requiresAccessibilityPermission == true {
            alert.addButton(withTitle: L10n.text("app.openSettings"))
        }

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            openAccessibilitySettings()
        }
    }
}
