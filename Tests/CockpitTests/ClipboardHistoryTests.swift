import AppKit
import XCTest
@testable import Cockpit

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    func testExternalDuplicatesMoveNewestButReplayDoesNotReorderOrDuplicate() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let history = ClipboardHistory(directory: root, pasteboard: pasteboard, monitorsAutomatically: false)
        await history.load()
        history.setEnabled(true)
        write("A", to: pasteboard)
        await history.capture()
        let originalID = try XCTUnwrap(history.entries.first?.id)
        write("B", to: pasteboard)
        await history.capture()
        write("A", to: pasteboard)
        await history.capture()
        XCTAssertEqual(history.entries.map(\.plainText), ["A", "B"])
        XCTAssertEqual(history.entries.first?.id, originalID)

        try await history.copy(try XCTUnwrap(history.entries.last), plainText: false)
        await history.capture()
        XCTAssertEqual(pasteboard.string(forType: .string), "B")
        XCTAssertEqual(history.entries.map(\.plainText), ["A", "B"])
    }

    func testHistoryIsBoundedAndSurvivesRestartWithoutCapturingOldClipboardContents() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        write("before opt-in", to: pb)
        history.setEnabled(true)
        await history.capture()
        XCTAssertTrue(history.entries.isEmpty)
        for number in 1...21 {
            write("Entry \(number)", to: pb)
            await history.capture()
        }
        XCTAssertEqual(history.entries.count, 20)
        XCTAssertEqual(history.entries.first?.plainText, "Entry 21")
        XCTAssertEqual(history.entries.last?.plainText, "Entry 2")
        write(String(repeating: "x", count: ClipboardHistory.entryByteLimit + 1), to: pb)
        await history.capture()
        XCTAssertEqual(history.entries.count, 20)
        await history.flush()
        let restored = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await restored.load()
        XCTAssertEqual(restored.entries, history.entries)
        history.setEnabled(false)
        await history.clear()
        let cleared = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await cleared.load()
        XCTAssertTrue(cleared.entries.isEmpty)
    }

    func testSensitiveCopiesAreIgnoredIncludingDuringThePendingCopyDrain() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        history.setEnabled(true)
        write("kept", to: pb)
        await history.capture()
        write("secret", to: pb)
        pb.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        try await history.copy(try XCTUnwrap(history.entries.first), plainText: false)
        XCTAssertEqual(history.entries.map(\.plainText), ["kept"])
        write("pending", to: pb)
        try await history.copy(try XCTUnwrap(history.entries.first), plainText: false)
        XCTAssertEqual(history.entries.map(\.plainText), ["pending", "kept"])
    }

    func testFileBatchesReplayFilesOrPlainPathsWithoutOwningTheOriginals() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = [root.appending(path: "a.txt"), root.appending(path: "b.txt")]
        for file in files { try Data("contents".utf8).write(to: file) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        // Override volatile roots: this fixture deliberately lives in a temporary directory.
        let history = ClipboardHistory(directory: root.appending(path: "history"), pasteboard: pb, monitorsAutomatically: false, volatileRoots: [])
        await history.load()
        history.setEnabled(true)
        pb.clearContents()
        pb.writeObjects(files.map { $0 as NSURL })
        await history.capture()
        let entry = try XCTUnwrap(history.entries.first)
        XCTAssertEqual(entry.content, .files(files))
        try await history.copy(entry, plainText: false)
        XCTAssertEqual(pb.pasteboardItems?.count, 2)
        XCTAssertEqual(pb.pasteboardItems?.first?.string(forType: .fileURL), files[0].absoluteString)
        XCTAssertEqual(pb.string(forType: .string), files.map(\.path).joined(separator: "\n"))
        try await history.copy(entry, plainText: true)
        XCTAssertEqual(pb.string(forType: .string), files.map(\.path).joined(separator: "\n"))
        XCTAssertFalse(pb.types?.contains(.fileURL) ?? false)
        await history.clear()
        XCTAssertTrue(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testImagesAreCapturedAsImagesAndReplayDoesNotBecomeText() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        history.setEnabled(true)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        pb.clearContents()
        pb.setData(png, forType: .png)
        await history.capture()
        let entry = try XCTUnwrap(history.entries.first)
        guard case let .image(_, width, height, thumbnail) = entry.content else { return XCTFail("Expected an image") }
        XCTAssertEqual(width, 4)
        XCTAssertEqual(height, 3)
        XCTAssertNotNil(NSImage(data: thumbnail))
        XCTAssertNil(entry.plainText)
        pb.clearContents()
        pb.setData(png, forType: .png)
        await history.capture()
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.id, entry.id)
        try await history.copy(entry, plainText: false)
        XCTAssertNotNil(pb.data(forType: .png))
        XCTAssertNil(pb.string(forType: .string))
        await history.capture()
        XCTAssertEqual(history.entries.count, 1)
        await history.flush()
        let restored = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await restored.load()
        XCTAssertEqual(restored.entries, history.entries)
        await history.clear()
        write("do not overwrite", to: pb)
        do {
            try await history.copy(entry, plainText: false)
            XCTFail("A stale selection must not replay a cleared image")
        } catch {}
        XCTAssertEqual(pb.string(forType: .string), "do not overwrite")
    }

    func testByteBudgetEvictsOldestAndClearCannotBeUndoneByInFlightCapture() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        history.setEnabled(true)
        for number in 1...6 {
            write(String(repeating: "\(number)", count: ClipboardHistory.entryByteLimit - 2) + "é", to: pb)
            await history.capture()
        }
        XCTAssertEqual(history.entries.count, 5)
        XCTAssertEqual(history.entries.last?.plainText?.first, "2")
        XCTAssertEqual(history.entries.reduce(0) { $0 + $1.payloadSize }, 25 * 1_024 * 1_024)
        await history.flush()
        let fullArchive = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await fullArchive.load()
        XCTAssertNil(fullArchive.errorMessage)
        XCTAssertEqual(fullArchive.entries.map(\.id), history.entries.map(\.id))
        XCTAssertEqual(fullArchive.entries.first?.plainText?.suffix(1), "é")
        write("in flight", to: pb)
        let capture = Task { await history.capture() }
        await Task.yield()
        await history.clear()
        await capture.value
        XCTAssertTrue(history.entries.isEmpty)
        let restored = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await restored.load()
        XCTAssertTrue(restored.entries.isEmpty)
    }

    func testMissingFileDoesNotOverwriteClipboardAndCorruptStoreNeedsExplicitClear() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        history.setEnabled(true)
        write("leave this alone", to: pb)
        let file = root.appending(path: "missing.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: file)
        let files = ClipboardHistory(directory: root.appending(path: "file-history"), pasteboard: pb, monitorsAutomatically: false, volatileRoots: [])
        await files.load()
        files.setEnabled(true)
        pb.clearContents()
        pb.writeObjects([file as NSURL])
        await files.capture()
        let missing = try XCTUnwrap(files.entries.first)
        try FileManager.default.removeItem(at: file)
        write("leave this alone", to: pb)
        do {
            try await files.copy(missing, plainText: false)
            XCTFail("A missing file must fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "A referenced file is no longer available.")
        }
        XCTAssertEqual(pb.string(forType: .string), "leave this alone")
        await history.clear()
        try Data("not a valid archive".utf8).write(to: root.appending(path: "history.plist"))
        let broken = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await broken.load()
        XCTAssertNotNil(broken.errorMessage)
        broken.setEnabled(true)
        XCTAssertFalse(broken.isEnabled)
        await broken.clear()
        XCTAssertNil(broken.errorMessage)
        broken.setEnabled(true)
        XCTAssertTrue(broken.isEnabled)
    }

    func testClearDoesNotModifyTheSystemClipboardAndDisableDoesNotCaptureMissedCopies() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        history.setEnabled(true)
        write("recorded", to: pb)
        await history.capture()
        history.setEnabled(false)
        write("while disabled", to: pb)
        await history.clear()
        XCTAssertEqual(pb.string(forType: .string), "while disabled")
        history.setEnabled(true)
        await history.capture()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testVolatileFileReferencesUseInlineImagesRatherThanFinderDisplayNames() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        history.setEnabled(true)
        let item = NSPasteboardItem()
        item.setString("file:///tmp/export.png", forType: .fileURL)
        item.setString("export.png", forType: .string)
        pb.clearContents()
        pb.writeObjects([item])
        await history.capture()
        XCTAssertTrue(history.entries.isEmpty, "A transient file's display name isn't useful inline content")
    }

    func testOptInPreferencePersistsAndSearchUsesOriginalTextAndPathsOnly() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suiteName = "CockpitClipboardTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: root, pasteboard: pb, defaults: defaults, monitorsAutomatically: false)
        await history.load()
        XCTAssertFalse(history.isEnabled)
        history.setEnabled(true)
        write("  Résumé\nfull original text\n", to: pb)
        await history.capture()
        let matches = await history.search("resume")
        XCTAssertEqual(matches.first?.plainText, "  Résumé\nfull original text\n")
        await history.shutDown()
        let restored = ClipboardHistory(directory: root, pasteboard: pb, defaults: defaults, monitorsAutomatically: false)
        await restored.load()
        XCTAssertTrue(restored.isEnabled)
        XCTAssertEqual(restored.entries, history.entries)
    }

    func testSensitiveMarkerOnAnyFileInABatchSuppressesTheEntireCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false, volatileRoots: [])
        await history.load()
        history.setEnabled(true)
        let items = [NSPasteboardItem(), NSPasteboardItem()]
        for (index, item) in items.enumerated() {
            item.setString("file:///Users/example/file-\(index).txt", forType: .fileURL)
        }
        items[1].setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pb.clearContents()
        pb.writeObjects(items)
        await history.capture()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testPersistenceFailureIsVisibleAndDoesNotDiscardTheSessionHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        // Simulate the storage directory becoming unavailable after a successful load.
        try Data().write(to: root)
        history.setEnabled(true)
        write("still available", to: pb)
        await history.capture()
        await history.flush()
        XCTAssertEqual(history.entries.first?.plainText, "still available")
        XCTAssertNotNil(history.errorMessage)
    }

    func testAutomaticMonitorStartsOnOptInAndStopsWhenDisabled() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: root, pasteboard: pb)
        await history.load()
        history.setEnabled(true)
        defer { history.setEnabled(false) }
        write("automatic", to: pb)
        for _ in 0..<60 where history.entries.isEmpty { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(history.entries.first?.plainText, "automatic")
        history.setEnabled(false)
        write("not recorded", to: pb)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(history.entries.map(\.plainText), ["automatic"])
        await history.flush()
    }

    func testStartupAndClearSweepUncommittedArchive() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pending = root.appending(path: "history.pending")
        try Data("uncommitted capture".utf8).write(to: pending)
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let history = ClipboardHistory(directory: root, pasteboard: pb, monitorsAutomatically: false)
        await history.load()
        XCTAssertNil(history.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        try Data("abandoned capture".utf8).write(to: pending)
        await history.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        XCTAssertTrue(history.entries.isEmpty)
    }

    private func write(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
