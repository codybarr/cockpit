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
protocol SystemProcessRunning: AnyObject {
    func start(executableURL: URL, arguments: [String]) throws
}

@MainActor
final class FoundationSystemProcessRunner: SystemProcessRunning {
    private var runningProcesses: [Process] = []

    func start(executableURL: URL, arguments: [String]) throws {
        runningProcesses.removeAll { !$0.isRunning }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()
        runningProcesses.append(process)
    }
}

@MainActor
final class MacOSSystemActionExecutor: SystemActionExecuting {
    private let processRunner: any SystemProcessRunning

    init(processRunner: any SystemProcessRunning = FoundationSystemProcessRunner()) {
        self.processRunner = processRunner
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
        try processRunner.start(
            executableURL: URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine"),
            arguments: ["-background"]
        )
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
