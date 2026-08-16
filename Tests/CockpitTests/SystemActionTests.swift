import Foundation
import XCTest
@testable import Cockpit

@MainActor
final class SystemActionTests: XCTestCase {
    func testLockStartsTheScreenSaverThroughTheTypedProcessRunner() throws {
        let runner = RecordingSystemProcessRunner()
        let executor = MacOSSystemActionExecutor(processRunner: runner)

        try executor.execute(.lock)

        XCTAssertEqual(runner.invocations, [
            .init(
                executableURL: URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine"),
                arguments: ["-background"]
            ),
        ])
    }
}

@MainActor
private final class RecordingSystemProcessRunner: SystemProcessRunning {
    struct Invocation: Equatable {
        let executableURL: URL
        let arguments: [String]
    }

    private(set) var invocations: [Invocation] = []

    func start(executableURL: URL, arguments: [String]) throws {
        invocations.append(.init(executableURL: executableURL, arguments: arguments))
    }
}
