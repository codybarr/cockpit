# Least-privilege macOS integration

Cockpit will target macOS 13+ and use a Developer ID–signed, hardened-runtime, notarized app. It will use `SMAppService.mainApp` for an opt-in login item, a normal global-hotkey API rather than accessibility/input monitoring, user-selected folders rather than Full Disk Access, and just-in-time Apple Events consent only when a system action needs it.

## Consequences

Cockpit must never install a privileged helper, request Accessibility or Full Disk Access as a convenience, execute dynamically constructed shell commands or AppleScript, or collect a permission it does not actively need. Failed or revoked consent is visible in settings and returned plainly from the attempted command.
