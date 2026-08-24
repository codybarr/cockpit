import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Cockpit

final class LauncherKeypressTests: XCTestCase {
    func testCommandCommaRequestsSettingsOnlyFromTheActiveLauncher() {
        let commandComma = LauncherKeypress(
            keyCode: UInt16(kVK_ANSI_Comma),
            modifierFlags: [.command]
        )

        XCTAssertEqual(commandComma.action, .showSettings)
    }

    func testCommandEditingShortcutsDispatchToTheFocusedLaunchpad() {
        let commandC = LauncherKeypress(
            keyCode: UInt16(kVK_ANSI_C),
            modifierFlags: [.command]
        )
        let commandX = LauncherKeypress(
            keyCode: UInt16(kVK_ANSI_X),
            modifierFlags: [.command]
        )
        let commandV = LauncherKeypress(
            keyCode: UInt16(kVK_ANSI_V),
            modifierFlags: [.command]
        )

        XCTAssertEqual(commandC.action, .copy)
        XCTAssertEqual(commandX.action, .cut)
        XCTAssertEqual(commandV.action, .paste)
    }

    func testCommaWithoutCommandDoesNotRequestSettings() {
        let comma = LauncherKeypress(
            keyCode: UInt16(kVK_ANSI_Comma),
            modifierFlags: []
        )

        XCTAssertEqual(comma.action, .passThrough)
    }
}
