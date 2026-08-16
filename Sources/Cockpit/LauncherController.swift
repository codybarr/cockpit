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
protocol FileOpening: AnyObject {
    func open(_ file: FilenameCandidate) throws
}

@MainActor
protocol FileRevealing: AnyObject {
    func reveal(_ file: FilenameCandidate) throws
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
    var results: [LauncherResult] = []
    var selectedIndex: Int?
    var isRevealHintVisible = false
    var errorMessage: String?

    var selectedResult: LauncherResult? {
        guard let selectedIndex, results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }
}

@MainActor
final class LauncherController: ObservableObject {
    private let catalog: any ApplicationCataloging
    private let launcher: any ApplicationLaunching
    private let revealer: any ApplicationRevealing
    private let systemActionExecutor: any SystemActionExecuting
    private let filenameIndex: any FilenameIndexing
    private let fileOpener: any FileOpening
    private let fileRevealer: any FileRevealing
    private let useTracker: any ApplicationUseTracking
    private let search: ApplicationSearch
    @Published private(set) var state = LauncherState()

    init(
        catalog: any ApplicationCataloging,
        launcher: any ApplicationLaunching,
        revealer: any ApplicationRevealing,
        systemActionExecutor: any SystemActionExecuting,
        filenameIndex: any FilenameIndexing,
        fileOpener: any FileOpening,
        fileRevealer: any FileRevealing,
        useTracker: any ApplicationUseTracking = InMemoryApplicationUseTracker(),
        search: ApplicationSearch = ApplicationSearch()
    ) {
        self.catalog = catalog
        self.launcher = launcher
        self.revealer = revealer
        self.systemActionExecutor = systemActionExecutor
        self.filenameIndex = filenameIndex
        self.fileOpener = fileOpener
        self.fileRevealer = fileRevealer
        self.useTracker = useTracker
        self.search = search
    }

    func invoke() {
        state = LauncherState(isVisible: true)
    }

    @discardableResult
    func startFilenameSearch() -> Bool {
        guard state.query.isEmpty else { return false }
        updateQuery("'")
        return true
    }

    func updateQuery(_ query: String) {
        let query = state.query.isEmpty && query.hasPrefix(" ")
            ? "'" + query.dropFirst()
            : query
        state.query = query
        state.errorMessage = nil

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state.results = []
            state.selectedIndex = nil
            return
        }

        do {
            if query.hasPrefix("'") {
                let filenameQuery = String(query.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                state.results = search.ranked(try filenameIndex.matches(for: filenameQuery).map(LauncherResult.file), for: filenameQuery)
            } else {
                let applications = try catalog.scan().map(LauncherResult.application)
                let systemActions = SystemAction.allCases.map(LauncherResult.systemAction)
                state.results = search.ranked(applications + systemActions, for: query) { result in
                    guard case let .application(application) = result else { return 0 }
                    return self.useTracker.score(for: application)
                }
            }
            state.selectedIndex = state.results.isEmpty ? nil : 0
        } catch {
            state.results = []
            state.selectedIndex = nil
            state.errorMessage = "Cockpit could not search indexed filenames: \(error.localizedDescription)"
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
            switch selectedResult {
            case let .application(application):
                try launcher.launch(application)
                useTracker.recordLaunch(of: application)
            case let .file(file):
                try fileOpener.open(file)
            case let .systemAction(action):
                try systemActionExecutor.execute(action)
            }
            dismiss()
        } catch {
            state.errorMessage = "Cockpit could not \(selectedResult.label.lowercased()): \(error.localizedDescription)"
        }
    }

    func revealSelectedResult() {
        guard let selectedResult = state.selectedResult else { return }

        do {
            switch selectedResult {
            case let .application(application): try revealer.reveal(application)
            case let .file(file): try fileRevealer.reveal(file)
            case .systemAction: return
            }
            dismiss()
        } catch {
            state.errorMessage = "Cockpit could not reveal \(selectedResult.label): \(error.localizedDescription)"
        }
    }
}
