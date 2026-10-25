import AppKit

final class AreaSelectionController {
    private var windows: [SelectionWindow] = []
    private var completion: ((CGRect, NSScreen) -> Void)?
    private var onCancel: (() -> Void)?

    /// `hint` is shown at the top of each screen. With
    /// `selectsScreenOnClick`, a click without a drag selects the whole
    /// screen it is on instead of cancelling. A screen with a still in
    /// `stills` shows that still under the overlay instead of what is live
    /// on it, so the selection is made on the screen as it was.
    func start(
        showsLoupe: Bool = true,
        hint: String? = nil,
        selectsScreenOnClick: Bool = false,
        stills: [CGDirectDisplayID: CGImage] = [:],
        onCancel: (() -> Void)? = nil,
        completion: @escaping (CGRect, NSScreen) -> Void
    ) {
        guard !NSScreen.screens.isEmpty else {
            onCancel?()
            return
        }

        self.completion = completion
        self.onCancel = onCancel

        windows = NSScreen.screens.map { screen in
            let selectionView = AreaSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            selectionView.hint = hint
            selectionView.selectsScreenOnClick = selectsScreenOnClick
            let still = ScreenUtilities.displayID(for: screen).flatMap { stills[$0] }
            if let still, showsLoupe {
                selectionView.loupe = SelectionLoupe(screenImage: still, screenSize: screen.frame.size)
            }
            // So the crosshair and loupe show before the pointer first moves.
            let mouse = NSEvent.mouseLocation
            if screen.frame.contains(mouse) {
                selectionView.showPointer(at: CGPoint(x: mouse.x - screen.frame.minX, y: mouse.y - screen.frame.minY))
            }
            selectionView.onSelection = { [weak self] selection in
                self?.finish(selection: selection, on: screen)
            }
            selectionView.onCancel = { [weak self] in
                self?.cancel()
            }

            let selectionWindow = SelectionWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            selectionWindow.backgroundColor = .clear
            selectionWindow.isOpaque = false
            selectionWindow.hasShadow = false
            selectionWindow.level = .screenSaver
            selectionWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            selectionWindow.contentView = still.map { Self.frozenBackground($0, under: selectionView) } ?? selectionView
            selectionWindow.isReleasedWhenClosed = false
            // A panel's default; it would hide the overlay whenever Screvia
            // is not the active app, which is now most of the time.
            selectionWindow.hidesOnDeactivate = false
            return selectionWindow
        }

        // Not activating Screvia leaves the app underneath active, so a
        // menu bar app's popover stays open to be captured; it closes
        // as soon as its app resigns active.
        windows.forEach { $0.orderFrontRegardless() }
        if let activeWindow = windows.first(where: { window in
            window.frame.contains(NSEvent.mouseLocation)
        }) ?? windows.first {
            activeWindow.makeKeyAndOrderFront(nil)
            activeWindow.makeFirstResponder(Self.selectionView(in: activeWindow))
        }
        if showsLoupe {
            loadLoupes()
        }
    }

    /// Gives each screen's overlay a still of that screen for the loupe,
    /// taken without the overlays, which would darken it. It arrives a
    /// moment after the overlay; until then the crosshair shows alone.
    private func loadLoupes() {
        // Without permission, asking now would interrupt the selection.
        guard CGPreflightScreenCaptureAccess() else {
            return
        }
        let overlays = windows.map(\.windowNumber)
        for window in windows {
            guard
                let view = Self.selectionView(in: window),
                view.loupe == nil,
                let screen = window.screen,
                let displayID = ScreenUtilities.displayID(for: screen)
            else {
                continue
            }
            let screenSize = screen.frame.size
            Task {
                guard let image = try? await CaptureService.screenImage(displayID: displayID, excludingWindows: overlays) else {
                    return
                }
                view.loupe = SelectionLoupe(screenImage: image, screenSize: screenSize)
                view.needsDisplay = true
            }
        }
    }

    /// A view showing `still` with `selectionView` over it. The selection
    /// view clears the selected area to show what is under it, here the
    /// still rather than the live screen.
    private static func frozenBackground(_ still: CGImage, under selectionView: AreaSelectionView) -> NSView {
        let background = NSView(frame: selectionView.frame)
        background.wantsLayer = true
        background.layer?.contents = still
        background.layer?.contentsGravity = .resize
        selectionView.autoresizingMask = [.width, .height]
        background.addSubview(selectionView)
        return background
    }

    private static func selectionView(in window: NSWindow) -> AreaSelectionView? {
        window.contentView as? AreaSelectionView
            ?? window.contentView?.subviews.lazy.compactMap { $0 as? AreaSelectionView }.first
    }

    private func finish(selection: CGRect, on screen: NSScreen) {
        guard let completion else {
            cancel()
            return
        }

        windows.forEach { $0.orderOut(nil) }
        windows = []
        self.completion = nil
        onCancel = nil
        completion(selection, screen)
    }

    func cancel() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        completion = nil
        let onCancel = onCancel
        self.onCancel = nil
        onCancel?()
    }
}

private final class SelectionWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class AreaSelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var loupe: SelectionLoupe?
    var hint: String?
    var selectsScreenOnClick = false

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var cursorPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    // Screvia is not active while selecting, and the first click is the
    // selection's first corner.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.42).setFill()
        bounds.fill()
        drawHint()

        guard let selection = selectionRect else {
            drawCrosshair(at: cursorPoint)
            drawLoupe(selectionSize: nil)
            return
        }

        NSColor.clear.setFill()
        NSGraphicsContext.current?.compositingOperation = .clear
        selection.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 1.5
        border.stroke()

        let dimensions = L10n.format(
            "selection.size",
            Int(selection.width.rounded()),
            Int(selection.height.rounded())
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let labelSize = dimensions.size(withAttributes: attributes)
        let labelOrigin = CGPoint(
            x: selection.midX - labelSize.width / 2,
            y: selection.maxY + 10 < bounds.maxY ? selection.maxY + 8 : selection.minY - labelSize.height - 8
        )
        dimensions.draw(at: labelOrigin, withAttributes: attributes)
        drawLoupe(selectionSize: selection.size)
    }

    private func drawHint() {
        guard let hint else {
            return
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]
        let size = hint.size(withAttributes: attributes)
        hint.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 64), withAttributes: attributes)
    }

    private func drawLoupe(selectionSize: CGSize?) {
        guard let loupe, let cursorPoint else {
            return
        }
        loupe.draw(at: cursorPoint, in: bounds, selectionSize: selectionSize)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursorPoint = point
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursorPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursorPoint = point
        currentPoint = point
        guard let selection = selectionRect, selection.width > 2, selection.height > 2 else {
            if selectsScreenOnClick {
                onSelection?(bounds)
            } else {
                onCancel?()
            }
            return
        }
        onSelection?(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    func showPointer(at point: CGPoint) {
        cursorPoint = point
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        cursorPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }

        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private func drawCrosshair(at point: CGPoint?) {
        guard let point else {
            return
        }

        // Faint guides across the whole screen, to line the first corner up
        // with what is on it, then the pointer's own cross.
        let guides = NSBezierPath()
        guides.move(to: CGPoint(x: bounds.minX, y: point.y))
        guides.line(to: CGPoint(x: bounds.maxX, y: point.y))
        guides.move(to: CGPoint(x: point.x, y: bounds.minY))
        guides.line(to: CGPoint(x: point.x, y: bounds.maxY))
        NSColor.white.withAlphaComponent(0.28).setStroke()
        guides.lineWidth = 1
        guides.stroke()

        let path = NSBezierPath()
        path.move(to: CGPoint(x: point.x - 12, y: point.y))
        path.line(to: CGPoint(x: point.x + 12, y: point.y))
        path.move(to: CGPoint(x: point.x, y: point.y - 12))
        path.line(to: CGPoint(x: point.x, y: point.y + 12))
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
