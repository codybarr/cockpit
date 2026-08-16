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

        XCTAssertEqual(controller.state.results, [.application(clock)])
        XCTAssertEqual(controller.state.selectedResult, .application(clock))
    }

    func testArrowSelectionStaysWithinResults() {
        let clock = application("Clock Utility")
        let notes = application("Notes Utility")
        let controller = makeController(catalog: StubCatalog(applications: [clock, notes]))
        controller.invoke()
        controller.updateQuery("utility")

        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.state.selectedResult, .application(notes))

        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.state.selectedResult, .application(notes))

        controller.moveSelection(by: -2)
        XCTAssertEqual(controller.state.selectedResult, .application(clock))
    }

    func testSelectingAndExecutingApplicationDelegatesToTypedLauncher() {
        let clock = application("Clock")
        let notes = application("Notes")
        let launcher = RecordingApplicationLauncher()
        let controller = makeController(catalog: StubCatalog(applications: [clock, notes]), launcher: launcher)
        controller.invoke()
        controller.updateQuery("notes")

        controller.selectResult(at: 0)
        controller.executeSelectedResult()

        XCTAssertEqual(launcher.launchedApplications, [notes])
        XCTAssertFalse(controller.state.isVisible)
        XCTAssertEqual(controller.state.query, "")

        controller.invoke()

        XCTAssertTrue(controller.state.query.isEmpty)
        XCTAssertTrue(controller.state.results.isEmpty)
    }

    func testQueryIncludesSystemActionsAndRanksThemWithApplicationResults() {
        let restartUtility = application("Restart Utility")
        let controller = makeController(catalog: StubCatalog(applications: [restartUtility]))
        controller.invoke()

        controller.updateQuery("restart")

        XCTAssertEqual(controller.state.results, [.systemAction(.restart), .application(restartUtility)])
        XCTAssertEqual(controller.state.selectedResult, .systemAction(.restart))
    }

    func testExecutingSystemActionDelegatesToTypedExecutorAndHidesLauncher() {
        let executor = RecordingSystemActionExecutor()
        let controller = makeController(catalog: StubCatalog(applications: []), systemActionExecutor: executor)
        controller.invoke()
        controller.updateQuery("lock")

        controller.executeSelectedResult()

        XCTAssertEqual(executor.executedActions, [.lock])
        XCTAssertFalse(controller.state.isVisible)
    }

    func testSystemActionFailureLeavesLauncherVisibleWithAPlainError() {
        let executor = RecordingSystemActionExecutor(error: SystemActionTestError.permissionDenied)
        let controller = makeController(catalog: StubCatalog(applications: []), systemActionExecutor: executor)
        controller.invoke()
        controller.updateQuery("shut down")

        controller.executeSelectedResult()

        XCTAssertTrue(controller.state.isVisible)
        XCTAssertEqual(controller.state.errorMessage, "Cockpit could not shut down: macOS denied permission to perform this System action.")
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
        revealer: RecordingApplicationRevealer = RecordingApplicationRevealer(),
        systemActionExecutor: RecordingSystemActionExecutor = RecordingSystemActionExecutor()
    ) -> LauncherController {
        LauncherController(
            catalog: catalog,
            launcher: launcher,
            revealer: revealer,
            systemActionExecutor: systemActionExecutor
        )
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

@MainActor
private final class RecordingSystemActionExecutor: SystemActionExecuting {
    private(set) var executedActions: [SystemAction] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func execute(_ action: SystemAction) throws {
        if let error { throw error }
        executedActions.append(action)
    }
}

private enum SystemActionTestError: LocalizedError {
    case permissionDenied

    var errorDescription: String? { "macOS denied permission to perform this System action." }
}
