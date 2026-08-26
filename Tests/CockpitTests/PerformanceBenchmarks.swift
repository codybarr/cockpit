import Foundation
import XCTest
@testable import Cockpit

@MainActor
final class PerformanceBenchmarks: XCTestCase {
    func testFiftyThousandItemQueryAndHotkeyTargets() throws {
        guard ProcessInfo.processInfo.environment["COCKPIT_RUN_BENCHMARKS"] == "1" else {
            throw XCTSkip("Set COCKPIT_RUN_BENCHMARKS=1 on an Apple-silicon Mac to run performance acceptance benchmarks.")
        }

        let files = (0..<50_000).map { index in
            FilenameCandidate(url: URL(fileURLWithPath: "/fixture/Quarterly Report \(index).pdf"))
        }
        let controller = makeController(filenameIndex: FixtureFilenameIndex(files: files))
        controller.updateQuery("'report") // Warm the fixture and SwiftUI observation machinery.

        let querySamples = samples(count: 30) {
            controller.updateQuery("'report")
        }
        let selectionSamples = samples(count: 30) {
            controller.moveSelection(by: 1)
        }
        let hotkeySamples = samples(count: 30) {
            controller.invoke()
        }

        let queryP95 = percentile(querySamples, 0.95)
        let queryP99 = percentile(querySamples, 0.99)
        let selectionP99 = percentile(selectionSamples, 0.99)
        let hotkeyP95 = percentile(hotkeySamples, 0.95)
        let hotkeyP99 = percentile(hotkeySamples, 0.99)
        XCTContext.runActivity(named: String(format: "50,000-item fixture: query p95 %.2f ms, p99 %.2f ms; selection p99 %.2f ms; hotkey p95 %.2f ms, p99 %.2f ms", queryP95 * 1_000, queryP99 * 1_000, selectionP99 * 1_000, hotkeyP95 * 1_000, hotkeyP99 * 1_000)) { _ in }

        XCTAssertLessThanOrEqual(queryP95, 0.016, "Query p95 must be at most 16 ms.")
        XCTAssertLessThanOrEqual(queryP99, 0.033, "Query p99 must be at most 33 ms.")
        XCTAssertLessThanOrEqual(selectionP99, 0.016, "Selection p99 must fit within one 60 Hz frame.")
        XCTAssertLessThanOrEqual(hotkeyP95, 0.033, "Hotkey-to-ready p95 must be at most 33 ms.")
        XCTAssertLessThanOrEqual(hotkeyP99, 0.050, "Hotkey-to-ready p99 must be at most 50 ms.")
    }

    private func makeController(filenameIndex: any FilenameIndexing) -> LauncherController {
        LauncherController(
            catalog: EmptyCatalog(),
            launcher: NoopWorkspace(),
            revealer: NoopWorkspace(),
            systemSettingsPaneCatalog: EmptySystemSettingsPaneCatalog(),
            systemSettingsPaneLauncher: NoopWorkspace(),
            systemActionExecutor: NoopSystemActionExecutor(),
            filenameIndex: filenameIndex,
            fileOpener: NoopWorkspace(),
            fileRevealer: NoopWorkspace(),
            calculationCopier: NoopWorkspace()
        )
    }

    private func samples(count: Int, operation: () -> Void) -> [TimeInterval] {
        (0..<count).map { _ in
            let start = DispatchTime.now().uptimeNanoseconds
            operation()
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        }.sorted()
    }

    private func percentile(_ samples: [TimeInterval], _ percentile: Double) -> TimeInterval {
        samples[Int((Double(samples.count) - 1) * percentile)]
    }
}

private final class EmptyCatalog: ApplicationCataloging {
    func scan() throws -> [ApplicationCandidate] { [] }
}

@MainActor
private final class NoopWorkspace: ApplicationLaunching, ApplicationRevealing, SystemSettingsPaneLaunching, FileOpening, FileRevealing, CalculationCopying {
    func launch(_: ApplicationCandidate) throws {}
    func launch(_: SystemSettingsPane) throws {}
    func reveal(_: ApplicationCandidate) throws {}
    func open(_: FilenameCandidate) throws {}
    func reveal(_: FilenameCandidate) throws {}
    func copy(_: Calculation) throws {}
}

@MainActor
private final class NoopSystemActionExecutor: SystemActionExecuting {
    func execute(_: SystemAction) throws {}
}

private struct EmptySystemSettingsPaneCatalog: SystemSettingsPaneCataloging {
    func panes() -> [SystemSettingsPane] { [] }
}

private final class FixtureFilenameIndex: FilenameIndexing {
    private let snapshot: FilenameSearchSnapshot

    init(files: [FilenameCandidate]) { snapshot = FilenameSearchSnapshot(files) }

    var indexedFolders: [URL] { [] }
    func folderState(for _: URL) -> IndexedFolderState { .available }
    func addIndexedFolder(_: URL) throws {}
    func removeIndexedFolder(_: URL) throws {}
    func retry(folder _: URL) throws {}
    func matches(for query: String) throws -> [FilenameCandidate] {
        snapshot.matches(for: SearchNormalizer.normalize(query))
    }
}
