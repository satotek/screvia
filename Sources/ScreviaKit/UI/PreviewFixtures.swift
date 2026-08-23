#if DEBUG
import AppKit
import SwiftUI

/// Sample data used exclusively by `#Preview` blocks.
///
/// Everything here is `#if DEBUG` so it never reaches a release build. The
/// views in this module take plain values and closures rather than reaching
/// for singletons, which is what makes previewing them possible at all — the
/// only thing missing was something to hand them.
enum PreviewFixtures {
    /// A stand-in screenshot. Drawing one beats shipping a PNG: it keeps the
    /// package free of binary assets and renders instantly in the canvas.
    static func sampleImage(
        size: NSSize = NSSize(width: 1280, height: 800)
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGradient(
            starting: NSColor(srgbRed: 0.15, green: 0.19, blue: 0.31, alpha: 1),
            ending: NSColor(srgbRed: 0.06, green: 0.07, blue: 0.11, alpha: 1)
        )?.draw(in: NSRect(origin: .zero, size: size), angle: 290)

        // A few window-ish rectangles so the image reads as a desktop capture
        // instead of a flat swatch.
        let cards: [(NSRect, CGFloat)] = [
            (NSRect(x: size.width * 0.08, y: size.height * 0.22, width: size.width * 0.44, height: size.height * 0.52), 0.16),
            (NSRect(x: size.width * 0.40, y: size.height * 0.12, width: size.width * 0.48, height: size.height * 0.46), 0.24)
        ]

        for (rect, alpha) in cards {
            let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
            NSColor.white.withAlphaComponent(alpha).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.28).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        return image
    }

    static var displays: [DisplayInfo] {
        [
            DisplayInfo(
                id: 1,
                name: "Built-in Retina Display",
                localizedName: "Built-in Retina Display",
                frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                isMain: true
            ),
            DisplayInfo(
                id: 2,
                name: "Studio Display",
                localizedName: "Studio Display",
                frame: CGRect(x: 1728, y: 0, width: 2560, height: 1440),
                isMain: false
            )
        ]
    }

    static var capture: CaptureItem {
        CaptureItem(
            image: sampleImage(size: NSSize(width: 960, height: 600)),
            fileURL: URL(fileURLWithPath: "/tmp/Screvia/Screvia-2026-08-23-22-05-11.png"),
            displayID: 1
        )
    }

    static var history: [CaptureHistoryEntry] {
        [
            CaptureHistoryEntry(
                fileURL: capture.fileURL,
                displayID: capture.displayID,
                capturedAt: Date()
            )
        ]
    }
}

extension ScreviaSettings {
    /// Settings backed by a throwaway `UserDefaults` suite.
    ///
    /// `ScreviaSettings` persists on every `didSet`, so a preview driving the
    /// sliders would otherwise rewrite the real app's preferences. The suite is
    /// wiped on creation so each canvas session starts from the defaults.
    static func previewInstance() -> ScreviaSettings {
        let suiteName = "com.screvia.previews"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        return ScreviaSettings(defaults: defaults)
    }
}
#endif
