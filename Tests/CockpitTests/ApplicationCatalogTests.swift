import Foundation
import XCTest
@testable import Cockpit

final class ApplicationCatalogTests: XCTestCase {
    func testDiscoversApplicationBundlesFromConfiguredRoots() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let application = root.appending(path: "Utilities/Example.app")
        try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
        try "".write(to: root.appending(path: "not-an-app.txt"), atomically: true, encoding: .utf8)

        let catalog = ApplicationCatalog(roots: [root], includesFinder: false)

        XCTAssertEqual(
            try catalog.scan(),
            [ApplicationCandidate(name: "Example", url: application.resolvingSymlinksInPath())]
        )
    }

    func testIncludesFinderAsASearchableApplication() throws {
        let applications = try ApplicationCatalog(roots: []).scan()

        XCTAssertTrue(applications.contains(ApplicationCatalog.finder))
    }

    func testDiscoversApplicationsInSystemApplicationRoots() throws {
        let applications = try ApplicationCatalog().scan()

        XCTAssertTrue(applications.contains { $0.url.path == "/System/Applications/Preview.app" })
        XCTAssertTrue(applications.contains { $0.url.path == "/System/Applications/Utilities/Disk Utility.app" })
    }

    func testStandardRootsExcludeSystemLibrary() {
        XCTAssertFalse(ApplicationCatalog.standardRoots.contains { $0.path.hasPrefix("/System/Library") })
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
