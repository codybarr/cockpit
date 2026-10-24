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

/// Shared by the native panel sizing and SwiftUI rows so gaps cannot create overflow.
enum LauncherLayout {
    static let launchpadHeight: CGFloat = 76
    static let rowHeight: CGFloat = 60
    static let rowSpacing: CGFloat = 2
    static let resultsPadding: CGFloat = 2
    static let visibleRowLimit = 6

    static func resultsHeight(for count: Int) -> CGFloat {
        let rows = min(count, visibleRowLimit)
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing + 2 * resultsPadding
    }
}

struct LauncherState: Equatable {
    enum Context: Equatable { case standard, clipboard }
    var context: Context = .standard
    var isVisible = false
    var query = ""
    var results: [LauncherResult] = []
    var selectedIndex: Int?
    var isRevealHintVisible = false
    var isSearching = false
    var errorMessage: String?

    var selectedResult: LauncherResult? {
        guard let selectedIndex, results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }

    var emptyMessage: String? {
        guard !isSearching, results.isEmpty else { return nil }
        if context == .clipboard && query.isEmpty { return "Clipboard history is empty." }
        return query.isEmpty ? nil : "No matching results found."
    }

    var contentHeight: CGFloat {
        if errorMessage != nil || emptyMessage != nil || (isSearching && results.isEmpty) {
            return 128
        }
        return LauncherLayout.launchpadHeight + LauncherLayout.resultsHeight(for: results.count)
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
    private let clipboardHistory: ClipboardHistory?
    private var clipboardObserver: AnyCancellable?
    private var clipboardSearchTask: Task<Void, Never>?
    private var clipboardCopyTask: Task<Void, Never>?
    private var clipboardCopyVersion = 0
    private var clipboardSearchVersion = 0
    private var clipboardStorageError: String?
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
        search: ApplicationSearch = ApplicationSearch(),
        clipboardHistory: ClipboardHistory? = nil
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
        self.clipboardHistory = clipboardHistory
        clipboardObserver = clipboardHistory?.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.state.context == .clipboard {
                    if self.clipboardHistory?.isEnabled == true {
                        self.refreshClipboardResults(preservingSelection: true)
                    } else {
                        self.dismiss()
                    }
                }
            }
        }
    }

    func invoke() {
        cancelClipboardWork()
        state = LauncherState(isVisible: true)
    }

    @discardableResult
    func startFilenameSearch(replacingExistingQuery: Bool = false) -> Bool {
        guard state.context == .standard, state.query.isEmpty || replacingExistingQuery else { return false }
        updateQuery("'")
        return true
    }

    func updateQuery(_ query: String) {
        clipboardCopyVersion += 1
        clipboardCopyTask?.cancel()
        clipboardCopyTask = nil
        if state.context == .clipboard {
            // Keep the last rendered rows/height until the next query completes, but mark
            // them non-executable. Publish query + pending status together so observers
            // never mistake an unfinished filter for a completed empty result.
            var nextState = state
            nextState.query = query
            nextState.isSearching = true
            nextState.errorMessage = nil
            state = nextState
            refreshClipboardResults(preservingSelection: false)
            return
        }
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
                let commands: [LauncherResult] = clipboardHistory?.isEnabled == true ? [.clipboardHistory] : []
                state.results = search.ranked(applications + panes + systemActions + commands, for: query) { result in
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
        cancelClipboardWork()
        state = LauncherState()
    }

    private func cancelClipboardWork() {
        clipboardSearchVersion += 1
        clipboardSearchTask?.cancel()
        clipboardCopyVersion += 1
        clipboardCopyTask?.cancel()
        clipboardCopyTask = nil
    }

    private func refreshClipboardResults(preservingSelection: Bool) {
        guard let clipboardHistory, state.context == .clipboard else { return }
        clipboardSearchVersion += 1
        let version = clipboardSearchVersion
        clipboardSearchTask?.cancel()
        let query = state.query
        let publish: ([ClipboardEntry]) -> Void = { [weak self] entries in
            guard let self, self.clipboardSearchVersion == version,
                  self.state.context == .clipboard else { return }
            let selectedID = preservingSelection ? self.state.selectedResult?.id : nil
            let previousIndex = preservingSelection ? (self.state.selectedIndex ?? 0) : 0
            var nextState = self.state
            nextState.results = entries.map(LauncherResult.clipboardEntry)
            nextState.selectedIndex = nextState.results.firstIndex { $0.id == selectedID }
                ?? (entries.isEmpty ? nil : min(previousIndex, entries.count - 1))
            nextState.isSearching = false
            if nextState.errorMessage == self.clipboardStorageError || clipboardHistory.errorMessage != nil {
                nextState.errorMessage = clipboardHistory.errorMessage
            }
            self.clipboardStorageError = clipboardHistory.errorMessage
            self.state = nextState
        }
        if query.isEmpty {
            publish(clipboardHistory.entries)
        } else {
            state.isSearching = true
            clipboardSearchTask = Task {
                let entries = await clipboardHistory.search(query)
                guard !Task.isCancelled else { return }
                publish(entries)
            }
        }
    }

    private func copyClipboardEntry(_ entry: ClipboardEntry, plainText: Bool) {
        guard clipboardCopyTask == nil, let clipboardHistory, !plainText || entry.plainText != nil else { return }
        clipboardCopyVersion += 1
        let version = clipboardCopyVersion
        clipboardCopyTask = Task {
            defer {
                if clipboardCopyVersion == version { clipboardCopyTask = nil }
            }
            do {
                try await clipboardHistory.copy(entry, plainText: plainText)
                guard !Task.isCancelled else { return }
                dismiss()
            } catch {
                guard !Task.isCancelled else { return }
                state.errorMessage = "Cockpit could not copy this item: \(error.localizedDescription)"
            }
        }
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
        guard !state.isSearching, let selectedResult = state.selectedResult else { return }

        do {
            switch selectedResult {
            case .clipboardHistory:
                guard clipboardHistory?.isEnabled == true else { return }
                state = LauncherState(context: .clipboard, isVisible: true)
                refreshClipboardResults(preservingSelection: false)
                return
            case let .clipboardEntry(entry):
                copyClipboardEntry(entry, plainText: false)
                return
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
        guard !state.isSearching, let selectedResult = state.selectedResult else { return }

        do {
            switch selectedResult {
            case let .application(application): try revealer.reveal(application)
            case .systemSettingsPane: return
            case let .file(file): try fileRevealer.reveal(file)
            case let .clipboardEntry(entry):
                copyClipboardEntry(entry, plainText: true)
                return
            case .systemAction, .calculation, .clipboardHistory: return
            }
            dismiss()
        } catch {
            state.errorMessage = "Cockpit could not reveal \(selectedResult.label): \(error.localizedDescription)"
        }
    }
}
