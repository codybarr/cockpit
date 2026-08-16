import CoreServices
import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct FilenameCandidate: Equatable, Sendable, Identifiable {
    let url: URL

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

protocol FilenameIndexing: AnyObject {
    var indexedFolders: [URL] { get }
    func addIndexedFolder(_ folder: URL) throws
    func removeIndexedFolder(_ folder: URL) throws
    func matches(for query: String) throws -> [FilenameCandidate]
}

extension FilenameCandidate: LauncherSearchable {
    var searchLabel: String { name }
}

final class FilenameIndex: FilenameIndexing {
    private var database: OpaquePointer?
    private var eventStreams: [String: FSEventStreamRef] = [:]
    private let fileManager: FileManager

    var indexedFolders: [URL] {
        (try? queryStrings("SELECT path FROM indexed_folders ORDER BY path")).map { $0.map(URL.init(fileURLWithPath:)) } ?? []
    }

    init(databaseURL: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
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
        for folder in indexedFolders { startWatching(folder) }
    }

    deinit {
        eventStreams.values.forEach(stopWatching)
        sqlite3_close(database)
    }

    func addIndexedFolder(_ folder: URL) throws {
        let folder = canonicalFolderURL(folder)
        guard fileManager.fileExists(atPath: folder.path) else { throw IndexError.folderUnavailable(folder) }

        try transaction {
            try execute("INSERT OR IGNORE INTO indexed_folders(path) VALUES (?)", bindings: [folder.path])
            try execute("DELETE FROM filenames WHERE folder_path = ?", bindings: [folder.path])
            try indexContents(of: folder)
        }
        startWatching(folder)
    }

    func removeIndexedFolder(_ folder: URL) throws {
        let folder = canonicalFolderURL(folder)
        stopWatching(folder)
        try execute("DELETE FROM filenames WHERE folder_path = ?", bindings: [folder.path])
        try execute("DELETE FROM indexed_folders WHERE path = ?", bindings: [folder.path])
    }

    func matches(for query: String) throws -> [FilenameCandidate] {
        let pattern = "%\(query.replacing("\\", with: "\\\\").replacing("%", with: "\\%").replacing("_", with: "\\_"))%"
        return try queryStrings(
            "SELECT path FROM filenames WHERE filename LIKE ? ESCAPE '\\' ORDER BY path",
            bindings: [pattern]
        ).map(URL.init(fileURLWithPath:))
            .map(FilenameCandidate.init(url:))
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
        guard fileManager.fileExists(atPath: folder.path) else { return }
        do {
            try transaction {
                try execute("DELETE FROM filenames WHERE folder_path = ?", bindings: [folder.path])
                try indexContents(of: folder)
            }
        } catch {
            NSLog("Cockpit could not refresh filename index for %@: %@", folder.path, error.localizedDescription)
        }
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

    private func startWatching(_ folder: URL) {
        guard eventStreams[folder.path] == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let stream = FSEventStreamCreate(
            nil,
            filenameIndexEvents,
            &context,
            [folder.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        eventStreams[folder.path] = stream
    }

    private func stopWatching(_ folder: URL) {
        guard let stream = eventStreams.removeValue(forKey: folder.path) else { return }
        stopWatching(stream)
    }

    private func stopWatching(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamSetDispatchQueue(stream, nil)
        FSEventStreamRelease(stream)
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
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

private func filenameIndexEvents(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ eventCount: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let index = Unmanaged<FilenameIndex>.fromOpaque(info).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
    let changedFolders = Set(paths.compactMap { path in
        index.indexedFolders.first { folder in
            path == folder.path || path.hasPrefix(folder.path + "/")
        }
    })
    changedFolders.forEach(index.refresh)
}
