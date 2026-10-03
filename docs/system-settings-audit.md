# System Settings parity audit

Reference: installed **Alfred 5.7.3**, `Alfred Framework.framework/Versions/A/Resources/systemsettings{13,14,15,26}.json`, audited 2026-10-03. English names were selected explicitly; localization is outside this change.

## Regression

On macOS 27.0 (26A428), neither `System Settings.app/Contents/Resources/Sidebar.plist` nor `Contents/PlugIns/GeneralSettings.appex/Contents/Info.plist` exists. Cockpit treated missing private declarations as an empty availability list, hiding every destination. Existing tests checked the static list, not the actual catalog.

The catalog now uses a checked-in version-specific reference, independent of Apple's private plists and of an installed Alfred. It still returns no panes if System Settings itself is absent. macOS 27 and future versions use the latest audited catalog (26) until a newer reference is available; this is not a claim that their complete Apple settings inventory is identical.

## Exact catalog contract

| macOS reference | Entries | Differences |
| --- | ---: | --- |
| 13 | 46 | Apple ID, Profiles, Login Items, Siri & Spotlight; includes Control Center, Screen Saver, Passwords; no AppleCare & Warranty or separate Spotlight |
| 14 | 47 | Adds AppleCare & Warranty; changes Battery/Siri URL suffixes, Wi-Fi/Software Update icon paths |
| 15 | 47 | Apple Account, Device Management, Login Items & Extensions, Apple Intelligence & Siri; separate Spotlight; removes Passwords |
| 26 | 46 | Menu Bar replaces Control Center (including destination suffix); removes Screen Saver |

`Sources/Cockpit/SystemSettingsReference.swift` mirrors **all entries, order, English labels (including nonbreaking hyphens/spaces), and complete destination URLs** for each reference. `Tests/CockpitTests/Fixtures/alfred-system-settings.json` records the audited names, URLs, and icon paths and is the exhaustive parity fixture.

Destination suffixes must not be discarded: `*AppleIDSettings`, `*Family`, `*TouchIDPasswordPrefs`, `*BatteryPreferences`, `*siri-sae`, `*menubar`, and `:icloud` are part of Alfred's URLs. Apple Account and iCloud remain separately identifiable results.

## macOS 26 entries

About; Accessibility; AirDrop & Handoff; Appearance; AppleCare & Warranty; Apple Account; Bluetooth; Date & Time; Desktop & Dock; Device Management; Displays; Family; Focus; General; Game Center; Game Controllers; Internet Accounts; Keyboard; Language & Region; Lock Screen; Login Items & Extensions; Mouse; Network; Notifications; Printers & Scanners; Privacy & Security; Screen Time; Sharing; Spotlight; Software Update; Sound; Startup Disk; Storage; Time Machine; Touch ID & Password; Trackpad; Transfer or Reset; Users & Groups; Wallet & Apple Pay; VPN; Wallpaper; Wi‑Fi; Battery; Menu Bar; Apple Intelligence & Siri; iCloud.

Compared with Cockpit's former list, this adds 13 destinations: AirDrop & Handoff, AppleCare & Warranty, Date & Time, Device Management, Language & Region, Sharing, Software Update, Startup Disk, Storage, Time Machine, Transfer or Reset, VPN, and iCloud. It also corrects Siri/Menu Bar labels and destination suffixes. CDs & DVDs is not in any audited Alfred catalog. Passwords is only in the 13/14 references, not 15/26.

## Icons and limitations

Apple bundle icon paths match each reference and are rendered using `NSWorkspace.icon(forFile:)` when present. Missing paths fall back to Cockpit's existing SF Symbols/resource icons without removing the result. In particular, Alfred's General icon bundle path is absent on the audited macOS 27 installation.

Alfred uses proprietary custom icon sentinels for Battery and (26) Menu Bar. These are **not copied**: Cockpit uses its battery/menu-bar symbols instead. Thus entry/label/URL parity is exact; artwork is not pixel-identical. Other UI behavior and Alfred's search-ranking implementation are not part of this catalog mirror.

## Verification

Run with the Xcode toolchain (the installed Command Line Tools SDK lacks the SwiftUI State macro plugin):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Tests compare every entry across all four references, validate unique identities and icon paths, exercise empty/malformed private-plist installations, reproduce installed-Mac Display/Wi-Fi/Bluetooth searches, and exercise selection/execution through the real catalog and Launcher controller. Execution tests record the destination without opening or changing the user's settings.

For a future audit, compare Alfred's versioned JSON against the fixture, update the reference and fixture together, and verify names, complete URLs, icon paths, ordering, removals, and the future-version fallback policy.
