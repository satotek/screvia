/// Owns the app's standalone windows — Preferences, About, Licenses, the
/// permission guide — so
/// AppDelegate doesn't have to hold each controller itself.
final class WindowsCoordinator {
    private let preferencesController = PreferencesWindowController()
    private let aboutController = AboutWindowController()
    private let licensesController = LicensesWindowController()
    private let permissionOnboardingController = PermissionOnboardingWindowController()

    func openPreferences(settings: ScreviaSettings) {
        preferencesController.show(settings: settings)
    }

    func openAbout() {
        aboutController.show()
    }

    func openLicenses() {
        licensesController.show()
    }

    func openPermissionOnboarding() {
        permissionOnboardingController.show()
    }
}
