import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
@MainActor
final class CockpitApp: NSObject, NSApplicationDelegate {
    private let launcherController = LauncherController(
        catalog: ApplicationCatalog(),
        launcher: WorkspaceApplicationLauncher()
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
final class WorkspaceApplicationLauncher: ApplicationLaunching {
    func launch(_ application: ApplicationCandidate) throws {
        guard NSWorkspace.shared.open(application.url) else {
            throw ApplicationLaunchError.unavailable
        }
    }

    private enum ApplicationLaunchError: LocalizedError {
        case unavailable

        var errorDescription: String? { "The application is no longer available." }
    }
}

@MainActor
private final class LauncherPanelController {
    private let controller: LauncherController
    private let panel: LauncherPanel

    init(controller: LauncherController) {
        self.controller = controller
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 430),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.controller = self
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: LauncherView(state: controller.state, select: { _ in }, execute: {}))
    }

    func present() {
        render()
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    fileprivate func selectResult(at index: Int) {
        controller.selectResult(at: index)
        render()
    }

    fileprivate func moveSelection(by offset: Int) {
        controller.moveSelection(by: offset)
        render()
    }

    fileprivate func executeSelection() {
        controller.executeSelectedResult()
        if controller.state.isVisible {
            render()
        } else {
            panel.orderOut(nil)
        }
    }

    fileprivate func hide() {
        panel.orderOut(nil)
    }

    private func render() {
        panel.contentView = NSHostingView(rootView: LauncherView(
            state: controller.state,
            select: { [weak self] index in self?.selectResult(at: index) },
            execute: { [weak self] in self?.executeSelection() }
        ))
    }
}

private final class LauncherPanel: NSPanel {
    weak var controller: LauncherPanelController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else {
            super.sendEvent(event)
            return
        }

        switch event.keyCode {
        case UInt16(kVK_Return): controller?.executeSelection()
        case UInt16(kVK_UpArrow): controller?.moveSelection(by: -1)
        case UInt16(kVK_DownArrow): controller?.moveSelection(by: 1)
        case UInt16(kVK_Escape): controller?.hide()
        default: super.sendEvent(event)
        }
    }
}

private struct LauncherView: View {
    let state: LauncherState
    let select: (Int) -> Void
    let execute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cockpit")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 28)
                .padding(.vertical, 19)

            if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(28)
            } else if state.results.isEmpty {
                Text("No applications found in the standard application folders.")
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(28)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(state.results.enumerated()), id: \.element.id) { index, application in
                                Button {
                                    select(index)
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(application.name).font(.system(size: 17, weight: .medium))
                                            Text(application.url.path).font(.system(size: 12)).foregroundStyle(.white.opacity(0.56))
                                        }
                                        Spacer()
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(state.selectedIndex == index ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture(count: 2).onEnded(execute))
                                .id(application.id)
                            }
                        }
                        .padding(10)
                    }
                    .onAppear { scrollToSelection(using: proxy) }
                    .onChange(of: state.selectedIndex) { _ in scrollToSelection(using: proxy) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.10, green: 0.11, blue: 0.12))
    }

    private func scrollToSelection(using proxy: ScrollViewProxy) {
        guard let selectedResult = state.selectedResult else { return }
        proxy.scrollTo(selectedResult.id, anchor: .center)
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
