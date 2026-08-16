import Foundation

struct SystemSettingsPane: Equatable, Sendable, Identifiable {
    let name: String
    let identifier: String

    var id: String { identifier }
    var destinationURL: URL { URL(string: "x-apple.systempreferences:\(identifier)")! }

    var icon: SystemSettingsPaneIcon {
        switch identifier {
        case "com.apple.SystemProfiler.AboutExtension": .init(symbolName: "info.circle.fill", color: .gray)
        case "com.apple.Accessibility-Settings.extension": .init(symbolName: "accessibility", color: .blue)
        case "com.apple.Appearance-Settings.extension": .init(symbolName: "circle.lefthalf.filled", color: .gray)
        case "com.apple.systempreferences.AppleIDSettings": .init(symbolName: "person.crop.circle.fill", color: .gray)
        case "com.apple.Battery-Settings.extension": .init(symbolName: "battery.100percent", color: .green)
        case "com.apple.BluetoothSettings": .init(symbolName: "antenna.radiowaves.left.and.right", color: .blue, resourcePath: "/System/Library/PrivateFrameworks/CoreBluetoothUI.framework/Versions/A/Resources/Bluetooth.icns")
        case "com.apple.CD-DVD-Settings.extension": .init(symbolName: "opticaldisc.fill", color: .gray)
        case "com.apple.ControlCenter-Settings.extension": .init(symbolName: "switch.2", color: .gray)
        case "com.apple.Desktop-Settings.extension": .init(symbolName: "dock.rectangle", color: .gray)
        case "com.apple.Displays-Settings.extension": .init(symbolName: "sun.max.fill", color: .blue)
        case "com.apple.Family-Settings.extension", "com.apple.Users-Groups-Settings.extension": .init(symbolName: "person.2.fill", color: .blue)
        case "com.apple.Focus-Settings.extension": .init(symbolName: "moon.fill", color: .indigo)
        case "com.apple.Game-Center-Settings.extension", "com.apple.Game-Controller-Settings.extension": .init(symbolName: "gamecontroller.fill", color: .gray)
        case "com.apple.systempreferences.GeneralSettings": .init(symbolName: "gearshape.fill", color: .gray)
        case "com.apple.Internet-Accounts-Settings.extension": .init(symbolName: "at", color: .blue)
        case "com.apple.Keyboard-Settings.extension": .init(symbolName: "keyboard", color: .blue)
        case "com.apple.Lock-Screen-Settings.extension": .init(symbolName: "lock.fill", color: .gray)
        case "com.apple.LoginItems-Settings.extension": .init(symbolName: "person.badge.key.fill", color: .gray)
        case "com.apple.Mouse-Settings.extension": .init(symbolName: "computermouse.fill", color: .gray)
        case "com.apple.Network-Settings.extension": .init(symbolName: "globe", color: .blue)
        case "com.apple.Notifications-Settings.extension": .init(symbolName: "bell.badge.fill", color: .red)
        case "com.apple.Passwords-Settings.extension": .init(symbolName: "key.fill", color: .gray)
        case "com.apple.settings.PrivacySecurity.extension": .init(symbolName: "hand.raised.fill", color: .blue)
        case "com.apple.Print-Scan-Settings.extension": .init(symbolName: "printer.fill", color: .gray)
        case "com.apple.Screen-Time-Settings.extension": .init(symbolName: "hourglass", color: .indigo)
        case "com.apple.Siri-Settings.extension": .init(symbolName: "sparkles", color: .indigo)
        case "com.apple.Sound-Settings.extension": .init(symbolName: "speaker.wave.3.fill", color: .red)
        case "com.apple.Spotlight-Settings.extension": .init(symbolName: "magnifyingglass", color: .blue)
        case "com.apple.Touch-ID-Settings.extension": .init(symbolName: "touchid", color: .red)
        case "com.apple.Trackpad-Settings.extension": .init(symbolName: "rectangle.and.hand.point.up.left.fill", color: .gray)
        case "com.apple.WalletSettingsExtension": .init(symbolName: "wallet.pass.fill", color: .gray)
        case "com.apple.Wallpaper-Settings.extension": .init(symbolName: "atom", color: .cyan)
        case "com.apple.wifi-settings-extension": .init(symbolName: "wifi", color: .blue)
        default: .init(symbolName: "gearshape.fill", color: .gray)
        }
    }
}

struct SystemSettingsPaneIcon: Sendable {
    enum Color: Sendable { case blue, cyan, green, gray, indigo, red }

    let symbolName: String
    let color: Color
    let resourcePath: String?

    init(symbolName: String, color: Color, resourcePath: String? = nil) {
        self.symbolName = symbolName
        self.color = color
        self.resourcePath = resourcePath
    }
}

protocol SystemSettingsPaneCataloging {
    func panes() -> [SystemSettingsPane]
}

/// Provides destinations that use System Settings' public URL scheme.
struct SystemSettingsPaneCatalog: SystemSettingsPaneCataloging {
    private let fileManager: FileManager
    private let systemSettingsURL: URL

    init(
        fileManager: FileManager = .default,
        systemSettingsURL: URL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
    ) {
        self.fileManager = fileManager
        self.systemSettingsURL = systemSettingsURL
    }

    func panes() -> [SystemSettingsPane] {
        guard fileManager.fileExists(atPath: systemSettingsURL.path) else { return [] }
        let availableIdentifiers = declaredDestinationIdentifiers()
        return Self.supportedPanes.filter { availableIdentifiers.contains($0.identifier) }
    }

    /// Reads System Settings' own sidebar and General subpane declarations instead of exposing
    /// destinations absent from the current macOS installation.
    private func declaredDestinationIdentifiers() -> Set<String> {
        let resources = systemSettingsURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let generalSettingsInfo = systemSettingsURL.appending(path: "Contents/PlugIns/GeneralSettings.appex/Contents/Info.plist")
        return [resources.appending(path: "Sidebar.plist"), generalSettingsInfo].reduce(into: []) { identifiers, url in
            guard let data = try? Data(contentsOf: url),
                  let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return }
            collectStrings(in: propertyList, into: &identifiers)
        }
    }

    private func collectStrings(in value: Any, into strings: inout Set<String>) {
        switch value {
        case let string as String:
            strings.insert(string)
        case let array as [Any]:
            array.forEach { collectStrings(in: $0, into: &strings) }
        case let dictionary as [String: Any]:
            dictionary.values.forEach { collectStrings(in: $0, into: &strings) }
        default:
            break
        }
    }

    // These are System Settings' stable, public URL-scheme destinations on macOS 13+. 
    static let supportedPanes = [
        SystemSettingsPane(name: "About", identifier: "com.apple.SystemProfiler.AboutExtension"),
        SystemSettingsPane(name: "Accessibility", identifier: "com.apple.Accessibility-Settings.extension"),
        SystemSettingsPane(name: "Appearance", identifier: "com.apple.Appearance-Settings.extension"),
        SystemSettingsPane(name: "Apple Account", identifier: "com.apple.systempreferences.AppleIDSettings"),
        SystemSettingsPane(name: "Battery", identifier: "com.apple.Battery-Settings.extension"),
        SystemSettingsPane(name: "Bluetooth", identifier: "com.apple.BluetoothSettings"),
        SystemSettingsPane(name: "CDs & DVDs", identifier: "com.apple.CD-DVD-Settings.extension"),
        SystemSettingsPane(name: "Control Center", identifier: "com.apple.ControlCenter-Settings.extension"),
        SystemSettingsPane(name: "Desktop & Dock", identifier: "com.apple.Desktop-Settings.extension"),
        SystemSettingsPane(name: "Displays", identifier: "com.apple.Displays-Settings.extension"),
        SystemSettingsPane(name: "Family", identifier: "com.apple.Family-Settings.extension"),
        SystemSettingsPane(name: "Focus", identifier: "com.apple.Focus-Settings.extension"),
        SystemSettingsPane(name: "Game Center", identifier: "com.apple.Game-Center-Settings.extension"),
        SystemSettingsPane(name: "Game Controllers", identifier: "com.apple.Game-Controller-Settings.extension"),
        SystemSettingsPane(name: "General", identifier: "com.apple.systempreferences.GeneralSettings"),
        SystemSettingsPane(name: "Internet Accounts", identifier: "com.apple.Internet-Accounts-Settings.extension"),
        SystemSettingsPane(name: "Keyboard", identifier: "com.apple.Keyboard-Settings.extension"),
        SystemSettingsPane(name: "Lock Screen", identifier: "com.apple.Lock-Screen-Settings.extension"),
        SystemSettingsPane(name: "Login Items & Extensions", identifier: "com.apple.LoginItems-Settings.extension"),
        SystemSettingsPane(name: "Mouse", identifier: "com.apple.Mouse-Settings.extension"),
        SystemSettingsPane(name: "Network", identifier: "com.apple.Network-Settings.extension"),
        SystemSettingsPane(name: "Notifications", identifier: "com.apple.Notifications-Settings.extension"),
        SystemSettingsPane(name: "Passwords", identifier: "com.apple.Passwords-Settings.extension"),
        SystemSettingsPane(name: "Privacy & Security", identifier: "com.apple.settings.PrivacySecurity.extension"),
        SystemSettingsPane(name: "Printers & Scanners", identifier: "com.apple.Print-Scan-Settings.extension"),
        SystemSettingsPane(name: "Screen Time", identifier: "com.apple.Screen-Time-Settings.extension"),
        SystemSettingsPane(name: "Siri", identifier: "com.apple.Siri-Settings.extension"),
        SystemSettingsPane(name: "Sound", identifier: "com.apple.Sound-Settings.extension"),
        SystemSettingsPane(name: "Spotlight", identifier: "com.apple.Spotlight-Settings.extension"),
        SystemSettingsPane(name: "Touch ID & Password", identifier: "com.apple.Touch-ID-Settings.extension"),
        SystemSettingsPane(name: "Trackpad", identifier: "com.apple.Trackpad-Settings.extension"),
        SystemSettingsPane(name: "Users & Groups", identifier: "com.apple.Users-Groups-Settings.extension"),
        SystemSettingsPane(name: "Wallet & Apple Pay", identifier: "com.apple.WalletSettingsExtension"),
        SystemSettingsPane(name: "Wallpaper", identifier: "com.apple.Wallpaper-Settings.extension"),
        SystemSettingsPane(name: "Wi-Fi", identifier: "com.apple.wifi-settings-extension"),
    ]
}

extension SystemSettingsPane: LauncherSearchable {
    var searchLabel: String { name }
}
