import Foundation

enum LauncherResult: Equatable, Sendable, Identifiable {
    case application(ApplicationCandidate)
    case file(FilenameCandidate)
    case systemAction(SystemAction)

    var id: String {
        switch self {
        case let .application(application): "application:\(application.url.absoluteString)"
        case let .file(file): "file:\(file.url.absoluteString)"
        case let .systemAction(action): "system-action:\(action.rawValue)"
        }
    }

    var label: String {
        switch self {
        case let .application(application): application.name
        case let .file(file): file.name
        case let .systemAction(action): action.label
        }
    }
}

protocol LauncherSearchable {
    var searchLabel: String { get }
    var normalizedSearchLabel: String { get }
}

extension LauncherSearchable {
    var normalizedSearchLabel: String { SearchNormalizer.normalize(searchLabel) }
}

enum SearchNormalizer {
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

extension ApplicationCandidate: LauncherSearchable {
    var searchLabel: String { name }
    var normalizedSearchLabel: String { normalizedName }
}

extension LauncherResult: LauncherSearchable {
    var searchLabel: String { label }

    var normalizedSearchLabel: String {
        switch self {
        case let .application(application): application.normalizedName
        case let .file(file): file.normalizedName
        case .systemAction: SearchNormalizer.normalize(label)
        }
    }

}
