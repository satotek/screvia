import AppKit

enum ErrorPresenter {
    static func present(_ error: Error) {
        // Every failure path in the app funnels through here, so this single
        // call gives the alert a paper trail. The alert itself is transient;
        // Console.app keeps this.
        Log.app.error(
            """
            Surfaced error: \(String(describing: type(of: error)), privacy: .public) \
            — \(error.localizedDescription, privacy: .public)
            """
        )

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screvia"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.text("app.ok"))

        let captureError = error as? CaptureService.CaptureError
        if captureError?.requiresAccessibilityPermission == true {
            alert.addButton(withTitle: L10n.text("app.openSettings"))
        }

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            SystemSettingsService.openAccessibilitySettings()
        }
    }
}
