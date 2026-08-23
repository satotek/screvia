import ServiceManagement
import XCTest

@testable import ScreviaKit

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testStatusFlagsForAllSystemStates() {
        let cases: [(SMAppService.Status, Bool, Bool)] = [
            (.notRegistered, false, false),
            (.enabled, true, false),
            (.requiresApproval, false, true),
            (.notFound, false, false)
        ]

        for (status, expectedIsEnabled, expectedRequiresApproval) in cases {
            let service = FakeLaunchAtLoginService(status: status)
            let controller = LaunchAtLoginController(service: service)

            XCTAssertEqual(controller.isEnabled, expectedIsEnabled)
            XCTAssertEqual(controller.requiresApproval, expectedRequiresApproval)
        }
    }

    func testEnablingUnregisteredServiceRegistersIt() throws {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        let controller = LaunchAtLoginController(service: service)

        try controller.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertTrue(controller.isEnabled)
    }

    func testEnablingAlreadyEnabledServiceDoesNotRegisterAgain() throws {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let controller = LaunchAtLoginController(service: service)

        try controller.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testDisablingRegisteredServiceUnregistersIt() throws {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let controller = LaunchAtLoginController(service: service)

        try controller.setEnabled(false)

        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertFalse(controller.isEnabled)
        if case .notRegistered = controller.status {
            // Expected.
        } else {
            XCTFail("The service should be unregistered")
        }
    }

    func testDisablingUnregisteredServiceDoesNotUnregisterAgain() throws {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        let controller = LaunchAtLoginController(service: service)

        try controller.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testRegisterErrorIsPropagated() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.registerError = FakeError.register
        let controller = LaunchAtLoginController(service: service)

        XCTAssertThrowsError(try controller.setEnabled(true)) { error in
            XCTAssertTrue(error is FakeError)
        }
        XCTAssertEqual(service.registerCallCount, 1)
        if case .notRegistered = controller.status {
            // The failed operation must not change the state.
        } else {
            XCTFail("A failed registration should leave the service unregistered")
        }
    }

    func testUnregisterErrorIsPropagated() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        service.unregisterError = FakeError.unregister
        let controller = LaunchAtLoginController(service: service)

        XCTAssertThrowsError(try controller.setEnabled(false)) { error in
            XCTAssertTrue(error is FakeError)
        }
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertTrue(controller.isEnabled)
    }

    func testOpenSystemSettingsIsForwarded() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        let controller = LaunchAtLoginController(service: service)

        controller.openSystemSettings()

        XCTAssertEqual(service.openSystemSettingsCallCount, 1)
    }
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginService {
    var status: SMAppService.Status
    var statusAfterRegister: SMAppService.Status = .enabled
    var statusAfterUnregister: SMAppService.Status = .notRegistered
    var registerError: Error?
    var unregisterError: Error?
    var registerCallCount = 0
    var unregisterCallCount = 0
    var openSystemSettingsCallCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = statusAfterUnregister
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}

private enum FakeError: Error {
    case register
    case unregister
}
