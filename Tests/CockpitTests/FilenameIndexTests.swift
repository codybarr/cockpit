import Foundation
import XCTest
@testable import Cockpit

final class FilenameIndexTests: XCTestCase {
    func testIndexesFilenameMatchesFromSelectedFoldersAndDeletesThemWhenFolderIsRemoved() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let notes = root.appending(path: "Projects/Meeting Notes.md")
        try FileManager.default.createDirectory(at: notes.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: notes, atomically: true, encoding: .utf8)

        let index = try FilenameIndex(databaseURL: root.appending(path: "index.sqlite"))
        try index.addIndexedFolder(root)

        XCTAssertEqual(try index.matches(for: "meeting").map(\.name), ["Meeting Notes.md"])

        try index.removeIndexedFolder(root)

        XCTAssertTrue(try index.matches(for: "meeting").isEmpty)
    }

    func testRefreshesAfterFilesystemEvents() throws {
        let root = try makeTemporaryDirectory()
        let databaseDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: databaseDirectory)
        }
        let index = try FilenameIndex(databaseURL: databaseDirectory.appending(path: "index.sqlite"))
        try index.addIndexedFolder(root)

        let expectedFile = root.appending(path: "created-after-watching.txt")
        let refreshed = expectation(description: "filename index receives the filesystem event")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try? "".write(to: expectedFile, atomically: true, encoding: .utf8)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if (try? index.matches(for: "created-after-watching"))?.map(\.name).contains(expectedFile.lastPathComponent) == true {
                refreshed.fulfill()
            }
        }
        wait(for: [refreshed], timeout: 3)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: ".build/CockpitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
