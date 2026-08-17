import XCTest
@testable import Cockpit

@MainActor
final class LauncherHotkeySettingsTests: XCTestCase {
    func testSelectingAnAllowedHotkeyAppliesAndPersistsIt() {
        let defaults = isolatedDefaults()
        var appliedHotkeys: [LauncherHotkey] = []
        let settings = LauncherHotkeySettings(defaults: defaults) { hotkey in
            appliedHotkeys.append(hotkey)
            return true
        }

        settings.select(.commandSpace)

        XCTAssertEqual(appliedHotkeys, [.commandSpace])
        XCTAssertEqual(settings.selectedHotkey, .commandSpace)
        XCTAssertEqual(defaults.string(forKey: LauncherHotkeySettings.storageKey), LauncherHotkey.commandSpace.rawValue)
    }

    func testLoadsThePreviouslyPersistedHotkey() {
        let defaults = isolatedDefaults()
        defaults.set(LauncherHotkey.controlSpace.rawValue, forKey: LauncherHotkeySettings.storageKey)

        let settings = LauncherHotkeySettings(defaults: defaults)

        XCTAssertEqual(settings.selectedHotkey, .controlSpace)
    }

    func testFailedHotkeyRegistrationLeavesTheCurrentSelectionUnchanged() {
        let defaults = isolatedDefaults()
        let settings = LauncherHotkeySettings(defaults: defaults) { _ in false }

        settings.select(.controlSpace)

        XCTAssertEqual(settings.selectedHotkey, .optionSpace)
        XCTAssertNil(defaults.string(forKey: LauncherHotkeySettings.storageKey))
    }

    func testOnlyTheSupportedSpaceHotkeysAreAvailable() {
        XCTAssertEqual(LauncherHotkey.allCases, [.controlSpace, .optionSpace, .commandSpace])
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "LauncherHotkeySettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}
