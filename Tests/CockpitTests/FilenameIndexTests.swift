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

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
