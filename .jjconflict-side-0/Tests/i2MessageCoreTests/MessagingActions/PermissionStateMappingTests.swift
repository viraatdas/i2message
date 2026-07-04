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
}
