import AppKit
import Combine
import Foundation

/// Orchestrates the capture -> process -> save -> present pipeline: taking a
/// screenshot, running it through CaptureProcessingPipeline, updating
/// history, and routing the result to the thumbnail, the editor, or the
/// clipboard depending on what the caller and the user's settings ask for.
final class CaptureCoordinator: ObservableObject {
    private let settings: ScreviaSettings

    private let captureService = CaptureService()
    private let scrollingCaptureService = ScrollingCaptureService()
    private let imageStore = ImageStore()
    private let captureProcessingPipeline = CaptureProcessingPipeline()
    private let shortcutMonitor = GlobalShortcutMonitor()
    private let thumbnailController = FloatingThumbnailController()
    private let pinnedImageController = PinnedImageController()
    private let editorController = AnnotationEditorController()
    private let historyStore = CaptureHistoryStore()

    private let toastController = ToastController()
    private let textCaptureController = TextCaptureWindowController()

    private var areaSelectionController: AreaSelectionController?
    private var windowSelectionController: WindowSelectionController?

    /// The last area chosen, for capturing the same area again. Kept for the
    /// session only: displays and their arrangement can change in between.
    private var lastArea: (selection: CGRect, displayID: UInt32)?

    /// Shows the self-timer's remaining seconds, and nil when it is done.
    var onCountdown: ((Int?) -> Void)?

    @Published private(set) var captureHistory: [CaptureHistoryEntry]

    init(settings: ScreviaSettings) {
        self.settings = settings
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
            case .captureText:
                self.captureText()
            case .captureLastArea:
                self.captureLastArea()
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
            ErrorPresenter.present(CaptureService.CaptureError.noScreenAvailable)
            return
        }

        afterDelay { [weak self] in
            guard let self else {
                return
            }
            do {
                let image = try self.captureService.captureMainDisplay(on: screen)
                self.finishCapture(image, on: screen)
            } catch {
                ErrorPresenter.present(error)
            }
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
            self.rememberArea(selection, on: screen)
            self.afterDelay { [weak self] in
                self?.captureArea(selection, on: screen)
            }
        }
    }

    private func captureArea(_ selection: CGRect, on screen: NSScreen) {
        do {
            let image = try captureService.capture(selection: selection, on: screen)
            finishCapture(image, on: screen)
        } catch {
            ErrorPresenter.present(error)
        }
    }

    private func rememberArea(_ selection: CGRect, on screen: NSScreen) {
        if let displayID = ScreenUtilities.displayID(for: screen) {
            lastArea = (selection, displayID)
        }
    }

    func captureLastArea() {
        guard
            let lastArea,
            let screen = ScreenUtilities.screen(for: lastArea.displayID)
        else {
            ErrorPresenter.present(CaptureService.CaptureError.noPreviousArea)
            return
        }
        afterDelay { [weak self] in
            self?.captureArea(lastArea.selection, on: screen)
        }
    }

    /// Captures an area and opens it in a window that shows its text, to
    /// copy all of it or, with Live Text, just a part.
    func captureText() {
        let controller = AreaSelectionController()
        areaSelectionController = controller
        controller.start { [weak self] selection, screen in
            guard let self else {
                return
            }
            self.areaSelectionController = nil
            self.rememberArea(selection, on: screen)

            do {
                let image = try self.captureService.capture(selection: selection, on: screen)
                self.showText(in: image)
            } catch {
                ErrorPresenter.present(error)
            }
        }
    }

    private func showText(in image: NSImage) {
        textCaptureController.show(image: image) { [weak self] text in
            self?.copyToClipboard(text: text)
        }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            textCaptureController.update(text: nil)
            return
        }
        Task { [weak self] in
            let text = try? await TextRecognizer.text(in: cgImage)
            self?.textCaptureController.update(text: text)
        }
    }

    private func copyToClipboard(text: String) {
        imageStore.copyToClipboard(text: text)
        toastController.show(L10n.format("toast.textCopied", text.count), symbol: "text.viewfinder")
    }

    /// Recognizes the text in `image` and puts it on the clipboard.
    func copyText(in image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            ErrorPresenter.present(TextRecognizer.RecognitionError.noText)
            return
        }
        Task { [weak self] in
            do {
                let text = try await TextRecognizer.text(in: cgImage)
                guard let self else {
                    return
                }
                self.copyToClipboard(text: text)
            } catch {
                ErrorPresenter.present(error)
            }
        }
    }

    /// Runs `capture` after the self-timer, counting down in the menu bar.
    /// The countdown is cleared a frame before the capture so it is not in
    /// the shot.
    private func afterDelay(_ capture: @escaping () -> Void) {
        let delay = settings.captureDelay
        guard delay > 0 else {
            capture()
            return
        }
        Task { [weak self] in
            for remaining in stride(from: delay, to: 0, by: -1) {
                self?.onCountdown?(remaining)
                try? await Task.sleep(for: .seconds(1))
            }
            self?.onCountdown?(nil)
            try? await Task.sleep(for: .milliseconds(100))
            capture()
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

            self.afterDelay { [weak self] in
                self?.captureSelectedWindow(selectedWindow, on: screen)
            }
        }
    }

    private func captureSelectedWindow(_ selectedWindow: CapturableWindow, on screen: NSScreen) {
        Task { [weak self] in
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
                ErrorPresenter.present(error)
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

            Task { [weak self] in
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
                    ErrorPresenter.present(error)
                }
            }
        }
    }

    func editHistoryEntry(_ entry: CaptureHistoryEntry) {
        Task { [weak self] in
            guard let self, let capture = await self.capture(from: entry) else {
                return
            }
            // Saved PNGs carry no DPI, so they load at one point per pixel.
            let image = ImageImport.normalized(capture.image, scale: Self.importScale) ?? capture.image
            self.openEditor(
                image: image,
                suggestedName: capture.fileURL.deletingPathExtension().lastPathComponent,
                displayID: capture.displayID,
                kind: capture.kind
            )
        }
    }

    // MARK: - Editing other images

    /// Imported images are sized as if captured on the main screen; see
    /// `ImageImport.normalized`.
    private static var importScale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }

    private static var displayUnderPointer: UInt32 {
        ScreenUtilities.screenAtMouse().flatMap(ScreenUtilities.displayID(for:)) ?? 0
    }

    func editClipboardImage() {
        do {
            let image = try ImageImport.image(from: .general, scale: Self.importScale)
            openEditor(
                image: image,
                suggestedName: L10n.text("import.clipboardName"),
                displayID: Self.displayUnderPointer,
                kind: .standard
            )
        } catch {
            ErrorPresenter.present(error)
        }
    }

    func chooseImageToEdit() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageImport.contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L10n.text("import.openMessage")
        // A menu bar app is not frontmost by default; without this the panel
        // opens behind the window the user was in.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        editImage(at: url)
    }

    /// Saving writes a new file to the capture folder; `url` is never
    /// overwritten unless the user picks it in Save As.
    func editImage(at url: URL) {
        let scale = Self.importScale
        let displayID = Self.displayUnderPointer
        Task { [weak self] in
            do {
                guard let data = await Self.readData(at: url) else {
                    throw ImageImport.ImportError.unreadable
                }
                let image = try ImageImport.image(from: data, scale: scale)
                self?.openEditor(
                    image: image,
                    suggestedName: url.deletingPathExtension().lastPathComponent,
                    displayID: displayID,
                    kind: .standard
                )
            } catch {
                ErrorPresenter.present(error)
            }
        }
    }

    func copyHistoryEntry(_ entry: CaptureHistoryEntry) {
        let fileURL = entry.fileURL
        let imageStore = self.imageStore
        Task { [weak self] in
            let imageData = await imageStore.loadImageData(at: fileURL)

            guard let self, let imageData else {
                return
            }
            self.imageStore.copyToClipboard(data: imageData.data, format: imageData.format)
        }
    }

    func pinHistoryEntry(_ entry: CaptureHistoryEntry) {
        Task { [weak self] in
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

        Task { [weak self] in
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
                ErrorPresenter.present(error)
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
        guard
            let data = await Self.readData(at: entry.fileURL),
            let image = NSImage(data: data)
        else {
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

    @concurrent
    private nonisolated static func readData(at fileURL: URL) async -> Data? {
        try? Data(contentsOf: fileURL)
    }

    private func openEditor(for capture: CaptureItem) {
        openEditor(
            image: capture.image,
            suggestedName: capture.fileURL.deletingPathExtension().lastPathComponent,
            displayID: capture.displayID,
            kind: capture.kind
        )
    }

    private func openEditor(image: NSImage, suggestedName: String, displayID: UInt32, kind: CaptureKind) {
        editorController.show(
            image: image,
            suggestedName: suggestedName,
            style: settings.annotationStyle,
            onStyleChange: { [weak self] style in
                self?.settings.annotationStyle = style
            },
            onSave: { [weak self] annotatedImage in
                guard let self else {
                    return
                }

                let saveDirectory = self.settings.saveDirectoryURL
                let format = self.settings.imageFormat
                let jpegQuality = self.settings.jpegQuality
                let copyToClipboard = self.settings.copyToClipboard
                let showThumbnail = self.settings.showThumbnail
                let pipeline = self.captureProcessingPipeline

                Task { [weak self] in
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
                        ErrorPresenter.present(error)
                    }
                }
            },
            onSaveAs: { [weak self] annotatedImage, url in
                guard let self else {
                    return
                }
                do {
                    try self.imageStore.write(annotatedImage, to: url, jpegQuality: self.settings.jpegQuality)
                } catch {
                    ErrorPresenter.present(error)
                }
            },
            onCopy: { [weak self] annotatedImage in
                self?.imageStore.copyToClipboard(annotatedImage)
            },
            onCopyText: { [weak self] annotatedImage in
                self?.copyText(in: annotatedImage)
            }
        )
    }
}
