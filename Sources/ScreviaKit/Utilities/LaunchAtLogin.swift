import AppKit
import ServiceManagement

/// Controls Screvia's presence in the user's macOS Login Items.
///
/// The system owns this state. Keeping it out of UserDefaults means the
/// Preferences window reflects changes made directly in System Settings too.
@MainActor
enum LaunchAtLoginManager {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        if case .enabled = status {
            return true
        }
        return false
    }

    static var requiresApproval: Bool {
        if case .requiresApproval = status {
            return true
        }
        return false
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp

        if enabled {
            if case .enabled = service.status {
                return
            }
            try service.register()
        } else {
            if case .notRegistered = service.status {
                return
            }
            try service.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
