import Combine
import Foundation

protocol ApplicationCataloging {
    func scan() throws -> [ApplicationCandidate]
}

typealias ApplicationLaunchCompletion = @MainActor (Result<Void, Error>) -> Void

@MainActor
protocol ApplicationLaunching: AnyObject {
    func launch(_ application: ApplicationCandidate, completion: @escaping ApplicationLaunchCompletion) throws
}

@MainActor
protocol ApplicationRevealing: AnyObject {
    func reveal(_ application: ApplicationCandidate) throws
}

@MainActor
protocol SystemSettingsPaneLaunching: AnyObject {
    func launch(_ pane: SystemSettingsPane) throws
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
protocol CalculationCopying: AnyObject {
    func copy(_ calculation: Calculation) throws
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

@MainActor
final class PersistentApplicationUseTracker: ApplicationUseTracking {
    static let storageKey = "applicationLaunchCounts"

    private let defaults: UserDefaults
    private var launchCounts: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchCounts = defaults.dictionary(forKey: Self.storageKey) as? [String: Int] ?? [:]
    }

    func score(for application: ApplicationCandidate) -> Int {
        launchCounts[application.url.absoluteString, default: 0]
    }

    func recordLaunch(of application: ApplicationCandidate) {
        let applicationID = application.url.absoluteString
        launchCounts[applicationID, default: 0] += 1
        defaults.set(launchCounts, forKey: Self.storageKey)
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

    var contentHeight: CGFloat {
        if errorMessage != nil || (!query.isEmpty && results.isEmpty) {
            return 128
        }
        guard !results.isEmpty else { return 76 }
        return 76 + min(CGFloat(results.count) * 60 + 4, 364)
    }
}

@MainActor
final class LauncherController: ObservableObject {
    private let catalog: any ApplicationCataloging
    private let launcher: any ApplicationLaunching
    private let revealer: any ApplicationRevealing
    private let systemSettingsPaneCatalog: any SystemSettingsPaneCataloging
    private let systemSettingsPaneLauncher: any SystemSettingsPaneLaunching
    private let systemActionExecutor: any SystemActionExecuting
    private let filenameIndex: any FilenameIndexing
    private let fileOpener: any FileOpening
    private let fileRevealer: any FileRevealing
    private let calculationCopier: any CalculationCopying
    private let useTracker: any ApplicationUseTracking
    private let search: ApplicationSearch
    @Published private(set) var state = LauncherState()

    init(
        catalog: any ApplicationCataloging,
        launcher: any ApplicationLaunching,
        revealer: any ApplicationRevealing,
        systemSettingsPaneCatalog: any SystemSettingsPaneCataloging = SystemSettingsPaneCatalog(),
        systemSettingsPaneLauncher: any SystemSettingsPaneLaunching,
        systemActionExecutor: any SystemActionExecuting,
        filenameIndex: any FilenameIndexing,
        fileOpener: any FileOpening,
        fileRevealer: any FileRevealing,
        calculationCopier: any CalculationCopying,
        useTracker: any ApplicationUseTracking = InMemoryApplicationUseTracker(),
        search: ApplicationSearch = ApplicationSearch()
    ) {
        self.catalog = catalog
        self.launcher = launcher
        self.revealer = revealer
        self.systemSettingsPaneCatalog = systemSettingsPaneCatalog
        self.systemSettingsPaneLauncher = systemSettingsPaneLauncher
        self.systemActionExecutor = systemActionExecutor
        self.filenameIndex = filenameIndex
        self.fileOpener = fileOpener
        self.fileRevealer = fileRevealer
        self.calculationCopier = calculationCopier
        self.useTracker = useTracker
        self.search = search
    }

    func invoke() {
        state = LauncherState(isVisible: true)
    }

    @discardableResult
    func startFilenameSearch(replacingExistingQuery: Bool = false) -> Bool {
        guard state.query.isEmpty || replacingExistingQuery else { return false }
        updateQuery("'")
        return true
    }

    func updateQuery(_ query: String) {
        // A leading space begins filename search only when the Launchpad is
        // empty. Replacing a selected query is handled by LauncherPanel before
        // SwiftUI updates this binding, so a literal space remains literal here.
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
                state.results = filenameQuery.count < 3
                    ? []
                    : search.ranked(try filenameIndex.matches(for: filenameQuery).map(LauncherResult.file), for: filenameQuery)
            } else if let calculation = try? Calculator.calculate(query) {
                state.results = [.calculation(calculation)]
            } else {
                let applications = try catalog.scan().map(LauncherResult.application)
                let panes = systemSettingsPaneCatalog.panes().map(LauncherResult.systemSettingsPane)
                let systemActions = SystemAction.allCases.map(LauncherResult.systemAction)
                state.results = search.ranked(applications + panes + systemActions, for: query) { result in
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

        let resultCount = state.results.count
        let wrappedIndex = (selectedIndex + offset) % resultCount
        state.selectedIndex = wrappedIndex >= 0 ? wrappedIndex : wrappedIndex + resultCount
    }

    func setRevealHintVisible(_ isVisible: Bool) {
        state.isRevealHintVisible = isVisible
    }

    func executeSelectedResult() {
        guard let selectedResult = state.selectedResult else { return }

        do {
            switch selectedResult {
            case let .application(application):
                try launcher.launch(application) { [weak self] result in
                    guard case .success = result else { return }
                    self?.useTracker.recordLaunch(of: application)
                }
            case let .systemSettingsPane(pane):
                try systemSettingsPaneLauncher.launch(pane)
            case let .file(file):
                try fileOpener.open(file)
            case let .systemAction(action):
                try systemActionExecutor.execute(action)
            case let .calculation(calculation):
                try calculationCopier.copy(calculation)
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
            case .systemSettingsPane: return
            case let .file(file): try fileRevealer.reveal(file)
            case .systemAction, .calculation: return
            }
            dismiss()
        } catch {
            state.errorMessage = "Cockpit could not reveal \(selectedResult.label): \(error.localizedDescription)"
        }
    }
}
