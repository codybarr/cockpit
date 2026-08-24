import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
@MainActor
final class CockpitApp: NSObject, NSApplicationDelegate {
    private let workspaceLauncher = WorkspaceApplicationLauncher()
    private let calculationCopier = PasteboardCalculationCopier()
    private let systemActionExecutor = MacOSSystemActionExecutor()
    private let loginItemSettings = LoginItemSettings()
    private lazy var launcherHotkeySettings = LauncherHotkeySettings { [weak self] hotkey in
        self?.registerLauncherHotkey(hotkey) ?? false
    }
    private let applicationCatalog = ApplicationCatalogCache()
    private let applicationUseTracker = PersistentApplicationUseTracker()
    private lazy var filenameIndex = try! FilenameIndex(databaseURL: Self.filenameIndexURL)
    private lazy var launcherController = LauncherController(
        catalog: applicationCatalog,
        launcher: workspaceLauncher,
        revealer: workspaceLauncher,
        systemSettingsPaneLauncher: workspaceLauncher,
        systemActionExecutor: systemActionExecutor,
        filenameIndex: filenameIndex,
        fileOpener: workspaceLauncher,
        fileRevealer: workspaceLauncher,
        calculationCopier: calculationCopier,
        useTracker: applicationUseTracker
    )
    private var panelController: LauncherPanelController!
    private var hotkey: GlobalHotkey?
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?

    private static var filenameIndexURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Cockpit/filename-index.sqlite")
    }

    static func main() {
        let application = NSApplication.shared
        let delegate = CockpitApp()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applicationCatalog.refreshInBackground()
        panelController = LauncherPanelController(controller: launcherController) { [weak self] in
            self?.showSettings()
        }
        installStatusItem()

        _ = registerLauncherHotkey(launcherHotkeySettings.selectedHotkey)
    }

    private func showLauncher() {
        if panelController.isActive {
            panelController.hide()
            return
        }

        launcherController.invoke()
        panelController.present()
    }

    private func registerLauncherHotkey(_ hotkey: LauncherHotkey) -> Bool {
        do {
            self.hotkey = try GlobalHotkey(keyCode: UInt32(kVK_Space), modifiers: hotkey.modifiers) { [weak self] in
                self?.showLauncher()
            }
            return true
        } catch {
            NSLog("Cockpit could not register its global hotkey: %@", error.localizedDescription)
            return false
        }
    }

    private func installStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let imageURL = Bundle.main.url(forResource: "CockpitMenuBarTemplate", withExtension: "png"),
           let image = NSImage(contentsOf: imageURL) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            image.accessibilityDescription = "Cockpit"
            statusItem.button?.image = image
        } else {
            NSLog("Cockpit menu-bar icon is missing from the app bundle.")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Cockpit", action: #selector(showCockpitFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Cockpit", action: #selector(quitCockpit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    @objc private func showCockpitFromMenu() {
        showLauncher()
    }

    @objc private func showSettings() {
        panelController.hide()

        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                index: filenameIndex,
                hotkeySettings: launcherHotkeySettings,
                loginItemSettings: loginItemSettings
            )
        }
        settingsWindowController?.show()
    }

    @objc private func quitCockpit() {
        NSApp.terminate(nil)
    }
}

@MainActor
final class WorkspaceApplicationLauncher: ApplicationLaunching, ApplicationRevealing, SystemSettingsPaneLaunching, FileOpening, FileRevealing {
    func launch(_ application: ApplicationCandidate) throws {
        guard NSWorkspace.shared.open(application.url) else {
            throw ApplicationError.unavailable
        }
    }

    func reveal(_ application: ApplicationCandidate) throws {
        try revealURL(application.url)
    }

    func launch(_ pane: SystemSettingsPane) throws {
        guard FileManager.default.fileExists(atPath: "/System/Applications/System Settings.app"),
              NSWorkspace.shared.open(pane.destinationURL) else {
            throw ApplicationError.unavailable
        }
    }

    func open(_ file: FilenameCandidate) throws {
        guard NSWorkspace.shared.open(file.url) else { throw ApplicationError.unavailable }
    }

    func reveal(_ file: FilenameCandidate) throws {
        try revealURL(file.url)
    }

    private func revealURL(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ApplicationError.unavailable }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private enum ApplicationError: LocalizedError {
        case unavailable

        var errorDescription: String? { "The application is no longer available." }
    }
}

@MainActor
final class PasteboardCalculationCopier: CalculationCopying {
    func copy(_ calculation: Calculation) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(calculation.value, forType: .string) else {
            throw CopyError.unavailable
        }
    }

    private enum CopyError: LocalizedError {
        case unavailable

        var errorDescription: String? { "The clipboard is unavailable." }
    }
}

@MainActor
private final class LauncherPanelController {
    private let controller: LauncherController
    private let panel: LauncherPanel
    private let showSettings: () -> Void
    private var stateObserver: Any?
    private var pendingResize: DispatchWorkItem?

    init(controller: LauncherController, showSettings: @escaping () -> Void) {
        self.controller = controller
        self.showSettings = showSettings
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 76),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.controller = self
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: LauncherView(controller: controller))
        stateObserver = controller.$state.sink { [weak self] _ in
            self?.scheduleResize()
        }
    }

    var isActive: Bool { panel.isKeyWindow }

    func present() {
        resize(for: controller.state, preservingTopEdge: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    fileprivate func showSettingsPanel() {
        showSettings()
    }

    fileprivate func moveSelection(by offset: Int) {
        controller.moveSelection(by: offset)
    }

    fileprivate func startFilenameSearch(replacingExistingQuery: Bool = false) -> Bool {
        controller.startFilenameSearch(replacingExistingQuery: replacingExistingQuery)
    }

    fileprivate func setRevealHintVisible(_ isVisible: Bool) {
        controller.setRevealHintVisible(isVisible)
    }

    fileprivate func executeSelection() {
        controller.executeSelectedResult()
        if !controller.state.isVisible { panel.orderOut(nil) }
    }

    fileprivate func revealSelection() {
        controller.revealSelectedResult()
        if !controller.state.isVisible { panel.orderOut(nil) }
    }

    fileprivate func hide() {
        controller.dismiss()
        panel.orderOut(nil)
    }

    private func scheduleResize() {
        pendingResize?.cancel()
        let resize = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.resize(for: self.controller.state)
        }
        pendingResize = resize
        DispatchQueue.main.async(execute: resize)
    }

    private func resize(for state: LauncherState, preservingTopEdge: Bool = true) {
        let contentHeight = state.contentHeight

        // Selection changes do not affect the launcher's dimensions. Avoid resetting the
        // panel frame for them, as even an identical AppKit frame update can cause a
        // perceptible one-pixel redraw shift.
        if preservingTopEdge, panel.isVisible, panel.contentView?.bounds.height == contentHeight {
            return
        }

        let oldFrame = panel.frame
        let frame = NSRect(x: oldFrame.minX, y: oldFrame.maxY - contentHeight, width: 680, height: contentHeight)
        if preservingTopEdge, panel.isVisible {
            panel.setFrame(frame, display: true, animate: false)
        } else {
            panel.setContentSize(frame.size)
            panel.center()
        }
    }
}

struct LauncherKeypress {
    enum Action: Equatable {
        case showSettings
        case copy
        case cut
        case paste
        case passThrough
    }

    let action: Action

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        if modifierFlags.contains(.command) {
            switch keyCode {
            case UInt16(kVK_ANSI_Comma): action = .showSettings
            case UInt16(kVK_ANSI_C): action = .copy
            case UInt16(kVK_ANSI_X): action = .cut
            case UInt16(kVK_ANSI_V): action = .paste
            default: action = .passThrough
            }
        } else {
            action = .passThrough
        }
    }
}

private final class LauncherPanel: NSPanel {
    weak var controller: LauncherPanelController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            controller?.setRevealHintVisible(event.modifierFlags.contains(.command))
            return
        }

        guard event.type == .keyDown else {
            super.sendEvent(event)
            return
        }

        switch LauncherKeypress(keyCode: event.keyCode, modifierFlags: event.modifierFlags).action {
        case .showSettings:
            controller?.showSettingsPanel()
            return
        case .copy:
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
            return
        case .cut:
            NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
            return
        case .paste:
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            return
        case .passThrough:
            break
        }

        switch event.keyCode {
        case UInt16(kVK_Space):
            if hasFullySelectedLaunchpadText {
                _ = controller?.startFilenameSearch(replacingExistingQuery: true)
                return
            }
            if controller?.startFilenameSearch() == true { return }
        case UInt16(kVK_ANSI_A) where event.modifierFlags.contains(.command):
            NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: self)
        case UInt16(kVK_Return) where event.modifierFlags.contains(.command): controller?.revealSelection()
        case UInt16(kVK_Return): controller?.executeSelection()
        case UInt16(kVK_UpArrow): controller?.moveSelection(by: -1)
        case UInt16(kVK_DownArrow): controller?.moveSelection(by: 1)
        case UInt16(kVK_Escape): controller?.hide()
        default: super.sendEvent(event)
        }
    }

    private var hasFullySelectedLaunchpadText: Bool {
        guard let editor = firstResponder as? NSTextView else { return false }
        let selection = editor.selectedRange()
        return !editor.string.isEmpty
            && selection.location == 0
            && selection.length == (editor.string as NSString).length
    }
}

private struct LauncherView: View {
    @ObservedObject var controller: LauncherController
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("", text: Binding(
                get: { controller.state.query },
                set: { query in controller.updateQuery(query) }
            ))
            .focused($isQueryFocused)
            .textFieldStyle(.plain)
            .font(.system(size: 42, weight: .regular))
            .foregroundStyle(.white)
            .padding(14)
            .frame(height: 76)

            if let errorMessage = controller.state.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(.horizontal, 20)
                    .frame(height: 48)
            } else if !controller.state.query.isEmpty && controller.state.results.isEmpty {
                Text("No matching results found.")
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 20)
                    .frame(height: 48)
            } else if !controller.state.results.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(controller.state.results.enumerated()), id: \.element.id) { index, result in
                                LauncherResultRow(
                                    result: result,
                                    isSelected: controller.state.selectedIndex == index,
                                    isRevealHintVisible: controller.state.isRevealHintVisible
                                ) {
                                    controller.selectResult(at: index)
                                }
                                .simultaneousGesture(TapGesture(count: 2).onEnded(controller.executeSelectedResult))
                                .id(result.id)
                            }
                        }
                        .padding(2)
                    }
                    .onChange(of: controller.state.selectedIndex) { _ in
                        guard let selectedResult = controller.state.selectedResult else { return }
                        proxy.scrollTo(selectedResult.id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.10, green: 0.11, blue: 0.12))
        .onAppear { isQueryFocused = true }
    }
}

private struct LauncherResultRow: View {
    let result: LauncherResult
    let isSelected: Bool
    let isRevealHintVisible: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 16) {
                resultIcon
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.label).font(.system(size: 20, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.56))
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 60)
            .background {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color(red: 0.19, green: 0.40, blue: 0.55))
                    .opacity(isSelected ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resultIcon: some View {
        switch result {
        case let .application(application):
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                .resizable()
        case let .systemSettingsPane(pane):
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                if let resourcePath = pane.icon.resourcePath, let image = NSImage(contentsOfFile: resourcePath) {
                    Image(nsImage: image)
                        .resizable()
                        .padding(4)
                } else {
                    Image(systemName: pane.icon.symbolName)
                        .font(.system(size: 23, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(paneIconColor(pane.icon.color))
                }
            }
        case let .file(file):
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
        case let .systemAction(action):
            Image(systemName: action.symbolName)
                .font(.system(size: 26))
        case .calculation:
            Image(systemName: "plus.forwardslash.minus")
                .font(.system(size: 24))
        }
    }

    private func paneIconColor(_ color: SystemSettingsPaneIcon.Color) -> Color {
        switch color {
        case .blue: .blue
        case .cyan: .cyan
        case .green: .green
        case .gray: .gray
        case .indigo: .indigo
        case .red: .red
        }
    }

    private var subtitle: String {
        switch result {
        case let .application(application):
            isRevealHintVisible ? "Reveal file in Finder" : application.url.path
        case .systemSettingsPane:
            "System Settings"
        case let .file(file):
            isRevealHintVisible ? "Reveal file in Finder" : file.url.path
        case .systemAction:
            "System action"
        case .calculation:
            "Copy result"
        }
    }
}

private final class GlobalHotkey {
    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) throws {
        self.action = action
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        var handler: EventHandlerRef?
        let eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        guard InstallEventHandler(GetEventDispatcherTarget(), globalHotkeyHandler, 1, [eventType], pointer, &handler) == noErr,
              let handler else { throw GlobalHotkeyError.handlerRegistrationFailed }
        handlerRef = handler

        let hotkeyID = EventHotKeyID(signature: OSType(0x434F4B50), id: 1)
        guard RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetEventDispatcherTarget(), 0, &hotkeyRef) == noErr else {
            RemoveEventHandler(handler)
            handlerRef = nil
            throw GlobalHotkeyError.hotkeyRegistrationFailed
        }
    }

    deinit {
        if let hotkeyRef { UnregisterEventHotKey(hotkeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    fileprivate func fire() {
        Task { @MainActor [action] in action() }
    }

    private enum GlobalHotkeyError: LocalizedError {
        case handlerRegistrationFailed
        case hotkeyRegistrationFailed

        var errorDescription: String? { "Cockpit’s global hotkey could not be registered." }
    }
}

private func globalHotkeyHandler(_ nextHandler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue().fire()
    return noErr
}
