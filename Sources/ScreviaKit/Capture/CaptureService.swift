import AppKit
import CoreGraphics
import ScreenCaptureKit

nonisolated struct WindowCaptureSession {
    private let contentFilter: SCContentFilter
    private let configuration: SCStreamConfiguration

    init(window: SCWindow, includeShadow: Bool, includeCursor: Bool = false) {
        let contentFilter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = includeCursor
        if #available(macOS 14.2, *) {
            configuration.includeChildWindows = true
        }
        configuration.ignoreShadowsSingleWindow = !includeShadow
        configuration.width = max(
            1,
            Int(contentFilter.contentRect.width * CGFloat(contentFilter.pointPixelScale))
        )
        configuration.height = max(
            1,
            Int(contentFilter.contentRect.height * CGFloat(contentFilter.pointPixelScale))
        )

        self.contentFilter = contentFilter
        self.configuration = configuration
    }

    func capture() async throws -> CGImage {
        try await SCScreenshotManager.captureImage(
            contentFilter: contentFilter,
            configuration: configuration
        )
    }
}

nonisolated struct CaptureService {
    enum CaptureError: LocalizedError {
        case screenRecordingPermissionRequired
        case accessibilityPermissionRequired
        case noScreenAvailable
        case displayImageUnavailable
        case cropFailed
        case scrollCaptureTargetUnavailable
        case scrollCaptureFailed
        case noPreviousArea

        var errorDescription: String? {
            switch self {
            case .screenRecordingPermissionRequired:
                return L10n.text("error.screenRecordingPermission")
            case .accessibilityPermissionRequired:
                return L10n.text("error.accessibilityPermission")
            case .noScreenAvailable:
                return L10n.text("error.noScreen")
            case .displayImageUnavailable:
                return L10n.text("error.displayImageUnavailable")
            case .cropFailed:
                return L10n.text("error.cropFailed")
            case .scrollCaptureTargetUnavailable:
                return L10n.text("error.scrollCaptureTargetUnavailable")
            case .scrollCaptureFailed:
                return L10n.text("error.scrollCaptureFailed")
            case .noPreviousArea:
                return L10n.text("error.noPreviousArea")
            }
        }
    }

    // The only method here that reads the mouse location, so the only one
    // pinned to the main actor; the rest are callable from anywhere.
    @MainActor
    func captureMainDisplay() throws -> NSImage {
        guard let screen = ScreenUtilities.screenAtMouse() ?? NSScreen.screens.first else {
            throw CaptureError.noScreenAvailable
        }

        return try captureMainDisplay(on: screen)
    }

    func captureMainDisplay(on screen: NSScreen, cursor: CursorSnapshot? = nil) throws -> NSImage {
        try requireScreenCaptureAccess()
        return try captureFullDisplay(for: screen, cursor: cursor)
    }

    func capture(selection: CGRect, on screen: NSScreen, cursor: CursorSnapshot? = nil) throws -> NSImage {
        try requireScreenCaptureAccess()

        let screenBounds = CGRect(origin: .zero, size: screen.frame.size)
        let clippedSelection = selection.intersection(screenBounds)
        guard clippedSelection.width > 1, clippedSelection.height > 1 else {
            throw CaptureError.cropFailed
        }

        guard let displayImage = displayImage(for: screen, cursor: cursor) else {
            throw CaptureError.displayImageUnavailable
        }

        let pixelsPerPointX = CGFloat(displayImage.width) / screenBounds.width
        let pixelsPerPointY = CGFloat(displayImage.height) / screenBounds.height

        // Selection coordinates have their origin at the bottom-left in AppKit;
        // CGImage cropping has its origin at the top-left.
        let cropRect = CGRect(
            x: clippedSelection.minX * pixelsPerPointX,
            y: (screenBounds.height - clippedSelection.maxY) * pixelsPerPointY,
            width: clippedSelection.width * pixelsPerPointX,
            height: clippedSelection.height * pixelsPerPointY
        ).integral

        guard let croppedImage = displayImage.cropping(to: cropRect) else {
            throw CaptureError.cropFailed
        }

        return NSImage(
            cgImage: croppedImage,
            size: NSSize(width: clippedSelection.width, height: clippedSelection.height)
        )
    }

    func captureWindow(windowID: CGWindowID, includeShadow: Bool, includeCursor: Bool = false) async throws -> NSImage {
        try requireScreenCaptureAccess()

        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        guard let window = shareableContent.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.displayImageUnavailable
        }

        let session = WindowCaptureSession(window: window, includeShadow: includeShadow, includeCursor: includeCursor)
        let image = try await session.capture()
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    func makeWindowCaptureSession(
        windowID: CGWindowID,
        includeShadow: Bool
    ) async throws -> WindowCaptureSession {
        try requireScreenCaptureAccess()

        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        guard let window = shareableContent.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.displayImageUnavailable
        }

        return WindowCaptureSession(window: window, includeShadow: includeShadow)
    }

    private func captureFullDisplay(for screen: NSScreen, cursor: CursorSnapshot?) throws -> NSImage {
        guard let image = displayImage(for: screen, cursor: cursor) else {
            throw CaptureError.displayImageUnavailable
        }

        return NSImage(cgImage: image, size: screen.frame.size)
    }

    /// The whole screen, with the pointer drawn in when one is given: the
    /// display image itself never contains it.
    private func displayImage(for screen: NSScreen, cursor: CursorSnapshot? = nil) -> CGImage? {
        guard
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            let image = CGDisplayCreateImage(CGDirectDisplayID(screenNumber.uint32Value))
        else {
            return nil
        }
        guard let cursor, screen.frame.width > 0 else {
            return image
        }
        return cursor.drawn(onto: image, pixelsPerPoint: CGFloat(image.width) / screen.frame.width)
    }

    private func requireScreenCaptureAccess() throws {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            throw CaptureError.screenRecordingPermissionRequired
        }
    }
}
