import AppKit

/// Area captures whose area is chosen with macOS's own screenshot tool.
///
/// Screvia's overlay is an ordinary window, so the first click on it tells
/// other apps a click landed elsewhere, and their menus close. The system
/// tool takes the pointer without that, so an open menu stays open and is
/// captured live, with nothing frozen.
nonisolated enum SystemAreaCapture {
    /// The area chosen, or nil when it was cancelled. The tool reports the
    /// image only, not where on screen the area was.
    static func capture(includeCursor: Bool, includeWindowShadow: Bool) async throws -> NSImage? {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            throw CaptureService.CaptureError.screenRecordingPermissionRequired
        }

        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        // -i chooses interactively, Space switching to a window as with ⌘⇧4;
        // -x keeps the tool's own shutter sound out of it, Screvia plays its
        // own; -o leaves the shadow off a chosen window.
        var arguments = ["-i", "-x"]
        if includeCursor {
            arguments.append("-C")
        }
        if !includeWindowShadow {
            arguments.append("-o")
        }
        arguments.append(url.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume()
            }
        }

        // A cancelled selection writes no file.
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let image = NSImage(data: data) else {
            throw CaptureService.CaptureError.displayImageUnavailable
        }
        return image
    }
}
