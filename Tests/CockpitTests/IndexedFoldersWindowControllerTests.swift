import AppKit
import XCTest
@testable import Cockpit

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testSettingsWindowIncludesClipboardControlsWithoutGrowingTheWindow() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        let controller = SettingsWindowController(index: EmptyFilenameIndex(), hotkeySettings: LauncherHotkeySettings(), clipboardHistory: history)
        controller.show()
        defer { controller.window?.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(controller.window?.contentView?.bounds.size, NSSize(width: 560, height: 480))
        XCTAssertFalse(history.isEnabled)
        if ProcessInfo.processInfo.environment["COCKPIT_CAPTURE_UI"] == "1" {
            let view = try XCTUnwrap(controller.window?.contentView)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/cockpit-clipboard-settings.png"))
        }
    }

    func testSettingsWindowPresentsHotkeyAndIndexedFolderSettingsOnOnePage() {
        let controller = SettingsWindowController(
            index: EmptyFilenameIndex(),
            hotkeySettings: LauncherHotkeySettings()
        )
        controller.show()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(controller.window?.title, "Settings")
        XCTAssertLessThanOrEqual(controller.window!.frame.height, 632)
    }
}

private final class EmptyFilenameIndex: FilenameIndexing {
    var indexedFolders: [URL] { [] }
    func folderState(for folder: URL) -> IndexedFolderState { .available }
    func addIndexedFolder(_ folder: URL) throws {}
    func removeIndexedFolder(_ folder: URL) throws {}
    func retry(folder: URL) throws {}
    func matches(for query: String) throws -> [FilenameCandidate] { [] }
}
