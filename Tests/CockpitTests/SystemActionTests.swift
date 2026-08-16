import Foundation
import XCTest
@testable import Cockpit

@MainActor
final class SystemActionTests: XCTestCase {
    func testLockStartsTheScreenSaverThroughLaunchServices() throws {
        let launcher = RecordingScreenSaverLauncher()
        let executor = MacOSSystemActionExecutor(screenSaverLauncher: launcher)

        try executor.execute(.lock)

        XCTAssertEqual(launcher.launchCount, 1)
    }
}

@MainActor
private final class RecordingScreenSaverLauncher: ScreenSaverLaunching {
    private(set) var launchCount = 0

    func launchScreenSaver() -> Bool {
        launchCount += 1
        return true
    }
}
