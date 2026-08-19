import Combine
import Foundation
import ServiceManagement

enum LoginItemStatus: Equatable {
    case disabled
    case enabled
    case approvalRequired
    case unavailable

}

@MainActor
protocol LoginItemManaging: AnyObject {
    var status: LoginItemStatus { get }
    func enable() throws
    func disable() throws
}

@MainActor
final class MainAppLoginItemService: LoginItemManaging {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .approvalRequired
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func enable() throws {
        try SMAppService.mainApp.register()
    }

    func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
final class LoginItemSettings: ObservableObject {
    private let service: any LoginItemManaging
    @Published private(set) var status: LoginItemStatus

    init(service: any LoginItemManaging = MainAppLoginItemService()) {
        self.service = service
        status = service.status
    }

    func refresh() {
        status = service.status
    }

    func setEnabled(_ isEnabled: Bool) throws {
        refresh()
        switch (status, isEnabled) {
        case (.disabled, true): try service.enable()
        case (.enabled, false): try service.disable()
        case (.unavailable, _): throw LoginItemError.unavailable
        case (.approvalRequired, _), (.disabled, false), (.enabled, true): break
        }
        status = service.status
    }

    private enum LoginItemError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Launch at Login is unavailable in this build. Install a signed Cockpit release to enable it."
        }
    }
}
