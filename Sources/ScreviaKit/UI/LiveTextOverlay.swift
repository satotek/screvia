import AppKit
import SwiftUI
import VisionKit

/// Apple's Live Text over an image: drag across text to select it, ⌘C or
/// the context menu to copy, as in Preview and Photos. Analysis runs on
/// this Mac, like the rest of Screvia's text recognition.
///
/// Give it the frame the image is drawn in; the overlay maps its whole
/// bounds onto the image.
struct LiveTextOverlay: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> ImageAnalysisOverlayView {
        let view = ImageAnalysisOverlayView()
        // Text and data detectors such as links, without subject lifting,
        // which has nothing to do with copying text.
        view.preferredInteractionTypes = .automaticTextOnly
        context.coordinator.analyze(image, into: view)
        return view
    }

    func updateNSView(_ view: ImageAnalysisOverlayView, context: Context) {
        if context.coordinator.image !== image {
            context.coordinator.analyze(image, into: view)
        }
    }

    static func dismantleNSView(_ view: ImageAnalysisOverlayView, coordinator: Coordinator) {
        coordinator.task?.cancel()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private static let analyzer = ImageAnalyzer()

        private(set) var image: NSImage?
        var task: Task<Void, Never>?

        func analyze(_ image: NSImage, into view: ImageAnalysisOverlayView) {
            self.image = image
            task?.cancel()
            guard
                ImageAnalyzer.isSupported,
                let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else {
                return
            }

            task = Task { [weak view] in
                do {
                    let analysis = try await Self.analyzer.analyze(
                        cgImage,
                        orientation: .up,
                        configuration: ImageAnalyzer.Configuration([.text, .machineReadableCode])
                    )
                    guard !Task.isCancelled else {
                        return
                    }
                    view?.analysis = analysis
                } catch {
                    Log.ui.error("Live Text analysis failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
