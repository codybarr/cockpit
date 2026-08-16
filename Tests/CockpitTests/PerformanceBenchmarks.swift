import Foundation
import XCTest
@testable import Cockpit

@MainActor
final class PerformanceBenchmarks: XCTestCase {
    func testFiftyThousandItemQueryAndHotkeyTargets() throws {
        guard ProcessInfo.processInfo.environment["COCKPIT_RUN_BENCHMARKS"] == "1" else {
            throw XCTSkip("Set COCKPIT_RUN_BENCHMARKS=1 on an Apple-silicon Mac to run performance acceptance benchmarks.")
        }

        let candidates = (0..<50_000).map { index in
            LauncherResult.file(FilenameCandidate(url: URL(fileURLWithPath: "/fixture/Quarterly Report \(index).pdf")))
        }
        let search = ApplicationSearch()
        let matches = candidates.filter { $0.normalizedSearchLabel.contains("report 49999") }
        let querySamples = samples(count: 30) {
            _ = search.ranked(matches, for: "report 49999")
        }

        let controller = LauncherController(
            catalog: EmptyCatalog(),
            launcher: NoopWorkspace(),
            revealer: NoopWorkspace(),
            systemSettingsPaneLauncher: NoopWorkspace(),
            systemActionExecutor: NoopSystemActionExecutor(),
            filenameIndex: EmptyFilenameIndex(),
            fileOpener: NoopWorkspace(),
            fileRevealer: NoopWorkspace()
        )
        let hotkeySamples = samples(count: 30) {
            controller.invoke()
        }

        let queryP95 = percentile(querySamples, 0.95)
        let queryP99 = percentile(querySamples, 0.99)
        let hotkeyP95 = percentile(hotkeySamples, 0.95)
        XCTContext.runActivity(named: String(format: "50,000-item fixture: query p95 %.2f ms, p99 %.2f ms; hotkey p95 %.2f ms", queryP95 * 1_000, queryP99 * 1_000, hotkeyP95 * 1_000)) { _ in }

        XCTAssertLessThanOrEqual(queryP95, 0.016, "Query p95 must be at most 16 ms.")
        XCTAssertLessThanOrEqual(queryP99, 0.033, "Query p99 must be at most 33 ms.")
        XCTAssertLessThanOrEqual(hotkeyP95, 0.100, "Hotkey-to-ready p95 must be at most 100 ms.")
    }

    private func samples(count: Int, operation: () -> Void) -> [TimeInterval] {
        (0..<count).map { _ in
            let start = Date()
            operation()
            return Date().timeIntervalSince(start)
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
private final class NoopWorkspace: ApplicationLaunching, ApplicationRevealing, SystemSettingsPaneLaunching, FileOpening, FileRevealing {
    func launch(_: ApplicationCandidate) throws {}
    func launch(_: SystemSettingsPane) throws {}
    func reveal(_: ApplicationCandidate) throws {}
    func open(_: FilenameCandidate) throws {}
    func reveal(_: FilenameCandidate) throws {}
}

@MainActor
private final class NoopSystemActionExecutor: SystemActionExecuting {
    func execute(_: SystemAction) throws {}
}

private final class EmptyFilenameIndex: FilenameIndexing {
    var indexedFolders: [URL] { [] }
    func folderState(for _: URL) -> IndexedFolderState { .available }
    func addIndexedFolder(_: URL) throws {}
    func removeIndexedFolder(_: URL) throws {}
    func retry(folder _: URL) throws {}
    func matches(for _: String) throws -> [FilenameCandidate] { [] }
}
