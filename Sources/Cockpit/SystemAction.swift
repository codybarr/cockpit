import ApplicationServices
import Foundation

enum SystemAction: String, CaseIterable, Equatable, Sendable, Identifiable {
    case lock
    case restart
    case shutDown

    var id: Self { self }

    var label: String {
        switch self {
        case .lock: "Lock"
        case .restart: "Restart"
        case .shutDown: "Shut Down"
        }
    }

    var symbolName: String {
        switch self {
        case .lock: "lock.fill"
        case .restart: "arrow.clockwise"
        case .shutDown: "power"
        }
    }

    var appleScript: String? {
        switch self {
        case .lock: nil
        case .restart: "tell application \"System Events\" to restart"
        case .shutDown: "tell application \"System Events\" to shut down"
        }
    }
}

@MainActor
protocol SystemActionExecuting: AnyObject {
    func execute(_ action: SystemAction) throws
}

@MainActor
protocol ScreenLocking: AnyObject {
    func lockScreen() throws
}

@MainActor
final class AccessibilityScreenLocker: ScreenLocking {
    func lockScreen() throws {
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else {
            throw ScreenLockError.accessibilityPermissionDenied
        }

        let source = CGEventSource(stateID: .hidSystemState)
        for isKeyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: isKeyDown) else {
                throw ScreenLockError.unavailable
            }
            event.flags = [.maskCommand, .maskControl]
            event.post(tap: .cghidEventTap)
        }
    }

    private enum ScreenLockError: LocalizedError {
        case accessibilityPermissionDenied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionDenied:
                "Cockpit needs Accessibility permission to lock the screen. Grant it in System Settings, then run Lock again."
            case .unavailable:
                "macOS could not prepare the lock shortcut."
            }
        }
    }
}

@MainActor
final class MacOSSystemActionExecutor: SystemActionExecuting {
    private let screenLocker: any ScreenLocking

    init(screenLocker: any ScreenLocking = AccessibilityScreenLocker()) {
        self.screenLocker = screenLocker
    }

    func execute(_ action: SystemAction) throws {
        if action == .lock {
            try lockScreen()
            return
        }

        guard let source = action.appleScript, let script = NSAppleScript(source: source) else {
            throw SystemActionError.unavailable
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            if error[NSAppleScript.errorNumber] as? Int == -1743 {
                throw SystemActionError.permissionDenied
            }
            throw SystemActionError.failed(error[NSAppleScript.errorMessage] as? String)
        }
    }

    private func lockScreen() throws {
        try screenLocker.lockScreen()
    }

    private enum SystemActionError: LocalizedError {
        case unavailable
        case permissionDenied
        case failed(String?)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "macOS could not prepare this System action."
            case .permissionDenied:
                "macOS denied Automation permission for this System action."
            case let .failed(message):
                message ?? "macOS could not perform this System action."
            }
        }
    }
}
