import AppKit
import Foundation
import SwiftUI
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

    func testLiteralSpaceIsNotRewrittenWhenTheLaunchpadAlreadyHasInput() {
        let controller = makeController(catalog: StubCatalog(applications: []))
        controller.invoke()
        controller.updateQuery("Drew")

        controller.updateQuery(" ")

        XCTAssertEqual(controller.state.query, " ")
    }

    func testNormalAndFilenameQueriesKeepInternalSpaces() {
        let controller = makeController(catalog: StubCatalog(applications: []))
        controller.invoke()

        controller.updateQuery("Drew Estate")
        XCTAssertEqual(controller.state.query, "Drew Estate")

        controller.updateQuery("'Drew Estate")
        XCTAssertEqual(controller.state.query, "'Drew Estate")
    }

    func testSelectedQueryReplacementKeepsTheFilenamePrefixForSpaceAndApostropheInput() {
        let controller = makeController(catalog: StubCatalog(applications: []))
        controller.invoke()
        controller.updateQuery("report")

        XCTAssertTrue(controller.startFilenameSearch(replacingExistingQuery: true))
        XCTAssertEqual(controller.state.query, "'")

        controller.updateQuery("report")
        controller.updateQuery("'")
        XCTAssertEqual(controller.state.query, "'")
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
        XCTAssertEqual(controller.state.contentHeight, 450)

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

    func testExecutingAnApplicationDoesNotWaitForItsLaunchToComplete() {
        let notes = application("Notes")
        let launcher = DeferredApplicationLauncher()
        let controller = makeController(
            catalog: StubCatalog(applications: [notes]),
            launcher: launcher
        )
        controller.invoke()
        controller.updateQuery("notes")

        controller.executeSelectedResult()

        XCTAssertFalse(controller.state.isVisible, "The Launcher must dismiss before a cold application finishes launching.")
        XCTAssertTrue(launcher.hasPendingCompletion)
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

    func testRealSettingsCatalogFindsAndLaunchesPreviouslyMissingSettings() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paneLauncher = RecordingSystemSettingsPaneLauncher()
        let controller = makeController(
            catalog: StubCatalog(applications: []),
            systemSettingsPaneCatalog: SystemSettingsPaneCatalog(systemSettingsURL: root, macOSMajorVersion: 26),
            systemSettingsPaneLauncher: paneLauncher
        )
        for (query, destination) in [
            ("display", "com.apple.Displays-Settings.extension"),
            ("wifi", "com.apple.wifi-settings-extension"),
            ("bluetooth", "com.apple.BluetoothSettings"),
            ("icloud", "com.apple.systempreferences.AppleIDSettings:icloud"),
            ("menu bar", "com.apple.ControlCenter-Settings.extension*menubar"),
        ] {
            controller.invoke()
            controller.updateQuery(query)
            guard case let .systemSettingsPane(pane) = controller.state.selectedResult else {
                XCTFail("Missing selected setting for \(query)")
                continue
            }
            XCTAssertEqual(pane.destinationURL.absoluteString, "x-apple.systempreferences:\(destination)")
            controller.executeSelectedResult()
            XCTAssertEqual(paneLauncher.launchedPanes.last, pane)
            XCTAssertFalse(controller.state.isVisible)
        }
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

    func testClipboardCommandOpensTheExistingLauncherAndCopiesWithoutReordering() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: directory, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        history.setEnabled(true)
        for text in ["older", "Newest\nfull text"] {
            pb.clearContents()
            pb.setString(text, forType: .string)
            await history.capture()
        }
        let controller = makeController(catalog: StubCatalog(applications: []), clipboardHistory: history)
        controller.invoke()
        controller.updateQuery("clipboard")
        XCTAssertEqual(controller.state.selectedResult, .clipboardHistory)
        controller.executeSelectedResult()
        XCTAssertEqual(controller.state.context, .clipboard)
        XCTAssertEqual(controller.state.query, "")
        XCTAssertEqual(controller.state.results.count, 2)
        XCTAssertEqual(controller.state.contentHeight, 202)
        if ProcessInfo.processInfo.environment["COCKPIT_CAPTURE_UI"] == "1" {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: controller.state.contentHeight), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: LauncherView(controller: controller))
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(150))
            let view = try XCTUnwrap(window.contentView)
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/cockpit-clipboard-launcher.png"))
        }
        controller.moveSelection(by: 1)
        controller.executeSelectedResult()
        for _ in 0..<100 where controller.state.isVisible { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(controller.state.isVisible)
        XCTAssertEqual(pb.string(forType: .string), "older")
        XCTAssertEqual(history.entries.map(\.plainText), ["Newest\nfull text", "older"])
        controller.invoke()
        XCTAssertEqual(controller.state.context, .standard)
        XCTAssertTrue(controller.state.results.isEmpty)
    }

    func testClipboardContextTreatsSpacesAndApostrophesAsLiteralInput() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: directory, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        history.setEnabled(true)
        pb.clearContents()
        pb.setString("'a literal value", forType: .string)
        await history.capture()
        let controller = makeController(catalog: StubCatalog(applications: []), clipboardHistory: history)
        controller.invoke()
        controller.updateQuery("clipboard")
        controller.executeSelectedResult()
        XCTAssertFalse(controller.startFilenameSearch(replacingExistingQuery: true))
        controller.updateQuery("'A LITERAL")
        for _ in 0..<100 where controller.state.results.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(controller.state.query, "'A LITERAL")
        // Wait for the asynchronous clipboard-only filter to publish.
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(controller.state.results.count, 1)
        controller.updateQuery(" ")
        XCTAssertEqual(controller.state.query, " ")
        controller.updateQuery("definitely not in history")
        controller.executeSelectedResult()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(controller.state.isVisible, "A new query must not execute the previous query’s selection")
        XCTAssertTrue(controller.state.results.isEmpty)
    }

    func testClipboardSelectionFollowsEntryIdentityAcrossExternalCopiesAndClear() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: directory, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        history.setEnabled(true)
        for text in ["A", "B"] {
            pb.clearContents()
            pb.setString(text, forType: .string)
            await history.capture()
        }
        let controller = makeController(catalog: StubCatalog(applications: []), clipboardHistory: history)
        controller.invoke()
        controller.updateQuery("clipboard")
        controller.executeSelectedResult()
        controller.moveSelection(by: 1)
        let selectedID = controller.state.selectedResult?.id
        pb.clearContents()
        pb.setString("C", forType: .string)
        await history.capture()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(controller.state.selectedResult?.id, selectedID)
        XCTAssertEqual(controller.state.selectedIndex, 2)
        await history.clear()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(controller.state.selectedResult)
        XCTAssertEqual(controller.state.emptyMessage, "Clipboard history is empty.")
        XCTAssertEqual(controller.state.contentHeight, 128)
        history.setEnabled(false)
        try await Task.sleep(for: .milliseconds(20))
        controller.invoke()
        controller.updateQuery("clipboard")
        XCTAssertTrue(controller.state.results.isEmpty)
    }

    func testClipboardAlternateActionCopiesPathsButDoesNothingForAnImage() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: "example.txt")
        try Data("original".utf8).write(to: file)
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: root.appending(path: "history"), pasteboard: pb, monitorsAutomatically: false, volatileRoots: [])
        await history.load()
        history.setEnabled(true)
        pb.clearContents()
        pb.writeObjects([file as NSURL])
        await history.capture()
        let controller = makeController(catalog: StubCatalog(applications: []), clipboardHistory: history)
        controller.invoke()
        controller.updateQuery("clipboard")
        controller.executeSelectedResult()
        controller.revealSelectedResult()
        for _ in 0..<100 where controller.state.isVisible { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(controller.state.isVisible)
        XCTAssertEqual(pb.string(forType: .string), file.path)
        XCTAssertFalse(pb.types?.contains(.fileURL) ?? false)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        pb.clearContents()
        pb.setData(try XCTUnwrap(bitmap.representation(using: .png, properties: [:])), forType: .png)
        await history.capture()
        controller.invoke()
        controller.updateQuery("clipboard")
        controller.executeSelectedResult()
        let count = pb.changeCount
        controller.revealSelectedResult()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(controller.state.isVisible)
        XCTAssertEqual(pb.changeCount, count)
        controller.executeSelectedResult()
        controller.dismiss() // Escape while the asynchronous copy is being prepared.
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(pb.changeCount, count, "Dismissal must cancel a pending replay")
    }

    func testClipboardRowsFitWithoutScrollingWhenAllResultsFitInTheLauncher() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: directory, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        history.setEnabled(true)
        for rowCount in [4, 6] { // The recording's four rows, and the six-row viewport boundary.
            await history.clear()
            for number in 1...rowCount {
                pb.clearContents()
                if rowCount == 4 && number < 4 { // Three images and text, like the recording.
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: number * 10, pixelsHigh: 10, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                    bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
                    pb.setData(try XCTUnwrap(bitmap.representation(using: .png, properties: [:])), forType: .png)
                } else {
                    pb.setString("Row \(number)", forType: .string)
                }
                await history.capture()
            }
            let controller = makeController(catalog: StubCatalog(applications: []), clipboardHistory: history)
            controller.invoke()
            controller.updateQuery("clipboard")
            controller.executeSelectedResult()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: controller.state.contentHeight), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: LauncherView(controller: controller))
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(100))
            let scroll = try XCTUnwrap(findScrollView(in: try XCTUnwrap(window.contentView)))
            let document = try XCTUnwrap(scroll.documentView)
            XCTAssertLessThanOrEqual(document.frame.height, scroll.contentView.bounds.height + 0.5,
                                     "\(rowCount) fixed-height rows must not overflow their viewport")
            let origin = scroll.contentView.bounds.origin
            controller.moveSelection(by: -1) // First → last, as in the recording.
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(scroll.contentView.bounds.origin, origin, "Wrapping to the last row must not shift a fully visible list")
            controller.moveSelection(by: 1)
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(scroll.contentView.bounds.origin, origin)
        }
    }

    func testClipboardSearchDoesNotPublishANoMatchesFrameBeforeFilteringCompletes() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: directory, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        history.setEnabled(true)
        pb.clearContents()
        pb.setString("Matching clipboard text", forType: .string)
        await history.capture()
        let controller = makeController(catalog: StubCatalog(applications: []), clipboardHistory: history)
        controller.invoke()
        controller.updateQuery("clipboard")
        controller.executeSelectedResult()
        var falseEmptyMessages = 0
        let observer = controller.$state.sink { state in
            if state.query == "matching", state.emptyMessage == "No matching results found." {
                falseEmptyMessages += 1
            }
        }
        defer { observer.cancel() }
        let previousResults = controller.state.results
        let previousHeight = controller.state.contentHeight
        controller.updateQuery("matching")
        XCTAssertTrue(controller.state.isSearching)
        XCTAssertEqual(controller.state.results, previousResults)
        XCTAssertEqual(controller.state.contentHeight, previousHeight, "The panel must not collapse while a filter is pending")
        controller.executeSelectedResult()
        controller.revealSelectedResult()
        for _ in 0..<100 where controller.state.isSearching { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(controller.state.isSearching)
        XCTAssertTrue(controller.state.isVisible, "The previous results must not be executable while filtering")
        XCTAssertEqual(controller.state.results.count, 1)
        XCTAssertEqual(falseEmptyMessages, 0, "A matching query must never briefly announce no matches")

        controller.updateQuery("no such entry")
        XCTAssertNil(controller.state.emptyMessage)
        XCTAssertEqual(controller.state.contentHeight, previousHeight)
        for _ in 0..<100 where controller.state.isSearching { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(controller.state.isSearching)
        XCTAssertEqual(controller.state.emptyMessage, "No matching results found.")
        XCTAssertEqual(controller.state.contentHeight, 128)

        // Replacing a genuine no-match query must not announce that old outcome for
        // the new query, including intermediate @Published state snapshots.
        controller.updateQuery("matching")
        XCTAssertNil(controller.state.emptyMessage)
        XCTAssertEqual(controller.state.contentHeight, 128)
        for _ in 0..<100 where controller.state.isSearching { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(controller.state.isSearching)
        XCTAssertEqual(controller.state.results.count, 1)
        XCTAssertEqual(falseEmptyMessages, 0)
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }

    private func application(_ name: String) -> ApplicationCandidate {
        ApplicationCandidate(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    private func makeController(
        catalog: StubCatalog,
        launcher: any ApplicationLaunching = RecordingApplicationLauncher(),
        revealer: RecordingApplicationRevealer = RecordingApplicationRevealer(),
        systemSettingsPaneCatalog: any SystemSettingsPaneCataloging = StubSystemSettingsPaneCatalog(panes: []),
        systemSettingsPaneLauncher: RecordingSystemSettingsPaneLauncher = RecordingSystemSettingsPaneLauncher(),
        systemActionExecutor: RecordingSystemActionExecutor = RecordingSystemActionExecutor(),
        filenameIndex: StubFilenameIndex = StubFilenameIndex(files: []),
        fileOpener: RecordingFileOpener = RecordingFileOpener(),
        fileRevealer: RecordingFileRevealer = RecordingFileRevealer(),
        calculationCopier: RecordingCalculationCopier = RecordingCalculationCopier(),
        useTracker: any ApplicationUseTracking = InMemoryApplicationUseTracker(),
        clipboardHistory: ClipboardHistory? = nil
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
            useTracker: useTracker,
            clipboardHistory: clipboardHistory
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
private final class DeferredApplicationLauncher: ApplicationLaunching {
    private(set) var hasPendingCompletion = false

    func launch(_: ApplicationCandidate, completion: @escaping ApplicationLaunchCompletion) throws {
        hasPendingCompletion = true
    }
}

@MainActor
private final class RecordingApplicationLauncher: ApplicationLaunching {
    private(set) var launchedApplications: [ApplicationCandidate] = []

    func launch(_ application: ApplicationCandidate, completion: @escaping ApplicationLaunchCompletion) throws {
        launchedApplications.append(application)
        completion(.success(()))
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
