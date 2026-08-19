import XCTest
@testable import Cockpit

@MainActor
final class LoginItemSettingsTests: XCTestCase {
    func testEnablingRegistersTheOptInLoginItem() throws {
        let service = StubLoginItemService(status: .disabled)
        let settings = LoginItemSettings(service: service)

        try settings.setEnabled(true)

        XCTAssertEqual(service.enableCount, 1)
        XCTAssertEqual(settings.status, .enabled)
    }

    func testDisablingUnregistersTheOptInLoginItem() throws {
        let service = StubLoginItemService(status: .enabled)
        let settings = LoginItemSettings(service: service)

        try settings.setEnabled(false)

        XCTAssertEqual(service.disableCount, 1)
        XCTAssertEqual(settings.status, .disabled)
    }

    func testEnablingAnUnavailableLoginItemStillAttemptsRegistration() throws {
        let service = StubLoginItemService(status: .unavailable)
        let settings = LoginItemSettings(service: service)

        try settings.setEnabled(true)

        XCTAssertEqual(service.enableCount, 1)
        XCTAssertEqual(settings.status, .enabled)
    }

    func testApprovalNeededStatusDoesNotAttemptToOverrideSystemSettings() throws {
        let service = StubLoginItemService(status: .approvalRequired)
        let settings = LoginItemSettings(service: service)

        try settings.setEnabled(true)
        try settings.setEnabled(false)

        XCTAssertEqual(service.enableCount, 0)
        XCTAssertEqual(service.disableCount, 0)
        XCTAssertEqual(settings.status, .approvalRequired)
    }
}

@MainActor
private final class StubLoginItemService: LoginItemManaging {
    var status: LoginItemStatus
    private(set) var enableCount = 0
    private(set) var disableCount = 0

    init(status: LoginItemStatus) {
        self.status = status
    }

    func enable() throws {
        enableCount += 1
        status = .enabled
    }

    func disable() throws {
        disableCount += 1
        status = .disabled
    }
}
