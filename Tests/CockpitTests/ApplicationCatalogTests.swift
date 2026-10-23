import AppKit
import Foundation
import XCTest
@testable import Cockpit

final class ApplicationCatalogTests: XCTestCase {
    @MainActor
    func testMenuBarIconIsAvailableOutsideAnAppBundle() throws {
        let url = try XCTUnwrap(CockpitApp.menuBarIconURL)
        XCTAssertNotNil(NSImage(contentsOf: url))
    }

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

    func testDisplayPathUsesAnApplicationsAliasOnlyForTheSameApp() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let application = root.appending(path: "System/Safari.app")
        let applications = root.appending(path: "Applications")
        try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let alias = applications.appending(path: "Safari.app")

        XCTAssertEqual(ApplicationCatalog.displayURL(for: application, applicationsDirectory: applications), application)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: application)
        XCTAssertEqual(ApplicationCatalog.displayURL(for: application, applicationsDirectory: applications), alias)
        let candidate = ApplicationCandidate(name: "Safari", url: application, displayURL: alias)
        XCTAssertEqual(candidate.url, application)
        XCTAssertEqual(candidate.displayURL, alias)
        XCTAssertEqual(candidate.iconCacheKey, application.path)

        try FileManager.default.removeItem(at: alias)
        try FileManager.default.createDirectory(at: alias, withIntermediateDirectories: true)
        XCTAssertEqual(ApplicationCatalog.displayURL(for: application, applicationsDirectory: applications), application)
    }

    func testInstalledSafariDisplaysItsFinderFacingPath() throws {
        let alias = URL(fileURLWithPath: "/Applications/Safari.app")
        guard FileManager.default.fileExists(atPath: alias.path) else { throw XCTSkip("Safari is not installed") }
        let safari = try XCTUnwrap(ApplicationCatalog().scan().first { $0.url.path == alias.resolvingSymlinksInPath().path })
        XCTAssertEqual(safari.displayURL.path, "/Applications/Safari.app")
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

    func testStandardRootsIncludeUserFacingSystemAppsWithoutScanningAllCoreServices() {
        let paths = ApplicationCatalog.standardRoots.map(\.path)
        XCTAssertTrue(paths.contains("/System/Library/CoreServices/Applications"))
        XCTAssertTrue(paths.contains("/System/Volumes/Preboot/Cryptexes/App/System/Applications"))
        XCTAssertFalse(paths.contains("/System/Library"))
        XCTAssertFalse(paths.contains("/System/Library/CoreServices"))
    }

    func testDiscoversSafariAndCoreServicesUtilitiesWhenInstalled() throws {
        let applications = try ApplicationCatalog().scan()
        for path in [
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app",
            "/System/Library/CoreServices/Applications/Screen Sharing.app",
            "/System/Library/CoreServices/Applications/Archive Utility.app",
        ] where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            XCTAssertEqual(applications.filter { $0.url.path == url.path }.count, 1, path)
        }
    }

    func testDiscoversEmbeddedToolsButNotArbitraryBundleHelpers() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = [
            "Developer.app",
            "Developer.app/Contents/Applications/Instruments.app",
            "Developer.app/Contents/Developer/Applications/Simulator.app",
            "Developer.app/Contents/Library/Hidden Helper.app",
        ]
        for path in paths {
            try FileManager.default.createDirectory(at: root.appending(path: path), withIntermediateDirectories: true)
        }
        let applications = try ApplicationCatalog(roots: [root], includesFinder: false).scan()
        XCTAssertEqual(Set(applications.map(\.name)), ["Developer", "Instruments", "Simulator"])
    }

    func testOverlappingRootsAndApplicationSymlinksDoNotDuplicateResults() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let application = root.appending(path: "Utilities/Example.app")
        try FileManager.default.createDirectory(at: application, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "Alias.app"), withDestinationURL: application)
        let applications = try ApplicationCatalog(
            roots: [root, root.appending(path: "Utilities")], includesFinder: false
        ).scan()
        XCTAssertEqual(applications.map(\.url), [application.resolvingSymlinksInPath()])
    }

    func testSystemSettingsPaneCacheServesAnInitiallyEmptySnapshotThenRefreshesOffTheCaller() {
        let expected = [SystemSettingsPane(name: "Displays", identifier: "com.apple.Displays-Settings.extension")]
        let cache = SystemSettingsPaneCache(catalog: StubSystemSettingsPaneCatalog(panes: expected))

        XCTAssertEqual(cache.panes(), [])
        cache.refreshInBackground()

        let refreshed = expectation(description: "System Settings panes are cached")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if cache.panes() == expected { refreshed.fulfill() }
        }
        wait(for: [refreshed], timeout: 1)
    }

    func testSystemSettingsPaneCatalogDoesNotReturnDestinationsWhenSystemSettingsIsUnavailable() {
        let catalog = SystemSettingsPaneCatalog(systemSettingsURL: URL(fileURLWithPath: "/missing/System Settings.app"))

        XCTAssertEqual(catalog.panes(), [])
    }

    func testEverySystemSettingsPaneHasAnAvailableIcon() {
        for pane in SystemSettingsPaneCatalog.supportedPanes {
            let icon = pane.icon
            if let resourcePath = icon.resourcePath {
                XCTAssertNotNil(NSImage(contentsOfFile: resourcePath), "\(pane.name) resource icon is unavailable")
            } else {
                XCTAssertNotNil(NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: nil), "\(pane.name) uses an unavailable symbol: \(icon.symbolName)")
            }
        }
    }

    func testInstalledSystemSettingsCatalogKeepsDisplaysWiFiAndBluetoothSearchable() {
        let panes = SystemSettingsPaneCatalog().panes()
        for (query, identifier) in [
            ("display", "com.apple.Displays-Settings.extension"),
            ("wifi", "com.apple.wifi-settings-extension"),
            ("bluetooth", "com.apple.BluetoothSettings"),
        ] {
            XCTAssertTrue(ApplicationSearch().ranked(panes, for: query).contains { $0.identifier == identifier }, "Missing setting for \(query)")
        }
    }

    func testCatalogMatchesEveryAuditedAlfredEntryWithoutPrivateApplePlists() throws {
        struct ReferencePane: Decodable {
            let name: String
            let url: String
            let icon: String
        }
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "alfred-system-settings", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode([String: [ReferencePane]].self, from: Data(contentsOf: fixtureURL))
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        for version in [13, 14, 15, 26, 27] {
            let expected = try XCTUnwrap(reference[String(min(version, 26))])
            let panes = SystemSettingsPaneCatalog(systemSettingsURL: root, macOSMajorVersion: version).panes()
            XCTAssertEqual(panes.map(\.name), expected.map(\.name), "macOS \(version) names/order")
            XCTAssertEqual(panes.map { $0.destinationURL.absoluteString }, expected.map(\.url), "macOS \(version) destinations")
            XCTAssertEqual(Set(panes.map(\.id)).count, panes.count, "macOS \(version) duplicate identities")
            for (pane, entry) in zip(panes, expected) {
                XCTAssertEqual(pane.iconBundlePath, entry.icon.hasPrefix("__customicon") ? nil : entry.icon)
            }
        }
    }

    func testCatalogRetainsPanesWhenPrivateApplePlistsAreMalformed() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appending(path: "Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try "not a plist".write(to: resources.appending(path: "Sidebar.plist"), atomically: true, encoding: .utf8)
        XCTAssertEqual(SystemSettingsPaneCatalog(systemSettingsURL: root, macOSMajorVersion: 26).panes().count, 46)
    }

    func testSystemSettingsPaneCatalogIncludesReferencePanes() {
        let panes = SystemSettingsReference.panes(for: 26)

        XCTAssertTrue(panes.contains { $0.name == "About" })
        XCTAssertTrue(panes.contains { $0.name == "Accessibility" })
        XCTAssertTrue(panes.contains { $0.name == "Displays" })
        XCTAssertTrue(panes.contains { $0.name == "Login Items & Extensions" })
        XCTAssertTrue(panes.contains { $0.name == "Bluetooth" })
        XCTAssertTrue(panes.contains { $0.name == "Privacy & Security" })
        XCTAssertTrue(panes.contains { $0.name == "Wi‑Fi" })
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct StubSystemSettingsPaneCatalog: SystemSettingsPaneCataloging {
    let availablePanes: [SystemSettingsPane]

    init(panes: [SystemSettingsPane]) { availablePanes = panes }
    func panes() -> [SystemSettingsPane] { availablePanes }
}
