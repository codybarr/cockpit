#!/bin/zsh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
version=${1:?Usage: Scripts/create-app.sh VERSION APP_PATH}
app=${2:?Usage: Scripts/create-app.sh VERSION APP_PATH}

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/Assets/Cockpit.icns" "$app/Contents/Resources/Cockpit.icns"
cp "$root/Assets/CockpitMenuBarTemplate.png" "$app/Contents/Resources/CockpitMenuBarTemplate.png"
(
  cd "$root"
  swift build -c release
  cp .build/release/Cockpit "$app/Contents/MacOS/Cockpit"
)
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Cockpit</string>
  <key>CFBundleIdentifier</key><string>com.codybarr.Cockpit</string>
  <key>CFBundleName</key><string>Cockpit</string>
  <key>CFBundleIconFile</key><string>Cockpit.icns</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
