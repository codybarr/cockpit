import Foundation
import XCTest
@testable import Cockpit

@MainActor
final class SystemActionTests: XCTestCase {
    func testLockDelegatesToTheScreenLocker() throws {
        let locker = RecordingScreenLocker()
        let executor = MacOSSystemActionExecutor(screenLocker: locker)

        try executor.execute(.lock)

        XCTAssertEqual(locker.lockCount, 1)
    }

    func testLockFailureIsReturnedWithoutRetrying() {
        let locker = RecordingScreenLocker()
        locker.shouldFail = true
        let executor = MacOSSystemActionExecutor(screenLocker: locker)

        XCTAssertThrowsError(try executor.execute(.lock)) { error in
            XCTAssertTrue(error is RecordingScreenLocker.Failure)
        }
        XCTAssertEqual(locker.lockCount, 1)
    }
}

@MainActor
private final class RecordingScreenLocker: ScreenLocking {
    struct Failure: Error {}
    private(set) var lockCount = 0
    var shouldFail = false

    func lockScreen() throws {
        lockCount += 1
        if shouldFail { throw Failure() }
    }
}
