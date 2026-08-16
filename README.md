# Cockpit

Cockpit is a local macOS launcher for opening applications and deliberately indexed filenames without Spotlight.

## Build and install

Cockpit requires macOS 13 or later and Xcode 15 or later. Build and run a development copy with:

```sh
swift test
swift run Cockpit
```

To build a release executable and install it as a local app in `~/Applications`:

```sh
swift build -c release

app="$HOME/Applications/Cockpit.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/Cockpit "$app/Contents/MacOS/Cockpit"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Cockpit</string>
  <key>CFBundleIdentifier</key><string>com.codybarr.Cockpit</string>
  <key>CFBundleName</key><string>Cockpit</string>
  <key>CFBundleShortVersionString</key><string>local</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
open "$app"
```

This produces an unsigned local build. To put it in `/Applications` for every user, replace `$HOME/Applications` with `/Applications` and run the installation commands with the needed administrator privileges.

Press **Option-Space** to show the Launcher. Use Cockpit’s menu-bar icon to show or quit the app. Cockpit searches the standard application locations (`/Applications`, `/System/Applications`, and `~/Applications`) without Spotlight, alongside Lock, Restart, and Shut Down System actions. Select a result and press Return to open the application or run the System action. The menu-bar menu also provides an opt-in Launch at Login control; “Approval Needed” leaves macOS’s setting unchanged.

## Performance acceptance benchmarks

On an Apple-silicon Mac, run the repeatable 50,000-item fixture benchmark with:

```sh
COCKPIT_RUN_BENCHMARKS=1 swift test --filter PerformanceBenchmarks
```

It verifies the documented p95 hotkey and p95/p99 ranked-query targets. Filesystem freshness is covered by the filename-index change-event integration checks.

## Direct release

`Scripts/release.sh <version>` builds a hardened-runtime Developer ID app, submits it for notarization, staples the result, and emits a distributable zip. It requires `DEVELOPER_ID_APPLICATION` and `NOTARY_PROFILE`; the release bundle contains no entitlements or privileged helpers.
