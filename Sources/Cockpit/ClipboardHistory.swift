import AppKit
import Combine
import Darwin

struct ClipboardEntry: Codable, Equatable, Sendable, Identifiable {
    enum Content: Codable, Equatable, Sendable {
        case text(String)
        case image(Data, width: Int, height: Int, thumbnail: Data)
        case files([URL])

        private enum Kind: Int, Codable { case text, image, files }

        // Encode text as UTF-8 bytes. Binary property lists otherwise encode a whole
        // mostly-ASCII string as UTF-16 when it contains a single non-ASCII character,
        // potentially doubling an otherwise valid 25 MiB archive beyond its read bound.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            switch self {
            case let .text(text):
                try container.encode(Kind.text)
                try container.encode(Data(text.utf8))
            case let .image(data, width, height, thumbnail):
                try container.encode(Kind.image)
                try container.encode(data)
                try container.encode(width)
                try container.encode(height)
                try container.encode(thumbnail)
            case let .files(urls):
                try container.encode(Kind.files)
                try container.encode(urls)
            }
        }

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            switch try container.decode(Kind.self) {
            case .text:
                let bytes = try container.decode(Data.self)
                guard let text = String(data: bytes, encoding: .utf8) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid clipboard text encoding")
                }
                self = .text(text)
            case .image:
                self = try .image(container.decode(Data.self), width: container.decode(Int.self),
                                  height: container.decode(Int.self), thumbnail: container.decode(Data.self))
            case .files:
                self = try .files(container.decode([URL].self))
            }
            guard container.isAtEnd else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unexpected clipboard data")
            }
        }
    }

    let id: UUID
    let content: Content

    init(id: UUID = UUID(), content: Content) {
        self.id = id
        self.content = content
    }

    var plainText: String? {
        switch content {
        case let .text(text): text
        case let .files(urls): urls.map(\.path).joined(separator: "\n")
        case .image: nil
        }
    }

    var isFileBatch: Bool {
        if case .files = content { return true }
        return false
    }

    var label: String {
        switch content {
        case let .text(text):
            // Never walk or lay out an entire large clipboard entry just to draw its row.
            String(decoding: text.utf8.prefix(512), as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(String.init) ?? "Text"
        case let .files(urls):
            (urls.first?.lastPathComponent ?? "Files") + (urls.count > 1 ? " (+\(urls.count - 1))" : "")
        case .image: "Image"
        }
    }

    var detail: String {
        switch content {
        case .text: "Copy text"
        case let .image(_, width, height, _): "\(width) × \(height) · Copy image"
        case let .files(urls): urls.count == 1 ? (urls.first?.path ?? "") : "\(urls.count) files · Copy files"
        }
    }

    var payloadSize: Int {
        switch content {
        case let .text(text): text.utf8.count
        case let .image(data, _, _, thumbnail): data.count + thumbnail.count
        case let .files(urls): urls.reduce(0) { $0 + $1.absoluteString.utf8.count }
        }
    }
}

/// Owns the small resident history. All disk/image work is delegated off the main actor.
@MainActor
final class ClipboardHistory: ObservableObject {
    nonisolated static let entryLimit = 20
    nonisolated static let byteLimit = 25 * 1_024 * 1_024
    nonisolated static let entryByteLimit = 5 * 1_024 * 1_024
    static let replayType = NSPasteboard.PasteboardType("com.cockpit.clipboard-history-replay")

    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var isEnabled = false
    @Published private(set) var errorMessage: String?
    private let pasteboard: NSPasteboard
    private let store: ClipboardStore
    private let defaults: UserDefaults?
    private let monitorsAutomatically: Bool
    private var timer: Timer?
    private var observedCount: Int
    private var generation = 0
    private var persistenceTask: Task<Void, Never>?
    private var pendingSave: [ClipboardEntry]?
    @Published private(set) var isLoaded = false
    private var captureTask: Task<Void, Never>?
    private let volatileRoots: [URL]

    init(directory: URL, pasteboard: NSPasteboard = .general, defaults: UserDefaults? = nil, monitorsAutomatically: Bool = true, volatileRoots: [URL] = ClipboardPasteboard.volatileRoots) {
        self.pasteboard = pasteboard
        self.store = ClipboardStore(directory: directory)
        self.defaults = defaults
        self.monitorsAutomatically = monitorsAutomatically
        self.volatileRoots = volatileRoots
        self.observedCount = pasteboard.changeCount
    }

    func load() async {
        guard !isLoaded else { return }
        let token = generation
        do {
            let loaded = try await store.load()
            guard token == generation else { return }
            entries = loaded
            isLoaded = true
            setEnabled(defaults?.bool(forKey: "clipboardHistoryEnabled") ?? false)
        } catch {
            guard token == generation else { return }
            errorMessage = "Clipboard history could not be loaded. Clear History in Settings to reset it."
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isLoaded else { return }
        generation += 1
        isEnabled = enabled
        defaults?.set(isEnabled, forKey: "clipboardHistoryEnabled")
        observedCount = pasteboard.changeCount
        timer?.invalidate()
        timer = nil
        if isEnabled && monitorsAutomatically {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.capture() }
            }
            timer?.tolerance = 0.1
        }
    }

    func capture() async {
        if let pending = captureTask {
            await pending.value
            return
        }
        guard isEnabled, observedCount != pasteboard.changeCount else { return }
        let count = pasteboard.changeCount
        observedCount = count
        guard let raw = ClipboardPasteboard.read(pasteboard, volatileRoots: volatileRoots),
              count == pasteboard.changeCount else { return }
        let token = generation
        let task = Task {
            let entry = await Task.detached(priority: .utility) {
                ClipboardContentPreparation.prepare(raw)
            }.value
            guard isEnabled, token == generation, let entry else { return }
            record(entry)
        }
        captureTask = task
        await task.value
        captureTask = nil
    }

    func copy(_ entry: ClipboardEntry, plainText: Bool) async throws {
        guard isEnabled, !Task.isCancelled, entries.contains(where: { $0.id == entry.id }),
              !plainText || entry.plainText != nil else { throw ClipboardError.unavailable }
        let token = generation
        let filesExist = await Task.detached(priority: .userInitiated) {
            ClipboardContentPreparation.validateFiles(in: entry)
        }.value
        guard filesExist else { throw ClipboardError.missingFiles }
        // Drain a pending copy before replacing it. If another application keeps writing,
        // fail rather than overwrite a change we haven't observed.
        for _ in 0..<3 {
            await capture()
            guard isEnabled, token == generation, !Task.isCancelled else { throw ClipboardError.unavailable }
            if observedCount == pasteboard.changeCount { break }
        }
        guard observedCount == pasteboard.changeCount else { throw ClipboardError.busy }
        try ClipboardPasteboard.write(entry, plainText: plainText, to: pasteboard)
        // Let the monitor observe our marked write rather than blindly adopting the
        // current count here: a different app might already have replaced it.
    }

    func search(_ query: String) async -> [ClipboardEntry] {
        let snapshot = entries
        guard !query.isEmpty else { return snapshot }
        let task = Task.detached(priority: .userInitiated) {
            snapshot.filter { entry in
                guard !Task.isCancelled else { return false }
                return entry.plainText?.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func clear() async {
        generation += 1
        observedCount = pasteboard.changeCount
        entries = []
        isLoaded = true
        persist()
        await persistenceTask?.value
    }

    func flush() async { await persistenceTask?.value }

    func shutDown() async {
        timer?.invalidate()
        timer = nil
        await capture()
        await flush()
    }

    private func record(_ entry: ClipboardEntry) {
        guard entry.payloadSize <= Self.entryByteLimit else { return }
        let existing = entries.first { $0.content == entry.content }
        entries.removeAll { $0.content == entry.content }
        entries.insert(existing ?? entry, at: 0)
        while entries.count > Self.entryLimit || entries.reduce(0, { $0 + $1.payloadSize }) > Self.byteLimit {
            entries.removeLast()
        }
        persist()
    }

    private func persist() {
        // Keep at most one in-flight write and one latest snapshot, rather than accumulating
        // an unbounded chain of 25 MiB archives if the disk is slow.
        pendingSave = entries
        guard persistenceTask == nil else { return }
        persistenceTask = Task {
            while let snapshot = pendingSave {
                pendingSave = nil
                do {
                    try await store.save(snapshot)
                    errorMessage = nil
                } catch {
                    errorMessage = "Clipboard history could not be saved. Check available disk space and access in Settings."
                }
            }
            persistenceTask = nil
        }
    }

    enum ClipboardError: LocalizedError {
        case unavailable, missingFiles, busy
        var errorDescription: String? {
            switch self {
            case .unavailable: "The clipboard item could not be copied."
            case .missingFiles: "A referenced file is no longer available."
            case .busy: "The clipboard is changing. Please try again."
            }
        }
    }
}

/// A single bounded archive avoids loose image ownership and clear/prune races entirely.
/// Actor serialization keeps filesystem work off the UI thread.
private actor ClipboardStore {
    private struct Archive: Codable {
        let version: Int
        let entries: [ClipboardEntry]
    }
    private let directory: URL
    private var fileURL: URL { directory.appending(path: "history.plist") }
    private var pendingURL: URL { directory.appending(path: "history.pending") }

    init(directory: URL) { self.directory = directory }

    func load() throws -> [ClipboardEntry] {
        try removePendingArchive()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let values = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink == false, values.isRegularFile == true else { throw CocoaError(.fileReadCorruptFile) }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let maximumSize = ClipboardHistory.byteLimit + 1_024 * 1_024
        let data = try handle.read(upToCount: maximumSize + 1) ?? Data()
        guard data.count <= maximumSize else { throw CocoaError(.fileReadCorruptFile) }
        let archive = try PropertyListDecoder().decode(Archive.self, from: data)
        guard archive.version == 1, archive.entries.count <= ClipboardHistory.entryLimit,
              archive.entries.allSatisfy({ $0.payloadSize <= ClipboardHistory.entryByteLimit }),
              archive.entries.reduce(0, { $0 + $1.payloadSize }) <= ClipboardHistory.byteLimit else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard Set(archive.entries.map(\.id)).count == archive.entries.count else { throw CocoaError(.fileReadCorruptFile) }
        // Never trust persisted image dimensions or thumbnails. Rebuild the bounded tile
        // from validated image data before it reaches an AppKit row.
        return try archive.entries.map { entry in
            switch entry.content {
            case let .text(text):
                guard !text.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                return entry
            case let .files(urls):
                guard !urls.isEmpty, urls.count <= 100, urls.allSatisfy({ $0.isFileURL }) else { throw CocoaError(.fileReadCorruptFile) }
                return entry
            case let .image(data, _, _, _):
                guard let validated = ClipboardContentPreparation.prepare(.image(data)) else { throw CocoaError(.fileReadCorruptFile) }
                return ClipboardEntry(id: entry.id, content: validated.content)
            }
        }
    }

    func save(_ entries: [ClipboardEntry]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(Archive(version: 1, entries: entries))
        // A known staging path can be swept after a crash and by Clear History.
        // Never leave clipboard bytes in Foundation-generated, untracked temporary files.
        try removePendingArchive()
        defer { try? removePendingArchive() }
        try data.write(to: pendingURL, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pendingURL.path)
        guard rename(pendingURL.path, fileURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func removePendingArchive() throws {
        do {
            try FileManager.default.removeItem(at: pendingURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            // Nothing was staged, or a prior rename already committed it.
        }
    }
}
