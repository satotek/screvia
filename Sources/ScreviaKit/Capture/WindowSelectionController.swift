import AppKit
import CoreGraphics

struct CapturableWindow {
    let id: CGWindowID
    let processID: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect

    func frame(on screen: NSScreen) -> CGRect? {
        guard let displayID = ScreenUtilities.displayID(for: screen) else {
            return nil
        }

        let displayBounds = CGDisplayBounds(displayID)
        guard let intersection = bounds.intersectionIfNonEmpty(with: displayBounds) else {
            return nil
        }

        return CGRect(
            x: intersection.minX - displayBounds.minX,
            y: displayBounds.maxY - intersection.maxY,
            width: intersection.width,
            height: intersection.height
        )
    }
}

enum WindowCatalog {
    static func window(at quartzPoint: CGPoint) -> CapturableWindow? {
        guard let windowInfos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let appName = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String

        for info in windowInfos {
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            guard ownerName != appName, ownerName != "Screvia" else {
                continue
            }

            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            guard layer == 0, alpha > 0.01, isOnScreen else {
                continue
            }

            guard let windowNumber = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let ownerProcessID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary
            else {
                continue
            }

            guard
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                bounds.width > 20,
                bounds.height > 20,
                bounds.contains(quartzPoint)
            else {
                continue
            }

            return CapturableWindow(
                id: CGWindowID(windowNumber),
                processID: pid_t(ownerProcessID),
                ownerName: ownerName,
                title: info[kCGWindowName as String] as? String ?? "",
                bounds: bounds
            )
        }

        return nil
    }
}

final class WindowSelectionController {
    private var entries: [(window: SelectionWindow, screen: NSScreen)] = []
    private var completion: ((CapturableWindow, NSScreen) -> Void)?
    private var highlightedWindow: CapturableWindow?

    func start(
        hint: String = L10n.text("selection.windowHint"),
        completion: @escaping (CapturableWindow, NSScreen) -> Void
    ) {
        guard !NSScreen.screens.isEmpty else {
            return
        }

        self.completion = completion
        entries = NSScreen.screens.map { screen in
            let selectionView = WindowSelectionView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                hint: hint
            )
            selectionView.onMouseMoved = { [weak self] in
                self?.updateHighlight()
            }
            selectionView.onMouseDown = { [weak self] in
                self?.selectHighlightedWindow(on: screen)
            }
            selectionView.onCancel = { [weak self] in
                self?.cancel()
            }

            let window = SelectionWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = selectionView
            window.isReleasedWhenClosed = false
            return (window, screen)
        }

        NSApp.activate(ignoringOtherApps: true)
        entries.forEach { $0.window.orderFrontRegardless() }
        if let activeWindow = entries.first(where: { $0.window.frame.contains(NSEvent.mouseLocation) })?.window
            ?? entries.first?.window {
            activeWindow.makeKeyAndOrderFront(nil)
            activeWindow.makeFirstResponder(activeWindow.contentView)
        }
        updateHighlight()
    }

    func cancel() {
        entries.forEach { $0.window.orderOut(nil) }
        entries = []
        completion = nil
        highlightedWindow = nil
    }

    private func updateHighlight() {
        let quartzPoint = CGEvent(source: nil)?.location ?? .zero
        highlightedWindow = WindowCatalog.window(at: quartzPoint)

        for entry in entries {
            guard let selectionView = entry.window.contentView as? WindowSelectionView else {
                continue
            }

            selectionView.highlightedFrame = highlightedWindow?.frame(on: entry.screen)
            selectionView.highlightedTitle = highlightedWindow.map {
                $0.title.isEmpty ? $0.ownerName : "\($0.ownerName)  ·  \($0.title)"
            }
            selectionView.needsDisplay = true
        }
    }

    private func selectHighlightedWindow(on screen: NSScreen) {
        updateHighlight()
        guard let highlightedWindow, let completion else {
            return
        }

        entries.forEach { $0.window.orderOut(nil) }
        entries = []
        self.completion = nil
        self.highlightedWindow = nil

        completion(highlightedWindow, ScreenUtilities.screenAtMouse() ?? screen)
    }
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class WindowSelectionView: NSView {
    let hint: String
    var onMouseMoved: (() -> Void)?
    var onMouseDown: (() -> Void)?
    var onCancel: (() -> Void)?
    var highlightedFrame: CGRect?
    var highlightedTitle: String?

    init(frame frameRect: NSRect, hint: String) {
        self.hint = hint
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        self.hint = L10n.text("selection.windowHint")
        super.init(coder: coder)
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        super.updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        if let highlightedFrame {
            NSColor.systemBlue.withAlphaComponent(0.18).setFill()
            highlightedFrame.fill()

            NSColor.systemBlue.withAlphaComponent(0.95).setStroke()
            let border = NSBezierPath(rect: highlightedFrame)
            border.lineWidth = 2
            border.stroke()

            if let highlightedTitle {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: NSColor.white
                ]
                highlightedTitle.draw(
                    at: CGPoint(x: highlightedFrame.minX + 8, y: highlightedFrame.maxY + 8),
                    withAttributes: attributes
                )
            }
        }

        hint.draw(
            at: CGPoint(x: 18, y: bounds.maxY - 30),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92)
            ]
        )
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?()
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}

private extension CGRect {
    func intersectionIfNonEmpty(with other: CGRect) -> CGRect? {
        let intersection = intersection(other)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return nil
        }
        return intersection
    }
}
