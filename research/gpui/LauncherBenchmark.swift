// Disposable research harness. Not a proposed production feature.
import AppKit
import Carbon.HIToolbox
import SwiftUI
import os

@MainActor
enum LauncherBenchmark {
    static let enabled = ProcessInfo.processInfo.environment["COCKPIT_UI_BENCHMARK"] == "1"
    static let cacheIcons = ProcessInfo.processInfo.environment["COCKPIT_CACHE_ICONS"] == "1"
    static let log = OSLog(subsystem: "com.codybarr.Cockpit.Research", category: .pointsOfInterest)
    static var launchStart: UInt64 = 0
    static var probe: Probe?
    static var rows: [String] = []
    static var icons: [String: NSImage] = [:]

    static func icon(for path: String) -> NSImage {
        guard cacheIcons else { return NSWorkspace.shared.icon(forFile: path) }
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }

    static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    static func ms(_ value: UInt64, since start: UInt64) -> Double {
        Double(value - start) / 1_000_000
    }

    struct VisualState: Equatable {
        let query: String
        let selected: Int?
        let count: Int
        let visible: Bool
        init(_ state: LauncherState) {
            query = state.query; selected = state.selectedIndex
            count = state.results.count; visible = state.isVisible
        }
    }

    @MainActor
    final class Probe {
        let operation: String
        let start = now()
        let signpostID = OSSignpostID(log: log)
        var dispatched: UInt64?
        var controllerStart: UInt64?
        var controllerEnd: UInt64?
        var expected: VisualState?
        var graph: UInt64?
        var drawn: UInt64?
        init(_ operation: String) {
            self.operation = operation
            os_signpost(.begin, log: log, name: "Research interaction", signpostID: signpostID, "%{public}s", operation)
        }
        func finish() {
            os_signpost(.end, log: log, name: "Research interaction", signpostID: signpostID)
        }
    }

    static func observedController(_ state: LauncherState) {
        guard let probe else { return }
        probe.controllerEnd = now()
        probe.expected = VisualState(state)
    }

    static func run() {
        launchStart = now()
        let app = NSApplication.shared
        let delegate = BenchmarkDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

struct BenchmarkDrawMarker: NSViewRepresentable {
    let state: LauncherBenchmark.VisualState
    func makeNSView(context: Context) -> BenchmarkMarkerView { BenchmarkMarkerView() }
    func updateNSView(_ view: BenchmarkMarkerView, context: Context) {
        view.state = state
        if let probe = LauncherBenchmark.probe, probe.expected == state {
            if probe.graph == nil { probe.graph = LauncherBenchmark.now() }
            view.needsDisplay = true
        }
    }
}

final class BenchmarkMarkerView: NSView {
    var state: LauncherBenchmark.VisualState?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        // No pixels added. This callback is CPU draw observation, NOT presentation.
        guard let probe = LauncherBenchmark.probe,
              let state, probe.expected == state, probe.graph != nil else { return }
        if probe.drawn == nil { probe.drawn = LauncherBenchmark.now() }
    }
}

@MainActor
private final class BenchmarkDelegate: NSObject, NSApplicationDelegate {
    private var panelController: LauncherPanelController?
    private var controller: LauncherController?
    private var index: FilenameIndex?
    private let environment = ProcessInfo.processInfo.environment

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await exercise() }
            catch {
                fputs("RESEARCH_UI_ERROR: \(error)\n", stderr)
                // Preserve a failure artifact instead of passing silently.
                if let output = environment["COCKPIT_UI_OUTPUT"] {
                    try? String(describing: error).write(toFile: output + ".error", atomically: true, encoding: .utf8)
                }
            }
            NSApp.terminate(nil)
        }
    }

    private func exercise() async throws {
        let root = URL(fileURLWithPath: environment["COCKPIT_UI_FIXTURE"]!, isDirectory: true)
        let database = URL(fileURLWithPath: environment["COCKPIT_UI_DATABASE"]!)
        let index = try FilenameIndex(databaseURL: database)
        self.index = index
        if index.indexedFolders.isEmpty { try index.addIndexedFolder(root) }
        let workspace = WorkspaceApplicationLauncher()
        let controller = LauncherController(
            catalog: BenchmarkCatalog(), launcher: workspace, revealer: workspace,
            systemSettingsPaneCatalog: BenchmarkPaneCatalog(), systemSettingsPaneLauncher: workspace,
            systemActionExecutor: MacOSSystemActionExecutor(), filenameIndex: index,
            fileOpener: workspace, fileRevealer: workspace, calculationCopier: PasteboardCalculationCopier()
        )
        self.controller = controller
        let panelController = LauncherPanelController(controller: controller, showSettings: {})
        self.panelController = panelController
        let mode = CGDisplayCopyDisplayMode(CGMainDisplayID())
        var metadata: [String: Any] = [
            "cache_icons": LauncherBenchmark.cacheIcons,
            "thermal_state": ProcessInfo.processInfo.thermalState.rawValue,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "display_nominal_hz": mode?.refreshRate ?? 0,
            "display_pixel_width": mode?.pixelWidth ?? 0,
            "display_pixel_height": mode?.pixelHeight ?? 0,
            "background_indexing": environment["COCKPIT_UI_BACKGROUND"] == "1",
            "endpoint": "matching-state NSView draw callback; not screen presentation"
        ]
        let output = environment["COCKPIT_UI_OUTPUT"]!
        controller.invoke(); panelController.present()
        try await pause(500)
        try ready(panelController)
        metadata["main_to_fixture_ready_ms"] = LauncherBenchmark.ms(LauncherBenchmark.now(), since: LauncherBenchmark.launchStart)
        metadata["initial_index_files"] = try FileManager.default.contentsOfDirectory(atPath: root.path).count
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: output + ".metadata.json"))
        try await pause(Int(environment["COCKPIT_UI_IDLE_MS"] ?? "0")!)

        // Setup and initial scan are outside interaction timing. Optional real FSEvents load.
        let writer: Task<Void, Never>? = environment["COCKPIT_UI_BACKGROUND"] == "1" ? Task.detached {
            for i in 0..<120 {
                if Task.isCancelled { return }
                try? Data("\(i)".utf8).write(to: root.appendingPathComponent("Background Report.txt"))
                try? await Task.sleep(for: .milliseconds(500))
            }
        } : nil
        defer { writer?.cancel() }
        let count = Int(environment["COCKPIT_UI_CYCLES"] ?? "20")!
        var sample = 0
        // Each key goes through NSApplication's own event queue; no CGEvent posting or consent.
        for cycle in 0..<count {
            panelController.hide()
            try await pause(35)
            try await measure("invoke", sample: sample, cycle: cycle) {
                controller.invoke()
                panelController.present()
                LauncherBenchmark.observedController(controller.state)
            }
            sample += 1
            try ready(panelController)
            for query in ["safari", "'report", "'zzznomatch"] {
                // Select-all is untimed; first character replaces the previous query.
                guard let editor = panelController.panel.firstResponder as? NSTextView else {
                    throw BenchmarkError("Launchpad editor lost focus")
                }
                editor.selectAll(nil)
                var expected = ""
                for character in query {
                    expected.append(character)
                    let wanted = expected
                    try await measure("input", sample: sample, cycle: cycle) {
                        post(panelController, key: UInt16(kVK_ANSI_A), text: String(character))
                    }
                    guard controller.state.query == wanted else {
                        throw BenchmarkError("input mismatch: expected \(wanted), got \(controller.state.query)")
                    }
                    sample += 1
                }
            }
            // Reuse the broad filename query, preserving the normal result-count cap.
            guard let editor = panelController.panel.firstResponder as? NSTextView else {
                throw BenchmarkError("Launchpad editor lost focus")
            }
            editor.selectAll(nil)
            for character in "'report" {
                post(panelController, key: UInt16(kVK_ANSI_A), text: String(character))
                try await pause(5)
            }
            try await pause(40)
            guard controller.state.query == "'report", controller.state.results.count == 100 else {
                throw BenchmarkError("broad fixture query mismatch: query=\(controller.state.query), results=\(controller.state.results.count)")
            }
            for _ in 0..<20 {
                let expected = ((controller.state.selectedIndex ?? 0) + 1) % 100
                try await measure("selection", sample: sample, cycle: cycle) {
                    post(panelController, key: UInt16(kVK_DownArrow), text: "\u{f701}")
                }
                guard controller.state.selectedIndex == expected else { throw BenchmarkError("selection mismatch") }
                sample += 1
            }
            // Native delete key and empty/no-result state.
            editor.selectAll(nil)
            try await measure("empty", sample: sample, cycle: cycle) {
                post(panelController, key: UInt16(kVK_Delete), text: "\u{7f}")
            }
            guard controller.state.query.isEmpty else { throw BenchmarkError("delete did not clear Launchpad") }
            sample += 1
        }
        panelController.hide()
        if writer != nil {
            let refreshed = try index.matches(for: "background").contains { $0.name == "Background Report.txt" }
            metadata["background_file_became_searchable"] = refreshed
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: output + ".metadata.json"))
            guard refreshed else { throw BenchmarkError("real FSEvents workload did not make its new file searchable") }
        }
        let header = "operation,sample,cycle,dispatch_ms,controller_ms,graph_ms,draw_proxy_ms,results,selected\n"
        try (header + LauncherBenchmark.rows.joined(separator: "\n") + "\n")
            .write(toFile: output, atomically: true, encoding: .utf8)
    }

    private func measure(_ operation: String, sample: Int, cycle: Int, perform: () -> Void) async throws {
        let probe = LauncherBenchmark.Probe(operation)
        LauncherBenchmark.probe = probe
        perform()
        let deadline = probe.start + 2_000_000_000
        while probe.drawn == nil {
            guard LauncherBenchmark.now() < deadline else {
                probe.finish()
                throw BenchmarkError("draw probe timeout for \(operation); graph=\(String(describing: probe.graph)), expected=\(String(describing: probe.expected))")
            }
            try await pause(1)
        }
        probe.finish()
        let controllerTime = probe.controllerStart.flatMap { begin in probe.controllerEnd.map { LauncherBenchmark.ms($0, since: begin) } }
        let dispatch = probe.dispatched.map { String(LauncherBenchmark.ms($0, since: probe.start)) } ?? ""
        let graph = probe.graph.map { String(LauncherBenchmark.ms($0, since: probe.start)) } ?? ""
        let draw = LauncherBenchmark.ms(probe.drawn!, since: probe.start)
        LauncherBenchmark.rows.append("\(operation),\(sample),\(cycle),\(dispatch),\(controllerTime.map(String.init(describing:)) ?? ""),\(graph),\(draw),\(controller!.state.results.count),\(controller!.state.selectedIndex.map(String.init) ?? "")")
        LauncherBenchmark.probe = nil
        try await pause(8)
    }

    private func ready(_ panelController: LauncherPanelController) throws {
        guard panelController.panel.isKeyWindow, panelController.panel.firstResponder is NSTextView else {
            throw BenchmarkError("Launcher not input-ready")
        }
    }

    private func post(_ panelController: LauncherPanelController, key: UInt16, text: String) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panelController.panel.windowNumber,
            context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: key)!
        NSApp.postEvent(event, atStart: false)
    }

    private func pause(_ milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}

private struct BenchmarkError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct BenchmarkCatalog: ApplicationCataloging {
    func scan() throws -> [ApplicationCandidate] {
        [ApplicationCandidate(name: "Safari", url: URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications/Safari.app")),
         ApplicationCandidate(name: "TextEdit", url: URL(fileURLWithPath: "/System/Applications/TextEdit.app")),
         ApplicationCatalog.finder]
    }
}
private struct BenchmarkPaneCatalog: SystemSettingsPaneCataloging {
    func panes() -> [SystemSettingsPane] { [] }
}
