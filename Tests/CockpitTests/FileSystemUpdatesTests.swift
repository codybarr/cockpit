import Foundation
import XCTest
@testable import Cockpit

final class FileSystemUpdatesTests: XCTestCase {
    func testFilenameIndexReconcilesFilesCreatedWhileCockpitWasNotRunning() throws {
        let root = try makeTemporaryDirectory()
        let databaseDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: databaseDirectory)
        }
        let databaseURL = databaseDirectory.appending(path: "index.sqlite")
        do {
            let index = try FilenameIndex(databaseURL: databaseURL, events: ControllableFileSystemEvents())
            try index.addIndexedFolder(root)
        }
        try "bargle".write(to: root.appending(path: "bargle.txt"), atomically: true, encoding: .utf8)

        let restartedIndex = try FilenameIndex(databaseURL: databaseURL, events: ControllableFileSystemEvents())
        let deadline = Date().addingTimeInterval(1)
        while try restartedIndex.matches(for: "bargle").isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(try restartedIndex.matches(for: "bargle").map(\.name), ["bargle.txt"])
    }

    func testApplicationCatalogRefreshesAfterAFilesystemChange() throws {
        let app = ApplicationCandidate(name: "Example", url: URL(fileURLWithPath: "/Applications/Example.app"))
        let catalog = MutableCatalog(applications: [])
        let events = ControllableFileSystemEvents()
        let cache = ApplicationCatalogCache(catalog: catalog, roots: [URL(fileURLWithPath: "/Applications")], events: events)
        try cache.refresh()

        catalog.applications = [app]
        events.send(.changed(URL(fileURLWithPath: "/Applications/Example.app")))

        XCTAssertEqual(try cache.scan(), [app])
    }

    func testApplicationCatalogReconcilesDroppedEvents() throws {
        let app = ApplicationCandidate(name: "Recovered", url: URL(fileURLWithPath: "/Applications/Recovered.app"))
        let catalog = MutableCatalog(applications: [])
        let events = ControllableFileSystemEvents()
        let cache = ApplicationCatalogCache(catalog: catalog, roots: [URL(fileURLWithPath: "/Applications")], events: events)
        try cache.refresh()

        catalog.applications = [app]
        events.send(.historyDropped)

        XCTAssertEqual(try cache.scan(), [app])
    }

    func testFilenameIndexReconcilesDroppedEventsAndRemovesStaleResults() throws {
        let root = try makeTemporaryDirectory()
        let databaseDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: databaseDirectory)
        }
        let events = ControllableFileSystemEvents()
        let index = try FilenameIndex(databaseURL: databaseDirectory.appending(path: "index.sqlite"), events: events)
        let file = root.appending(path: "old.txt")
        try "old".write(to: file, atomically: true, encoding: .utf8)
        try index.addIndexedFolder(root)

        try FileManager.default.removeItem(at: file)
        let replacement = root.appending(path: "new.txt")
        try "new".write(to: replacement, atomically: true, encoding: .utf8)
        events.send(.historyDropped)

        XCTAssertTrue(try index.matches(for: "old").isEmpty)
        XCTAssertEqual(try index.matches(for: "new").map(\.name), ["new.txt"])
    }

    func testFilenameIndexReconcilesCreatesRenamesMovesAndDeletions() throws {
        let root = try makeTemporaryDirectory()
        let databaseDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: databaseDirectory)
        }
        let events = ControllableFileSystemEvents()
        let index = try FilenameIndex(databaseURL: databaseDirectory.appending(path: "index.sqlite"), events: events)
        let stale = root.appending(path: "stale.txt")
        try "stale".write(to: stale, atomically: true, encoding: .utf8)
        try index.addIndexedFolder(root)

        try FileManager.default.removeItem(at: stale)
        let created = root.appending(path: "created.txt")
        try "created".write(to: created, atomically: true, encoding: .utf8)
        let renamed = root.appending(path: "renamed.txt")
        try FileManager.default.moveItem(at: created, to: renamed)
        let moved = root.appending(path: "nested/moved.txt")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: renamed, to: moved)

        events.send(.changed(moved))

        XCTAssertTrue(try index.matches(for: "stale").isEmpty)
        XCTAssertTrue(try index.matches(for: "created").isEmpty)
        XCTAssertTrue(try index.matches(for: "renamed").isEmpty)
        XCTAssertEqual(try index.matches(for: "moved").map(\.name), ["moved.txt"])
    }

    func testUnavailableIndexedFolderReportsStateAndRecoversThroughRetry() throws {
        let root = try makeTemporaryDirectory()
        let databaseDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: databaseDirectory)
        }
        let events = ControllableFileSystemEvents()
        let index = try FilenameIndex(databaseURL: databaseDirectory.appending(path: "index.sqlite"), events: events)
        try index.addIndexedFolder(root)

        try FileManager.default.removeItem(at: root)
        events.send(.rootUnavailable(root))
        XCTAssertEqual(index.folderState(for: root), .unavailable)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "back".write(to: root.appending(path: "recovered.txt"), atomically: true, encoding: .utf8)
        try index.retry(folder: root)

        XCTAssertEqual(index.folderState(for: root), .available)
        XCTAssertEqual(try index.matches(for: "recovered").map(\.name), ["recovered.txt"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class MutableCatalog: ApplicationCataloging, @unchecked Sendable {
    var applications: [ApplicationCandidate]

    init(applications: [ApplicationCandidate]) {
        self.applications = applications
    }

    func scan() throws -> [ApplicationCandidate] { applications }
}
