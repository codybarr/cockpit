import Foundation
import XCTest
@testable import Cockpit

@MainActor
final class LauncherControllerTests: XCTestCase {
    func testInvokingLauncherPresentsCatalogApplicationsWithBestResultSelected() throws {
        let clock = ApplicationCandidate(name: "Clock", url: URL(fileURLWithPath: "/Applications/Clock.app"))
        let notes = ApplicationCandidate(name: "Notes", url: URL(fileURLWithPath: "/Applications/Notes.app"))
        let controller = LauncherController(catalog: StubCatalog(applications: [clock, notes]), launcher: RecordingApplicationLauncher())

        controller.invoke()

        XCTAssertTrue(controller.state.isVisible)
        XCTAssertEqual(controller.state.results, [clock, notes])
        XCTAssertEqual(controller.state.selectedResult, clock)
    }

    func testArrowSelectionStaysWithinResults() throws {
        let clock = ApplicationCandidate(name: "Clock", url: URL(fileURLWithPath: "/Applications/Clock.app"))
        let notes = ApplicationCandidate(name: "Notes", url: URL(fileURLWithPath: "/Applications/Notes.app"))
        let controller = LauncherController(catalog: StubCatalog(applications: [clock, notes]), launcher: RecordingApplicationLauncher())
        controller.invoke()

        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.state.selectedResult, notes)

        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.state.selectedResult, notes)

        controller.moveSelection(by: -2)
        XCTAssertEqual(controller.state.selectedResult, clock)
    }

    func testSelectingAndExecutingApplicationDelegatesToTypedLauncher() throws {
        let clock = ApplicationCandidate(name: "Clock", url: URL(fileURLWithPath: "/Applications/Clock.app"))
        let notes = ApplicationCandidate(name: "Notes", url: URL(fileURLWithPath: "/Applications/Notes.app"))
        let launcher = RecordingApplicationLauncher()
        let controller = LauncherController(catalog: StubCatalog(applications: [clock, notes]), launcher: launcher)
        controller.invoke()

        controller.selectResult(at: 1)
        controller.executeSelectedResult()

        XCTAssertEqual(launcher.launchedApplications, [notes])
        XCTAssertFalse(controller.state.isVisible)
    }
}

private struct StubCatalog: ApplicationCataloging {
    let applications: [ApplicationCandidate]

    func scan() throws -> [ApplicationCandidate] { applications }
}

@MainActor
private final class RecordingApplicationLauncher: ApplicationLaunching {
    private(set) var launchedApplications: [ApplicationCandidate] = []

    func launch(_ application: ApplicationCandidate) throws {
        launchedApplications.append(application)
    }
}
