# Native macOS foundation

Cockpit will be a Swift native macOS application with an AppKit lifecycle and launcher window, using SwiftUI only for the result-list views. It will be distributed directly as a Developer ID–signed and notarized app rather than targeting the Mac App Store, because its global launcher behavior, independently maintained filesystem index, and system actions need the least constrained native integration while remaining local-first.

## Considered Options

- **SwiftUI app lifecycle**: rejected as the owning shell because the nonstandard launcher panel, activation behavior, and global-hotkey lifecycle are AppKit concerns.
- **Mac App Store sandbox baseline**: rejected for v1 because security-scoped access, indexing, and system-action constraints would dominate the product design; Cockpit will still limit file discovery to folders the user deliberately selects.
