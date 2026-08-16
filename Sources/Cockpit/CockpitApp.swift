import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
@MainActor
final class CockpitApp: NSObject, NSApplicationDelegate {
    private let workspaceLauncher = WorkspaceApplicationLauncher()
    private let applicationCatalog = ApplicationCatalogCache()
    private lazy var launcherController = LauncherController(
        catalog: applicationCatalog,
        launcher: workspaceLauncher,
        revealer: workspaceLauncher
    )
    private var panelController: LauncherPanelController!
    private var hotkey: GlobalHotkey?
    private var statusItem: NSStatusItem?

    static func main() {
        let application = NSApplication.shared
        let delegate = CockpitApp()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applicationCatalog.refreshInBackground()
        panelController = LauncherPanelController(controller: launcherController)
        installStatusItem()

        do {
            let hotkey = try GlobalHotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
                self?.showLauncher()
            }
            self.hotkey = hotkey
        } catch {
            NSLog("Cockpit could not register its global hotkey: %@", error.localizedDescription)
        }
    }

    private func showLauncher() {
        launcherController.invoke()
        panelController.present()
    }

    private func installStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "airplane", accessibilityDescription: "Cockpit")

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Cockpit", action: #selector(showCockpitFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Cockpit", action: #selector(quitCockpit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    @objc private func showCockpitFromMenu() {
        showLauncher()
    }

    @objc private func quitCockpit() {
        NSApp.terminate(nil)
    }
}

@MainActor
final class WorkspaceApplicationLauncher: ApplicationLaunching, ApplicationRevealing {
    func launch(_ application: ApplicationCandidate) throws {
        guard NSWorkspace.shared.open(application.url) else {
            throw ApplicationError.unavailable
        }
    }

    func reveal(_ application: ApplicationCandidate) throws {
        guard FileManager.default.fileExists(atPath: application.url.path) else {
            throw ApplicationError.unavailable
        }
        NSWorkspace.shared.activateFileViewerSelecting([application.url])
    }

    private enum ApplicationError: LocalizedError {
        case unavailable

        var errorDescription: String? { "The application is no longer available." }
    }
}

@MainActor
private final class LauncherPanelController {
    private let controller: LauncherController
    private let panel: LauncherPanel
    private var stateObserver: Any?

    init(controller: LauncherController) {
        self.controller = controller
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
        stateObserver = controller.$state.sink { [weak self] state in
            self?.resize(for: state)
        }
    }

    func present() {
        resize(for: controller.state, preservingTopEdge: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    fileprivate func moveSelection(by offset: Int) {
        controller.moveSelection(by: offset)
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

    private func resize(for state: LauncherState, preservingTopEdge: Bool = true) {
        let resultCount = state.results.count
        let contentHeight: CGFloat
        if state.errorMessage != nil || (!state.query.isEmpty && resultCount == 0) {
            contentHeight = 128
        } else {
            contentHeight = 76 + min(CGFloat(resultCount) * 60 + 4, 364)
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

        switch event.keyCode {
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
                Text("No matching applications found.")
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 20)
                    .frame(height: 48)
            } else if !controller.state.results.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(controller.state.results.enumerated()), id: \.element.id) { index, application in
                                Button {
                                    controller.selectResult(at: index)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(application.name).font(.system(size: 20, weight: .medium))
                                            Text(controller.state.isRevealHintVisible ? "Reveal file in Finder" : application.url.path)
                                                .font(.system(size: 13))
                                                .foregroundStyle(.white.opacity(0.56))
                                        }
                                        Spacer()
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .frame(height: 60)
                                    .background(controller.state.selectedIndex == index ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture(count: 2).onEnded(controller.executeSelectedResult))
                                .id(application.id)
                            }
                        }
                        .padding(2)
                    }
                    .onChange(of: controller.state.selectedIndex) { _ in
                        guard let selectedResult = controller.state.selectedResult else { return }
                        proxy.scrollTo(selectedResult.id, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.10, green: 0.11, blue: 0.12))
        .onAppear { isQueryFocused = true }
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
