/// Owns the app's standalone windows — Preferences, About, Licenses — so
/// AppDelegate doesn't have to hold each controller itself.
@MainActor
final class WindowsCoordinator {
    private let preferencesController = PreferencesWindowController()
    private let aboutController = AboutWindowController()
    private let licensesController = LicensesWindowController()

    func openPreferences(settings: ScreviaSettings) {
        preferencesController.show(settings: settings)
    }

    func openAbout() {
        aboutController.show()
    }

    func openLicenses() {
        licensesController.show()
    }
}
