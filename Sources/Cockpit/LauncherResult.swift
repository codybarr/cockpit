import Foundation

enum LauncherResult: Equatable, Sendable, Identifiable {
    case application(ApplicationCandidate)
    case systemAction(SystemAction)

    var id: String {
        switch self {
        case let .application(application): "application:\(application.url.absoluteString)"
        case let .systemAction(action): "system-action:\(action.rawValue)"
        }
    }

    var label: String {
        switch self {
        case let .application(application): application.name
        case let .systemAction(action): action.label
        }
    }
}

protocol LauncherSearchable {
    var searchLabel: String { get }
}

extension ApplicationCandidate: LauncherSearchable {
    var searchLabel: String { name }
}

extension LauncherResult: LauncherSearchable {
    var searchLabel: String { label }
}
