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

    private var areaSelectionController: AreaSelectionController?
    private var windowSelectionController: WindowSelectionController?

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

        do {
            let image = try captureService.captureMainDisplay(on: screen)
            finishCapture(image, on: screen)
        } catch {
            ErrorPresenter.present(error)
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
                ErrorPresenter.present(error)
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
            self.openEditor(for: capture)
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
        editorController.show(
            capture: capture,
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
                let displayID = capture.displayID
                let kind = capture.kind
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
            }
        )
    }
}
