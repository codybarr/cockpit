import Foundation
import XCTest
@testable import Cockpit

@MainActor
final class SystemActionTests: XCTestCase {
    func testLockDelegatesToTheAccessibilityScreenLocker() throws {
        let locker = RecordingScreenLocker()
        let executor = MacOSSystemActionExecutor(screenLocker: locker)

        try executor.execute(.lock)

        XCTAssertEqual(locker.lockCount, 1)
    }
}

@MainActor
private final class RecordingScreenLocker: ScreenLocking {
    private(set) var lockCount = 0

    func lockScreen() throws {
        lockCount += 1
    }
}
