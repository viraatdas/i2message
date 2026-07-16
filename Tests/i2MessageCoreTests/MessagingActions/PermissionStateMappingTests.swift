import XCTest
@testable import i2MessageCore

final class PermissionStateMappingTests: XCTestCase {
    func testSystemAuthorizationStatesMapToPermissionStates() {
        XCTAssertEqual(PermissionStateMapper.map(.authorized), .granted)
        XCTAssertEqual(PermissionStateMapper.map(.provisional), .granted)
        XCTAssertEqual(PermissionStateMapper.map(.ephemeral), .granted)
        XCTAssertEqual(PermissionStateMapper.map(.notDetermined), .notDetermined)
        XCTAssertEqual(PermissionStateMapper.map(.denied), .denied)
        XCTAssertEqual(PermissionStateMapper.map(.restricted), .restricted)
        XCTAssertEqual(PermissionStateMapper.map(.unsupported), .unsupported)
    }

    func testAutomationDenialRecoversAfterExternalGrantWithoutRelaunch() async throws {
        let automation = TransitioningAutomation()
        let manager = MacOSPermissionManager(automation: automation)

        await automation.setDenied(true)
        let denied = try await manager.request(.appleEventsMessages)
        XCTAssertEqual(denied.state, .denied)

        await automation.setDenied(false)
        let refreshed = await manager.refreshedAppleEventsStatus()
        XCTAssertEqual(refreshed.state, .granted)
    }
}

private actor TransitioningAutomation: MessagesAutomationControlling {
    private var denied = false

    func setDenied(_ denied: Bool) {
        self.denied = denied
    }

    func isMessagesAvailable() async -> Bool { true }

    func execute(_ command: MessagesAppleScriptCommand) async throws -> MessagesAutomationResult {
        if denied {
            throw MessagesAutomationFailure(kind: .appleEventsDenied, reason: "test denied")
        }
        return MessagesAutomationResult()
    }

    func openMessages() async throws {}
}
