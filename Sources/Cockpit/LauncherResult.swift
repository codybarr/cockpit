import Foundation

enum LauncherResult: Equatable, Sendable, Identifiable {
    case application(ApplicationCandidate)
    case systemSettingsPane(SystemSettingsPane)
    case file(FilenameCandidate)
    case systemAction(SystemAction)
    case calculation(Calculation)
    case clipboardHistory
    case clipboardEntry(ClipboardEntry)

    var id: String {
        switch self {
        case let .application(application): "application:\(application.url.absoluteString)"
        case let .systemSettingsPane(pane): "system-settings-pane:\(pane.identifier)"
        case let .file(file): "file:\(file.url.absoluteString)"
        case let .systemAction(action): "system-action:\(action.rawValue)"
        case let .calculation(calculation): "calculation:\(calculation.value)"
        case .clipboardHistory: "clipboard-history"
        case let .clipboardEntry(entry): "clipboard-entry:\(entry.id)"
        }
    }

    var label: String {
        switch self {
        case let .application(application): application.name
        case let .systemSettingsPane(pane): pane.name
        case let .file(file): file.name
        case let .systemAction(action): action.label
        case let .calculation(calculation): calculation.value
        case .clipboardHistory: "Clipboard History"
        case let .clipboardEntry(entry): entry.label
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
        case let .systemSettingsPane(pane): pane.normalizedSearchLabel
        case let .file(file): file.normalizedName
        case .systemAction, .calculation, .clipboardHistory, .clipboardEntry: SearchNormalizer.normalize(label)
        }
    }

}
