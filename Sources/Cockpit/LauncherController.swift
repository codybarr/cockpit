import Combine
import Foundation

protocol ApplicationCataloging {
    func scan() throws -> [ApplicationCandidate]
}

@MainActor
protocol ApplicationLaunching: AnyObject {
    func launch(_ application: ApplicationCandidate) throws
}

@MainActor
protocol ApplicationRevealing: AnyObject {
    func reveal(_ application: ApplicationCandidate) throws
}

@MainActor
protocol ApplicationUseTracking: AnyObject {
    func score(for application: ApplicationCandidate) -> Int
    func recordLaunch(of application: ApplicationCandidate)
}

@MainActor
final class InMemoryApplicationUseTracker: ApplicationUseTracking {
    private var launchCounts: [URL: Int] = [:]

    func score(for application: ApplicationCandidate) -> Int {
        launchCounts[application.url, default: 0]
    }

    func recordLaunch(of application: ApplicationCandidate) {
        launchCounts[application.url, default: 0] += 1
    }
}

struct LauncherState: Equatable {
    var isVisible = false
    var query = ""
    var results: [ApplicationCandidate] = []
    var selectedIndex: Int?
    var isRevealHintVisible = false
    var errorMessage: String?

    var selectedResult: ApplicationCandidate? {
        guard let selectedIndex, results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }
}

@MainActor
final class LauncherController: ObservableObject {
    private let catalog: any ApplicationCataloging
    private let launcher: any ApplicationLaunching
    private let revealer: any ApplicationRevealing
    private let useTracker: any ApplicationUseTracking
    private let search: ApplicationSearch
    @Published private(set) var state = LauncherState()

    init(
        catalog: any ApplicationCataloging,
        launcher: any ApplicationLaunching,
        revealer: any ApplicationRevealing,
        useTracker: any ApplicationUseTracking = InMemoryApplicationUseTracker(),
        search: ApplicationSearch = ApplicationSearch()
    ) {
        self.catalog = catalog
        self.launcher = launcher
        self.revealer = revealer
        self.useTracker = useTracker
        self.search = search
    }

    func invoke() {
        state = LauncherState(isVisible: true)
    }

    func updateQuery(_ query: String) {
        state.query = query
        state.errorMessage = nil

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state.results = []
            state.selectedIndex = nil
            return
        }

        do {
            state.results = search.ranked(try catalog.scan(), for: query, usageScore: useTracker.score)
            state.selectedIndex = state.results.isEmpty ? nil : 0
        } catch {
            state.results = []
            state.selectedIndex = nil
            state.errorMessage = "Cockpit could not load applications: \(error.localizedDescription)"
        }
    }

    func dismiss() {
        state = LauncherState()
    }

    func selectResult(at index: Int) {
        guard state.results.indices.contains(index) else { return }
        state.selectedIndex = index
    }

    func moveSelection(by offset: Int) {
        guard let selectedIndex = state.selectedIndex, !state.results.isEmpty else { return }
        state.selectedIndex = min(max(selectedIndex + offset, state.results.startIndex), state.results.index(before: state.results.endIndex))
    }

    func setRevealHintVisible(_ isVisible: Bool) {
        state.isRevealHintVisible = isVisible
    }

    func executeSelectedResult() {
        guard let selectedResult = state.selectedResult else { return }

        do {
            try launcher.launch(selectedResult)
            useTracker.recordLaunch(of: selectedResult)
            dismiss()
        } catch {
            state.errorMessage = "Cockpit could not open \(selectedResult.name): \(error.localizedDescription)"
        }
    }

    func revealSelectedResult() {
        guard let selectedResult = state.selectedResult else { return }

        do {
            try revealer.reveal(selectedResult)
            dismiss()
        } catch {
            state.errorMessage = "Cockpit could not reveal \(selectedResult.name): \(error.localizedDescription)"
        }
    }
}
