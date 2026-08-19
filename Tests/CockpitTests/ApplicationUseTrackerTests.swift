import Foundation
import XCTest
@testable import Cockpit

@MainActor
final class ApplicationUseTrackerTests: XCTestCase {
    func testRecordsApplicationLaunchCountsAcrossTrackerInstances() {
        let defaults = isolatedDefaults()
        let finder = application("Finder")

        let firstTracker = PersistentApplicationUseTracker(defaults: defaults)
        firstTracker.recordLaunch(of: finder)
        firstTracker.recordLaunch(of: finder)

        let restartedTracker = PersistentApplicationUseTracker(defaults: defaults)

        XCTAssertEqual(restartedTracker.score(for: finder), 2)
    }

    private func application(_ name: String) -> ApplicationCandidate {
        ApplicationCandidate(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "ApplicationUseTrackerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}
