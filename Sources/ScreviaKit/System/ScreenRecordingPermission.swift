import AppKit
import CoreGraphics

enum ScreenRecordingPermission {
    /// Cached by macOS for the life of the process: a grant made in System
    /// Settings shows up here only after Screvia is relaunched.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// The system prompt appears only the first time an app asks; later calls
    /// return silently. The call still matters, because it is what puts
    /// Screvia in the Screen Recording list for the user to switch on.
    static func request() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        // Without this, LaunchServices just re-activates the running copy.
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            Task { @MainActor in
                if let error {
                    Log.app.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
                    ErrorPresenter.present(error)
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}
