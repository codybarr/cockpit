import Carbon.HIToolbox
import Foundation
import SwiftUI

enum LauncherHotkey: String, CaseIterable, Equatable, Identifiable {
    case controlSpace
    case optionSpace
    case commandSpace

    var id: Self { self }

    var title: String {
        switch self {
        case .controlSpace: "Ctrl+Space"
        case .optionSpace: "Alt+Space"
        case .commandSpace: "Cmd+Space"
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .controlSpace: UInt32(controlKey)
        case .optionSpace: UInt32(optionKey)
        case .commandSpace: UInt32(cmdKey)
        }
    }
}

@MainActor
final class LauncherHotkeySettings: ObservableObject {
    static let storageKey = "launcherHotkey"

    @Published private(set) var selectedHotkey: LauncherHotkey

    private let defaults: UserDefaults
    private let apply: (LauncherHotkey) -> Bool

    init(defaults: UserDefaults = .standard, apply: @escaping (LauncherHotkey) -> Bool = { _ in true }) {
        self.defaults = defaults
        self.apply = apply
        selectedHotkey = defaults.string(forKey: Self.storageKey)
            .flatMap(LauncherHotkey.init(rawValue:)) ?? .optionSpace
    }

    func select(_ hotkey: LauncherHotkey) {
        guard hotkey != selectedHotkey, apply(hotkey) else { return }
        defaults.set(hotkey.rawValue, forKey: Self.storageKey)
        selectedHotkey = hotkey
    }
}

struct LauncherHotkeyPicker: View {
    @ObservedObject var settings: LauncherHotkeySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Launcher hotkey")
                .font(.title2.weight(.semibold))
            Text("Choose the shortcut that opens Cockpit.")
                .foregroundStyle(.secondary)
            Picker("Launcher hotkey", selection: Binding(
                get: { settings.selectedHotkey },
                set: { settings.select($0) }
            )) {
                ForEach(LauncherHotkey.allCases) { hotkey in
                    Text(hotkey.title).tag(hotkey)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
        }
    }
}
