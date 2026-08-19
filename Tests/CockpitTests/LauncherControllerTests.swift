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

    func testStartingFilenameSearchAddsTheFileSearchPrefix() {
        let controller = makeController(catalog: StubCatalog(applications: []))
        controller.invoke()

        controller.startFilenameSearch()

        XCTAssertEqual(controller.state.query, "'")
        XCTAssertTrue(controller.state.results.isEmpty)
        XCTAssertNil(controller.state.selectedResult)
    }

    func testLeadingSpaceAlwaysStartsFilenameSearchAfterClearingAQuery() {
        let controller = makeController(catalog: StubCatalog(applications: []))
        controller.invoke()

        controller.updateQuery(" ")
        XCTAssertEqual(controller.state.query, "'")

        controller.updateQuery("'report")
        controller.updateQuery("")
        controller.updateQuery(" ")

        XCTAssertEqual(controller.state.query, "'")
        XCTAssertTrue(controller.state.results.isEmpty)
    }

    func testLeadingSpaceStartsFilenameSearchWhenItReplacesASelectedQuery() {
        let controller = makeController(catalog: StubCatalog(applications: []))
        controller.invoke()
        controller.updateQuery("report")

        // Cmd-A selects the current Launchpad text, so typing space replaces the
        // visible query even though the controller still holds the old value.
        controller.updateQuery(" ")

        XCTAssertEqual(controller.state.query, "'")
        XCTAssertTrue(controller.state.results.isEmpty)
    }

    func testStartingFilenameSearchCanReplaceAnExistingQuery() {
        let controller = makeController(catalog: StubCatalog(applications: []))
        controller.invoke()
        controller.updateQuery("report")

        XCTAssertTrue(controller.startFilenameSearch(replacingExistingQuery: true))
        XCTAssertEqual(controller.state.query, "'")
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

    func testClearingAFileSearchRestoresTheEmptyLauncherHeight() {
        let files = (1...7).map { number in
            FilenameCandidate(url: URL(fileURLWithPath: "/Users/cody/Documents/Report \(number).md"))
        }
        let controller = makeController(
            catalog: StubCatalog(applications: []),
            filenameIndex: StubFilenameIndex(files: files)
        )
        controller.invoke()

        controller.updateQuery("'report")
        XCTAssertEqual(controller.state.results.count, 7)
        XCTAssertEqual(controller.state.contentHeight, 440)

        controller.updateQuery("")

        XCTAssertTrue(controller.state.results.isEmpty)
        XCTAssertEqual(controller.state.contentHeight, 76)
    }

    func testApostropheQuerySearchesIndexedFilenamesAndOpensOrRevealsTheSelectedFile() {
        let file = FilenameCandidate(url: URL(fileURLWithPath: "/Users/cody/Projects/Meeting Notes.md"))
        let opener = RecordingFileOpener()
        let revealer = RecordingFileRevealer()
        let controller = makeController(
            catalog: StubCatalog(applications: [application("Meeting Notes")]),
            filenameIndex: StubFilenameIndex(files: [file]),
            fileOpener: opener,
            fileRevealer: revealer
        )
        controller.invoke()

        controller.updateQuery("meeting")
        XCTAssertEqual(controller.state.results, [.application(application("Meeting Notes"))])

        controller.updateQuery("'meeting")
        XCTAssertEqual(controller.state.results, [.file(file)])

        controller.executeSelectedResult()
        XCTAssertEqual(opener.openedFiles, [file])

        controller.invoke()
        controller.updateQuery("'meeting")
        controller.revealSelectedResult()
        XCTAssertEqual(revealer.revealedFiles, [file])
    }

    func testArrowSelectionWrapsAroundResults() {
        let clock = application("Clock Utility")
        let notes = application("Notes Utility")
        let controller = makeController(catalog: StubCatalog(applications: [clock, notes]))
        controller.invoke()
        controller.updateQuery("utility")

        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.state.selectedResult, .application(notes))

        controller.moveSelection(by: 1)
        XCTAssertEqual(controller.state.selectedResult, .application(clock))

        controller.moveSelection(by: -1)
        XCTAssertEqual(controller.state.selectedResult, .application(notes))
    }

    func testSuccessfulApplicationLaunchRecordsUsageWithoutCountingSelectionChanges() {
        let findMy = application("Find My")
        let finder = application("Finder")
        let tracker = InMemoryApplicationUseTracker()
        let controller = makeController(catalog: StubCatalog(applications: [findMy, finder]), useTracker: tracker)
        controller.invoke()
        controller.updateQuery("find")

        controller.moveSelection(by: 1)
        XCTAssertEqual(tracker.score(for: finder), 0)

        controller.executeSelectedResult()
        XCTAssertEqual(tracker.score(for: finder), 1)

        controller.invoke()
        controller.updateQuery("find")
        XCTAssertEqual(controller.state.selectedResult, .application(finder))
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

    func testQueryingSystemSettingsPaneShowsItAlongsideSystemSettingsAndLaunchesItsDestination() {
        let systemSettings = application("System Settings")
        let displays = SystemSettingsPane(name: "Displays", identifier: "com.apple.Displays-Settings.extension")
        let paneLauncher = RecordingSystemSettingsPaneLauncher()
        let controller = makeController(
            catalog: StubCatalog(applications: [systemSettings]),
            systemSettingsPaneCatalog: StubSystemSettingsPaneCatalog(panes: [displays]),
            systemSettingsPaneLauncher: paneLauncher
        )
        controller.invoke()

        controller.updateQuery("displays")
        XCTAssertEqual(controller.state.results, [.systemSettingsPane(displays)])

        controller.executeSelectedResult()
        XCTAssertEqual(paneLauncher.launchedPanes, [displays])
        XCTAssertFalse(controller.state.isVisible)
    }

    func testValidArithmeticExpressionShowsCalculatorResultAndCopiesItWhenExecuted() {
        let copier = RecordingCalculationCopier()
        let controller = makeController(catalog: StubCatalog(applications: []), calculationCopier: copier)
        controller.invoke()

        controller.updateQuery("$20 * 1.08")

        XCTAssertEqual(controller.state.results, [.calculation(Calculation(value: "21.6"))])
        controller.executeSelectedResult()

        XCTAssertEqual(copier.copiedCalculations, [Calculation(value: "21.6")])
        XCTAssertFalse(controller.state.isVisible)
    }

    func testMalformedArithmeticExpressionFallsThroughToNormalLauncherSearch() {
        let catalog = StubCatalog(applications: [])
        let controller = makeController(catalog: catalog)
        controller.invoke()

        controller.updateQuery("2 +")

        XCTAssertTrue(controller.state.results.isEmpty)
        XCTAssertEqual(catalog.scanCount, 1)
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
        systemSettingsPaneCatalog: StubSystemSettingsPaneCatalog = StubSystemSettingsPaneCatalog(panes: []),
        systemSettingsPaneLauncher: RecordingSystemSettingsPaneLauncher = RecordingSystemSettingsPaneLauncher(),
        systemActionExecutor: RecordingSystemActionExecutor = RecordingSystemActionExecutor(),
        filenameIndex: StubFilenameIndex = StubFilenameIndex(files: []),
        fileOpener: RecordingFileOpener = RecordingFileOpener(),
        fileRevealer: RecordingFileRevealer = RecordingFileRevealer(),
        calculationCopier: RecordingCalculationCopier = RecordingCalculationCopier(),
        useTracker: any ApplicationUseTracking = InMemoryApplicationUseTracker()
    ) -> LauncherController {
        LauncherController(
            catalog: catalog,
            launcher: launcher,
            revealer: revealer,
            systemSettingsPaneCatalog: systemSettingsPaneCatalog,
            systemSettingsPaneLauncher: systemSettingsPaneLauncher,
            systemActionExecutor: systemActionExecutor,
            filenameIndex: filenameIndex,
            fileOpener: fileOpener,
            fileRevealer: fileRevealer,
            calculationCopier: calculationCopier,
            useTracker: useTracker
        )
    }
}

private final class StubFilenameIndex: FilenameIndexing {
    let files: [FilenameCandidate]

    init(files: [FilenameCandidate]) { self.files = files }

    var indexedFolders: [URL] { [] }
    func folderState(for folder: URL) -> IndexedFolderState { .available }
    func addIndexedFolder(_ folder: URL) throws {}
    func removeIndexedFolder(_ folder: URL) throws {}
    func retry(folder: URL) throws {}
    func matches(for query: String) throws -> [FilenameCandidate] { files }
}

@MainActor
private final class RecordingCalculationCopier: CalculationCopying {
    private(set) var copiedCalculations: [Calculation] = []
    func copy(_ calculation: Calculation) throws { copiedCalculations.append(calculation) }
}

@MainActor
private final class RecordingFileOpener: FileOpening {
    private(set) var openedFiles: [FilenameCandidate] = []
    func open(_ file: FilenameCandidate) throws { openedFiles.append(file) }
}

@MainActor
private final class RecordingFileRevealer: FileRevealing {
    private(set) var revealedFiles: [FilenameCandidate] = []
    func reveal(_ file: FilenameCandidate) throws { revealedFiles.append(file) }
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

private struct StubSystemSettingsPaneCatalog: SystemSettingsPaneCataloging {
    let availablePanes: [SystemSettingsPane]

    init(panes: [SystemSettingsPane]) { availablePanes = panes }
    func panes() -> [SystemSettingsPane] { availablePanes }
}

@MainActor
private final class RecordingSystemSettingsPaneLauncher: SystemSettingsPaneLaunching {
    private(set) var launchedPanes: [SystemSettingsPane] = []
    func launch(_ pane: SystemSettingsPane) throws { launchedPanes.append(pane) }
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
