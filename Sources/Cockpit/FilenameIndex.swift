import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct FilenameCandidate: Equatable, Sendable, Identifiable {
    let url: URL

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

enum IndexedFolderState: Equatable {
    case available
    case unavailable
}

protocol FilenameIndexing: AnyObject {
    var indexedFolders: [URL] { get }
    func folderState(for folder: URL) -> IndexedFolderState
    func addIndexedFolder(_ folder: URL) throws
    func removeIndexedFolder(_ folder: URL) throws
    func retry(folder: URL) throws
    func matches(for query: String) throws -> [FilenameCandidate]
}

extension FilenameCandidate: LauncherSearchable {
    var searchLabel: String { name }
}

final class FilenameIndex: FilenameIndexing, @unchecked Sendable {
    private var database: OpaquePointer?
    private let fileManager: FileManager
    private let events: any FileSystemEventSource
    private let snapshotLock = NSLock()
    private let databaseLock = NSLock()
    private var filenames: [FilenameCandidate] = []
    private var unavailableFolders: Set<String> = []

    var indexedFolders: [URL] {
        (try? queryStrings("SELECT path FROM indexed_folders ORDER BY path")).map { $0.map(URL.init(fileURLWithPath:)) } ?? []
    }

    init(databaseURL: URL, fileManager: FileManager = .default, events: any FileSystemEventSource = MacOSFileSystemEvents()) throws {
        self.fileManager = fileManager
        self.events = events
        try fileManager.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw IndexError.couldNotOpenDatabase
        }
        try execute("CREATE TABLE IF NOT EXISTS indexed_folders (path TEXT PRIMARY KEY NOT NULL)")
        try execute("""
            CREATE TABLE IF NOT EXISTS filenames (
                path TEXT PRIMARY KEY NOT NULL,
                folder_path TEXT NOT NULL REFERENCES indexed_folders(path) ON DELETE CASCADE,
                filename TEXT NOT NULL
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS filenames_filename ON filenames(filename)")
        try rebuildSnapshot()
        startWatching()
        reconcilePersistedFoldersInBackground()
    }

    deinit {
        events.stopWatching()
        sqlite3_close(database)
    }

    func folderState(for folder: URL) -> IndexedFolderState {
        let folder = canonicalFolderURL(folder)
        return snapshotLock.withLock { unavailableFolders.contains(folder.path) || !fileManager.fileExists(atPath: folder.path) ? .unavailable : .available }
    }

    func retry(folder: URL) throws {
        let folder = canonicalFolderURL(folder)
        guard fileManager.fileExists(atPath: folder.path) else { throw IndexError.folderUnavailable(folder) }
        try reconcile(folder)
        _ = snapshotLock.withLock { unavailableFolders.remove(folder.path) }
    }

    func addIndexedFolder(_ folder: URL) throws {
        let folder = canonicalFolderURL(folder)
        guard fileManager.fileExists(atPath: folder.path) else { throw IndexError.folderUnavailable(folder) }

        try transaction {
            try execute("INSERT OR IGNORE INTO indexed_folders(path) VALUES (?)", bindings: [folder.path])
            try execute("DELETE FROM filenames WHERE folder_path = ?", bindings: [folder.path])
            try indexContents(of: folder)
        }
        try rebuildSnapshot()
        _ = snapshotLock.withLock { unavailableFolders.remove(folder.path) }
        startWatching()
    }

    func removeIndexedFolder(_ folder: URL) throws {
        let folder = canonicalFolderURL(folder)
        try transaction {
            try execute("DELETE FROM filenames WHERE folder_path = ?", bindings: [folder.path])
            try execute("DELETE FROM indexed_folders WHERE path = ?", bindings: [folder.path])
        }
        try rebuildSnapshot()
        _ = snapshotLock.withLock { unavailableFolders.remove(folder.path) }
        startWatching()
    }

    func matches(for query: String) throws -> [FilenameCandidate] {
        snapshotLock.withLock {
            filenames.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    private func indexContents(of folder: URL) throws {
        try enumerate(folder) { file in
            try execute(
                "INSERT INTO filenames(path, folder_path, filename) VALUES (?, ?, ?)",
                bindings: [file.path, folder.path, file.lastPathComponent]
            )
        }
    }

    fileprivate func refresh(_ folder: URL) {
        do {
            try reconcile(folder)
            _ = snapshotLock.withLock { unavailableFolders.remove(folder.path) }
        } catch {
            _ = snapshotLock.withLock { unavailableFolders.insert(folder.path) }
            NSLog("Cockpit could not refresh filename index for %@: %@", folder.path, error.localizedDescription)
        }
    }

    private func reconcile(_ folder: URL) throws {
        guard fileManager.fileExists(atPath: folder.path) else { throw IndexError.folderUnavailable(folder) }
        try transaction {
            try execute("DELETE FROM filenames WHERE folder_path = ?", bindings: [folder.path])
            try indexContents(of: folder)
        }
        try rebuildSnapshot()
    }

    private func rebuildSnapshot() throws {
        let candidates = try queryStrings("SELECT path FROM filenames ORDER BY path").map(URL.init(fileURLWithPath:)).map(FilenameCandidate.init(url:))
        snapshotLock.withLock { filenames = candidates }
    }

    private func enumerate(_ folder: URL, visit: (URL) throws -> Void) throws {
        let properties: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(properties),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw IndexError.folderUnavailable(folder) }

        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: properties)
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            try visit(file)
        }
    }

    private func canonicalFolderURL(_ folder: URL) -> URL {
        folder.standardizedFileURL
    }

    private func startWatching() {
        events.startWatching(paths: indexedFolders) { [weak self] changes in
            self?.handle(changes)
        }
    }

    private func reconcilePersistedFoldersInBackground() {
        let folders = indexedFolders
        DispatchQueue.global(qos: .utility).async { [weak self, folders] in
            folders.forEach { self?.refresh($0) }
        }
    }

    private func handle(_ changes: [FileSystemEvent]) {
        let folders = indexedFolders
        let requiresReconciliation = changes.contains(.historyDropped)
        let affectedFolders = requiresReconciliation ? Set(folders) : Set(changes.compactMap { change -> URL? in
            let path: String
            switch change {
            case let .changed(url), let .rootUnavailable(url): path = url.path
            case .historyDropped: return nil
            }
            return folders.first { path == $0.path || path.hasPrefix($0.path + "/") }
        })
        for folder in affectedFolders { refresh(folder) }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try databaseLock.withLock {
            try execute("BEGIN IMMEDIATE")
            do {
                try body()
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    private func execute(_ statement: String, bindings: [String] = []) throws {
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(database, statement, -1, &prepared, nil) == SQLITE_OK else { throw databaseError }
        defer { sqlite3_finalize(prepared) }
        try bind(bindings, to: prepared)
        guard sqlite3_step(prepared) == SQLITE_DONE else { throw databaseError }
    }

    private func queryStrings(_ statement: String, bindings: [String] = []) throws -> [String] {
        try databaseLock.withLock {
            var prepared: OpaquePointer?
            guard sqlite3_prepare_v2(database, statement, -1, &prepared, nil) == SQLITE_OK else { throw databaseError }
            defer { sqlite3_finalize(prepared) }
            try bind(bindings, to: prepared)

            var values: [String] = []
            while sqlite3_step(prepared) == SQLITE_ROW {
                if let value = sqlite3_column_text(prepared, 0) { values.append(String(cString: value)) }
            }
            guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else { throw databaseError }
            return values
        }
    }

    private func bind(_ bindings: [String], to statement: OpaquePointer?) throws {
        for (index, value) in bindings.enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, sqliteTransient) == SQLITE_OK else { throw databaseError }
        }
    }

    private var databaseError: IndexError {
        .database(String(cString: sqlite3_errmsg(database)))
    }

    enum IndexError: LocalizedError {
        case couldNotOpenDatabase
        case folderUnavailable(URL)
        case database(String)

        var errorDescription: String? {
            switch self {
            case .couldNotOpenDatabase: "Cockpit could not open its filename index."
            case let .folderUnavailable(folder): "The indexed folder is unavailable: \(folder.path)"
            case let .database(message): "Cockpit’s filename index failed: \(message)"
            }
        }
    }
}
