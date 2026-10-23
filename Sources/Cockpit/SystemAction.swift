import Darwin
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
final class MacOSScreenLocker: ScreenLocking {
    func lockScreen() throws {
        // Deliberate private-API exception: avoids synthetic input and Accessibility consent.
        // Resolve at runtime so an OS change fails this action rather than preventing launch.
        let library = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        guard let handle = dlopen(library, RTLD_NOW | RTLD_LOCAL) else {
            throw ScreenLockError.unavailable
        }
        defer { dlclose(handle) }
        guard let address = dlsym(handle, "SACLockScreenImmediate") else {
            throw ScreenLockError.unavailable
        }
        typealias LockFunction = @convention(c) () -> Int32
        let lock = unsafeBitCast(address, to: LockFunction.self)
        let status = lock()
        guard status == 0 else { throw ScreenLockError.failed(status) }
    }

    private enum ScreenLockError: LocalizedError {
        case unavailable
        case failed(Int32)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "Screen locking is unavailable on this macOS version."
            case let .failed(status):
                "macOS could not lock the screen (error \(status))."
            }
        }
    }
}

@MainActor
final class MacOSSystemActionExecutor: SystemActionExecuting {
    private let screenLocker: any ScreenLocking

    init(screenLocker: any ScreenLocking = MacOSScreenLocker()) {
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
