# Least-privilege macOS integration

Cockpit will target macOS 13+ and use a Developer ID–signed, hardened-runtime, notarized app. It will use `SMAppService.mainApp` for an opt-in login item, a normal global-hotkey API rather than accessibility/input monitoring for its hotkey, user-selected folders rather than Full Disk Access, and just-in-time consent only when an explicit System action needs it. Lock dynamically resolves `SACLockScreenImmediate` from the private macOS login framework, avoiding synthetic input and Accessibility consent. This explicitly accepts private-API compatibility risk for Lock; macOS exposes no supported public lock-screen API.

## Revised decision

The original decision to post Control-Command-Q after requesting Accessibility consent is superseded. A direct lock call provides a seamless action without granting Cockpit broad input-control privileges. This is a narrow private-API exception, not permission to use undocumented APIs generally.

## Consequences

Cockpit must never install a privileged helper, request Accessibility or Full Disk Access as a convenience, execute dynamically constructed shell commands or AppleScript, or collect a permission it does not actively need. Lock must not request Accessibility or fall back to keyboard simulation. Resolve the private framework and symbol at runtime; if unavailable, or if the call reports failure, return a clear error without preventing app launch. Apple may change or remove this API, so compatibility and Developer ID distribution need verification on supported macOS releases. Restart and Shut Down continue using fixed AppleScript commands targeting System Events and may require Automation consent; permission denial is returned plainly from the attempted command.
