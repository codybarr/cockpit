import AppKit
import XCTest
@testable import Cockpit

@MainActor
final class IndexedFoldersWindowControllerTests: XCTestCase {
    func testIndexedFoldersWindowCapsItsContentHeightSoTheAddButtonRemainsReachable() {
        let controller = IndexedFoldersWindowController(index: EmptyFilenameIndex())
        controller.show()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

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
