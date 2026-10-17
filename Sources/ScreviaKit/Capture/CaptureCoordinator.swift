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
    private let editArchive = EditArchive(directory: EditArchive.standardDirectory)

    private let toastController = ToastController()
    private let textCaptureController = TextCaptureWindowController()
    private let desktopCover = DesktopCover()

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
        // History does not outlive a launch, so neither do unsaved captures.
        try? FileManager.default.removeItem(at: Self.unsavedDirectory)
        let editArchive = editArchive
        Task {
            await editArchive.pruneInBackground()
        }
    }

    /// Where captures go when "Save to file" is off: out of the user's
    /// folders, but on disk so history, the thumbnail and dragging work.
    static var unsavedDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "dev.satotek.screvia/Unsaved", directoryHint: .isDirectory)
    }

    /// The app a capture came from, for `{app}` in file names. Screvia itself
    /// is frontmost when a capture starts from the hub, which says nothing.
    private static func sourceAppName(processID: pid_t? = nil) -> String? {
        let app = processID.flatMap(NSRunningApplication.init(processIdentifier:))
            ?? NSWorkspace.shared.frontmostApplication
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }
        return app.localizedName
    }

    private func cursorSnapshot(on screen: NSScreen) -> CursorSnapshot? {
        settings.includeCursor ? CursorSnapshot.current(on: screen) : nil
    }

    /// Runs a display capture with the desktop icons covered when the user
    /// asks for it. The cover needs a frame on screen before the capture.
    private func withDesktopHidden(_ capture: @escaping () -> Void) {
        guard settings.hideDesktopIcons else {
            capture()
            return
        }
        desktopCover.show()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            capture()
            self?.desktopCover.hide()
        }
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

        let app = Self.sourceAppName()
        afterDelay { [weak self] in
            self?.withDesktopHidden { [weak self] in
                guard let self else {
                    return
                }
                do {
                    let image = try self.captureService.captureMainDisplay(
                        on: screen,
                        cursor: self.cursorSnapshot(on: screen)
                    )
                    self.finishCapture(image, on: screen, app: app)
                } catch {
                    ErrorPresenter.present(error)
                }
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
        let app = Self.sourceAppName()
        withDesktopHidden { [weak self] in
            guard let self else {
                return
            }
            do {
                let image = try self.captureService.capture(
                    selection: selection,
                    on: screen,
                    cursor: self.cursorSnapshot(on: screen)
                )
                self.finishCapture(image, on: screen, app: app)
            } catch {
                ErrorPresenter.present(error)
            }
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
        let language = settings.textLanguage
        let joinLines = settings.textJoinLines
        Task { [weak self] in
            let text = try? await TextRecognizer.text(
                in: cgImage,
                language: language,
                joinLines: joinLines
            )
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
        let language = settings.textLanguage
        let joinLines = settings.textJoinLines
        Task { [weak self] in
            do {
                let text = try await TextRecognizer.text(in: cgImage, language: language, joinLines: joinLines)
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
                    includeShadow: self.settings.includeWindowShadow,
                    includeCursor: self.settings.includeCursor
                )
                self.finishCapture(image, on: screen, app: Self.sourceAppName(processID: selectedWindow.processID))
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
                    self.finishCapture(
                        image,
                        on: screen,
                        kind: .scrolling,
                        app: Self.sourceAppName(processID: selectedWindow.processID)
                    )
                } catch {
                    ErrorPresenter.present(error)
                }
            }
        }
    }

    func editHistoryEntry(_ entry: CaptureHistoryEntry) {
        Task { [weak self] in
            guard let self else {
                return
            }
            if await self.reopenEdit(of: entry.fileURL, displayID: entry.displayID, kind: entry.kind) {
                return
            }
            guard let capture = await self.capture(from: entry) else {
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
    /// overwritten unless the user picks it in Save As, or it is an image
    /// the editor saved, which opens with its annotations to change.
    func editImage(at url: URL) {
        let scale = Self.importScale
        let displayID = Self.displayUnderPointer
        Task { [weak self] in
            if await self?.reopenEdit(of: url, displayID: displayID, kind: .standard) == true {
                return
            }
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
        kind: CaptureKind = .standard,
        app: String? = nil
    ) {
        let displayID = ScreenUtilities.displayID(for: screen) ?? 0
        let styleOptions = settings.styleOptions
        let saveDirectory = saveDirectory
        let baseName = settings.nextFileName(app: app)
        let downscale = settings.downscaleRetina
        let format = settings.imageFormat
        let jpegQuality = settings.jpegQuality
        let copyToClipboard = copiesToClipboard
        let showThumbnail = settings.showThumbnail
        let openEditor = settings.openEditorAfterCapture
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
                    includeClipboardData: copyToClipboard,
                    baseName: baseName,
                    downscaleToPointSize: downscale
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

                let capture = CaptureItem(
                    image: result.image,
                    fileURL: result.savedImage.fileURL,
                    displayID: displayID,
                    kind: kind
                )
                self.publishCapture(capture, showThumbnail: showThumbnail && !openEditor)
                if openEditor {
                    self.openEditor(for: capture)
                }
            } catch {
                ErrorPresenter.present(error)
            }
        }
    }

    /// The save folder, or the scratch folder when saving is off.
    private var saveDirectory: URL {
        settings.saveToFile ? settings.saveDirectoryURL : Self.unsavedDirectory
    }

    /// With saving off the clipboard is the only place a capture lands, so
    /// it always gets a copy.
    private var copiesToClipboard: Bool {
        settings.copyToClipboard || !settings.saveToFile
    }

    private func publishCapture(_ capture: CaptureItem, showThumbnail: Bool) {
        historyStore.limit = settings.historyLimit
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
        Task { [weak self] in
            guard let self else {
                return
            }
            if await self.reopenEdit(of: capture.fileURL, displayID: capture.displayID, kind: capture.kind) {
                return
            }
            self.openEditor(
                image: capture.image,
                suggestedName: capture.fileURL.deletingPathExtension().lastPathComponent,
                displayID: capture.displayID,
                kind: capture.kind
            )
        }
    }

    /// Opens the edit that saved `fileURL`, with its annotations still
    /// editable. False when the editor did not save the file, or another
    /// app changed it since.
    private func reopenEdit(of fileURL: URL, displayID: UInt32, kind: CaptureKind) async -> Bool {
        guard
            let edit = await editArchive.loadEdit(for: fileURL),
            let original = edit.original
        else {
            return false
        }
        openEditor(
            image: original,
            document: edit.document,
            replacing: fileURL,
            suggestedName: fileURL.deletingPathExtension().lastPathComponent,
            displayID: displayID,
            kind: kind
        )
        return true
    }

    /// Keeps what it takes to reopen the edit that saved `fileURL`. Failing
    /// costs only that, so it is logged rather than shown: the image itself
    /// is saved.
    private func archiveEdit(original: NSImage, document: AnnotationDocument, for fileURL: URL) {
        let editArchive = editArchive
        Task {
            do {
                try await editArchive.storeInBackground(original: original, document: document, for: fileURL)
            } catch {
                Log.storage.error("Could not keep the edit for reopening: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// `replacing` is the file a reopened edit saves over; otherwise saving
    /// writes a new file.
    private func openEditor(
        image: NSImage,
        document: AnnotationDocument = AnnotationDocument(),
        replacing: URL? = nil,
        suggestedName: String,
        displayID: UInt32,
        kind: CaptureKind
    ) {
        editorController.show(
            image: image,
            document: document,
            replacing: replacing,
            suggestedName: suggestedName,
            style: settings.annotationStyle,
            colorFormat: settings.colorCodeFormat,
            onStyleChange: { [weak self] style in
                self?.settings.annotationStyle = style
            },
            onColorFormatChange: { [weak self] format in
                self?.settings.colorCodeFormat = format
            },
            onSave: { [weak self] annotatedImage, document in
                guard let self else {
                    return
                }
                if let replacing {
                    self.saveEdit(
                        annotatedImage,
                        over: replacing,
                        original: image,
                        document: document,
                        displayID: displayID,
                        kind: kind
                    )
                    return
                }

                let saveDirectory = self.saveDirectory
                let baseName = self.settings.nextFileName(app: nil)
                let format = self.settings.imageFormat
                let jpegQuality = self.settings.jpegQuality
                let copyToClipboard = self.copiesToClipboard
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
                            includeClipboardData: copyToClipboard,
                            baseName: baseName
                        )

                        guard let self else {
                            return
                        }

                        self.archiveEdit(original: image, document: document, for: result.savedImage.fileURL)
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
            onSaveAs: { [weak self] annotatedImage, document, url in
                guard let self else {
                    return
                }
                let jpegQuality = self.settings.jpegQuality
                let pipeline = self.captureProcessingPipeline
                Task { [weak self] in
                    do {
                        try await pipeline.write(annotatedImage, to: url, jpegQuality: jpegQuality)
                        self?.archiveEdit(original: image, document: document, for: url)
                    } catch {
                        ErrorPresenter.present(error)
                    }
                }
            },
            onCopy: { [weak self] annotatedImage in
                self?.imageStore.copyToClipboard(annotatedImage)
            },
            onCopyText: { [weak self] annotatedImage in
                self?.copyText(in: annotatedImage)
            },
            onCopyColor: { [weak self] hex in
                self?.imageStore.copyToClipboard(text: hex)
                self?.toastController.show(L10n.format("toast.colorCopied", hex), symbol: "eyedropper")
            }
        )
    }

    /// Saves a reopened edit over its own file, which keeps its name and
    /// format and moves to the front of the history.
    private func saveEdit(
        _ annotatedImage: NSImage,
        over fileURL: URL,
        original: NSImage,
        document: AnnotationDocument,
        displayID: UInt32,
        kind: CaptureKind
    ) {
        let jpegQuality = settings.jpegQuality
        let copyToClipboard = copiesToClipboard
        let showThumbnail = settings.showThumbnail
        let pipeline = captureProcessingPipeline

        Task { [weak self] in
            do {
                try await pipeline.write(annotatedImage, to: fileURL, jpegQuality: jpegQuality)
                guard let self else {
                    return
                }

                self.archiveEdit(original: original, document: document, for: fileURL)
                if copyToClipboard {
                    self.imageStore.copyToClipboard(annotatedImage)
                }
                self.publishCapture(
                    CaptureItem(image: annotatedImage, fileURL: fileURL, displayID: displayID, kind: kind),
                    showThumbnail: showThumbnail
                )
            } catch {
                ErrorPresenter.present(error)
            }
        }
    }
}
