# Cockpit

Cockpit is a local macOS launcher for opening applications and deliberately indexed filenames without Spotlight.

## Development

Requires Xcode 15 or later and macOS 13 or later.

```sh
swift test
swift run Cockpit
```

Press **Option-Space** to show the Launcher. Use Cockpit’s menu-bar icon to show or quit the app. Cockpit searches the standard application locations (`/Applications`, `/System/Applications`, and `~/Applications`) without Spotlight, alongside Lock, Restart, and Shut Down System actions. Select a result and press Return to open the application or run the System action.
