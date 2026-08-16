import Foundation

protocol ApplicationCataloging {
    func scan() throws -> [ApplicationCandidate]
}

@MainActor
protocol ApplicationLaunching: AnyObject {
    func launch(_ application: ApplicationCandidate) throws
}

struct LauncherState: Equatable {
    var isVisible = false
    var results: [ApplicationCandidate] = []
    var selectedIndex: Int?
    var errorMessage: String?

    var selectedResult: ApplicationCandidate? {
        guard let selectedIndex, results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }
}

@MainActor
final class LauncherController {
    private let catalog: any ApplicationCataloging
    private let launcher: any ApplicationLaunching
    private(set) var state = LauncherState()

    init(catalog: any ApplicationCataloging, launcher: any ApplicationLaunching) {
        self.catalog = catalog
        self.launcher = launcher
    }

    func invoke() {
        do {
            let applications = try catalog.scan()
            state = LauncherState(
                isVisible: true,
                results: applications,
                selectedIndex: applications.isEmpty ? nil : 0
            )
        } catch {
            state = LauncherState(isVisible: true, errorMessage: "Cockpit could not load applications: \(error.localizedDescription)")
        }
    }

    func selectResult(at index: Int) {
        guard state.results.indices.contains(index) else { return }
        state.selectedIndex = index
    }

    func executeSelectedResult() {
        guard let selectedResult = state.selectedResult else { return }

        do {
            try launcher.launch(selectedResult)
            state.isVisible = false
            state.errorMessage = nil
        } catch {
            state.errorMessage = "Cockpit could not open \(selectedResult.name): \(error.localizedDescription)"
        }
    }
}
