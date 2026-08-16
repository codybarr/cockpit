# Least-privilege macOS integration

Cockpit will target macOS 13+ and use a Developer ID–signed, hardened-runtime, notarized app. It will use `SMAppService.mainApp` for an opt-in login item, a normal global-hotkey API rather than accessibility/input monitoring for its hotkey, user-selected folders rather than Full Disk Access, and just-in-time consent only when an explicit System action needs it. Lock requests Accessibility permission only when selected, because macOS exposes no supported public lock-screen API; it posts the standard Control-Command-Q lock shortcut after consent.

## Consequences

Cockpit must never install a privileged helper, request Accessibility or Full Disk Access as a convenience, execute dynamically constructed shell commands or AppleScript, or collect a permission it does not actively need. Accessibility is the narrow exception: request it just in time for the explicit Lock System action, never for the global hotkey or any passive behavior. Failed or revoked consent is visible in settings and returned plainly from the attempted command.
