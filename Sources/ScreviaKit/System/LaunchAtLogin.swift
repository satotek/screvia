import AppKit
import ServiceManagement

protocol LaunchAtLoginService {
    var status: SMAppService.Status { get }

    func register() throws
    func unregister() throws
    func openSystemSettings()
}

private struct SystemLaunchAtLoginService: LaunchAtLoginService {
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

final class LaunchAtLoginController {
    private let service: any LaunchAtLoginService

    init() {
        service = SystemLaunchAtLoginService()
    }

    init(service: any LaunchAtLoginService) {
        self.service = service
    }

    var status: SMAppService.Status {
        service.status
    }

    var isEnabled: Bool {
        if case .enabled = status {
            return true
        }
        return false
    }

    var requiresApproval: Bool {
        if case .requiresApproval = status {
            return true
        }
        return false
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if isEnabled {
                return
            }
            try service.register()
        } else {
            if case .notRegistered = status {
                return
            }
            try service.unregister()
        }
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}

/// Controls Screvia's presence in the user's macOS Login Items.
///
/// The system owns this state. Keeping it out of UserDefaults means the
/// Preferences window reflects changes made directly in System Settings too.
enum LaunchAtLoginManager {
    private static let controller = LaunchAtLoginController()

    static var status: SMAppService.Status {
        controller.status
    }

    static var isEnabled: Bool {
        controller.isEnabled
    }

    static var requiresApproval: Bool {
        controller.requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        try controller.setEnabled(enabled)
    }

    static func openSystemSettings() {
        controller.openSystemSettings()
    }
}
