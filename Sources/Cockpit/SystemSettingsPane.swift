import Foundation

struct SystemSettingsPane: Equatable, Sendable, Identifiable {
    let name: String
    let identifier: String
    var iconBundlePath: String? = nil

    var id: String { identifier }
    var destinationURL: URL { URL(string: "x-apple.systempreferences:\(identifier)")! }

    var icon: SystemSettingsPaneIcon {
        switch identifier.split(whereSeparator: { $0 == "*" || $0 == ":" }).first.map(String.init) ?? identifier {
        case "com.apple.SystemProfiler.AboutExtension": .init(symbolName: "info.circle.fill", color: .gray)
        case "com.apple.Accessibility-Settings.extension": .init(symbolName: "accessibility", color: .blue)
        case "com.apple.Appearance-Settings.extension": .init(symbolName: "circle.lefthalf.filled", color: .gray)
        case "com.apple.systempreferences.AppleIDSettings": .init(symbolName: "person.crop.circle.fill", color: .gray)
        case "com.apple.Battery-Settings.extension": .init(symbolName: "battery.100percent", color: .green)
        case "com.apple.BluetoothSettings": .init(symbolName: "antenna.radiowaves.left.and.right", color: .blue, resourcePath: "/System/Library/PrivateFrameworks/CoreBluetoothUI.framework/Versions/A/Resources/Bluetooth.icns")
        case "com.apple.CD-DVD-Settings.extension": .init(symbolName: "opticaldisc.fill", color: .gray)
        case "com.apple.ControlCenter-Settings.extension": .init(symbolName: identifier.hasSuffix("*menubar") ? "menubar.rectangle" : "switch.2", color: .gray)
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

/// Serves a stable System Settings snapshot while the disk-backed catalog refreshes off the main thread.
final class SystemSettingsPaneCache: SystemSettingsPaneCataloging, @unchecked Sendable {
    private let catalog: any SystemSettingsPaneCataloging
    private let lock = NSLock()
    private var availablePanes: [SystemSettingsPane] = []

    init(catalog: any SystemSettingsPaneCataloging = SystemSettingsPaneCatalog()) {
        self.catalog = catalog
    }

    func panes() -> [SystemSettingsPane] {
        lock.withLock { availablePanes }
    }

    func refreshInBackground() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let panes = catalog.panes()
            lock.withLock { availablePanes = panes }
        }
    }
}

/// Provides destinations that use System Settings' public URL scheme.
struct SystemSettingsPaneCatalog: SystemSettingsPaneCataloging {
    private let fileManager: FileManager
    private let systemSettingsURL: URL
    private let macOSMajorVersion: Int

    init(
        fileManager: FileManager = .default,
        systemSettingsURL: URL = URL(fileURLWithPath: "/System/Applications/System Settings.app"),
        macOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    ) {
        self.fileManager = fileManager
        self.systemSettingsURL = systemSettingsURL
        self.macOSMajorVersion = macOSMajorVersion
    }

    func panes() -> [SystemSettingsPane] {
        guard fileManager.fileExists(atPath: systemSettingsURL.path) else { return [] }
        // Private sidebar plists move between macOS releases. Their absence must never
        // hide launchable destinations; use the audited, version-specific reference instead.
        return SystemSettingsReference.panes(for: macOSMajorVersion)
    }

    static var supportedPanes: [SystemSettingsPane] {
        SystemSettingsReference.panes(for: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
}

extension SystemSettingsPane: LauncherSearchable {
    var searchLabel: String { name }
}
