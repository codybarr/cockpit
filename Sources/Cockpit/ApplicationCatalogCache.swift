import Foundation

/// Serves a stable application snapshot to the Launcher while catalog refreshes happen off the main thread.
final class ApplicationCatalogCache: ApplicationCataloging, @unchecked Sendable {
    private let catalog: any ApplicationCataloging
    private let lock = NSLock()
    private let events: any FileSystemEventSource
    private var applications: [ApplicationCandidate] = []

    init(catalog: any ApplicationCataloging = ApplicationCatalog(), roots: [URL] = ApplicationCatalog.standardRoots, events: any FileSystemEventSource = MacOSFileSystemEvents()) {
        self.catalog = catalog
        self.events = events
        events.startWatching(paths: roots) { [weak self] changes in
            guard !changes.isEmpty else { return }
            do {
                try self?.refresh()
            } catch {
                NSLog("Cockpit could not refresh its application catalog: %@", error.localizedDescription)
            }
        }
    }

    deinit { events.stopWatching() }

    func scan() throws -> [ApplicationCandidate] {
        lock.withLock { applications }
    }

    func refresh() throws {
        let scannedApplications = try catalog.scan()
        lock.withLock { applications = scannedApplications }
    }

    func refreshInBackground() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try self?.refresh()
            } catch {
                NSLog("Cockpit could not refresh its application catalog: %@", error.localizedDescription)
            }
        }
    }
}
