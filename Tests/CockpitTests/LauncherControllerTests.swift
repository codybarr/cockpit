import Foundation
import XCTest
@testable import Cockpit

@MainActor
final class LauncherControllerTests: XCTestCase {
    func testInvokingLauncherDisplaysNoResultsUntilTheUserTypesAQuery() {
        let catalog = StubCatalog(applications: [application("Clock"), application("Notes")])
        let controller = makeController(catalog: catalog)

        controller.invoke()

        XCTAssertTrue(controller.state.isVisible)
        XCTAssertEqual(controller.state.query, "")
        XCTAssertTrue(controller.state.results.isEmpty)
        XCTAssertNil(controller.state.selectedResult)
        XCTAssertEqual(catalog.scanCount, 0)
    }

    func testQueryingRanksApplicationsAndSelectsTheBestResult() {
        let clock = application("Clock")
        let calendar = application("Calendar")
        let controller = makeController(catalog: StubCatalog(applications: [calendar, clock]))
        controller.invoke()

        controller.updateQuery("clock")

        XCTAssertEqual(controller.state.results, [clock])
        XCTAssertEqual(controller.state.selectedResult, clock)
    }

    func testArrowSelectionStaysWithinResults() {
        let clock = application("Clock")
        let notes = application("Notes")
        let controller = makeController(catalog: StubCatalog(applications: [clock, notes]))
        controller.invoke()
        controller.updateQuery("o")

        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.state.selectedResult, notes)

        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.state.selectedResult, notes)

        controller.moveSelection(by: -2)
        XCTAssertEqual(controller.state.selectedResult, clock)
    }

    func testSelectingAndExecutingApplicationDelegatesToTypedLauncher() {
        let clock = application("Clock")
        let notes = application("Notes")
        let launcher = RecordingApplicationLauncher()
        let controller = makeController(catalog: StubCatalog(applications: [clock, notes]), launcher: launcher)
        controller.invoke()
        controller.updateQuery("o")

        controller.selectResult(at: 1)
        controller.executeSelectedResult()

        XCTAssertEqual(launcher.launchedApplications, [notes])
        XCTAssertFalse(controller.state.isVisible)
        XCTAssertEqual(controller.state.query, "")

        controller.invoke()

        XCTAssertTrue(controller.state.query.isEmpty)
        XCTAssertTrue(controller.state.results.isEmpty)
    }

    func testRevealDelegatesToTypedRevealerAndHidesLauncher() {
        let clock = application("Clock")
        let revealer = RecordingApplicationRevealer()
        let controller = makeController(catalog: StubCatalog(applications: [clock]), revealer: revealer)
        controller.invoke()
        controller.updateQuery("clock")

        controller.revealSelectedResult()

        XCTAssertEqual(revealer.revealedApplications, [clock])
        XCTAssertFalse(controller.state.isVisible)
    }

    func testRevealHintIsShownOnlyWhileTheModifierIsHeld() {
        let controller = makeController(catalog: StubCatalog(applications: [application("Clock")]))
        controller.invoke()

        controller.setRevealHintVisible(true)
        XCTAssertTrue(controller.state.isRevealHintVisible)

        controller.setRevealHintVisible(false)
        XCTAssertFalse(controller.state.isRevealHintVisible)
    }

    func testDismissHidesLauncherWithoutExecutingAResult() {
        let controller = makeController(catalog: StubCatalog(applications: [application("Clock")]))
        controller.invoke()

        controller.dismiss()

        XCTAssertFalse(controller.state.isVisible)
    }

    private func application(_ name: String) -> ApplicationCandidate {
        ApplicationCandidate(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    private func makeController(
        catalog: StubCatalog,
        launcher: RecordingApplicationLauncher = RecordingApplicationLauncher(),
        revealer: RecordingApplicationRevealer = RecordingApplicationRevealer()
    ) -> LauncherController {
        LauncherController(catalog: catalog, launcher: launcher, revealer: revealer)
    }
}

private final class StubCatalog: ApplicationCataloging, @unchecked Sendable {
    let applications: [ApplicationCandidate]
    private(set) var scanCount = 0

    init(applications: [ApplicationCandidate]) {
        self.applications = applications
    }

    func scan() throws -> [ApplicationCandidate] {
        scanCount += 1
        return applications
    }
}

@MainActor
private final class RecordingApplicationLauncher: ApplicationLaunching {
    private(set) var launchedApplications: [ApplicationCandidate] = []

    func launch(_ application: ApplicationCandidate) throws {
        launchedApplications.append(application)
    }
}

@MainActor
private final class RecordingApplicationRevealer: ApplicationRevealing {
    private(set) var revealedApplications: [ApplicationCandidate] = []

    func reveal(_ application: ApplicationCandidate) throws {
        revealedApplications.append(application)
    }
}
