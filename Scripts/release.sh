#!/bin/zsh
set -euo pipefail

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to your Developer ID Application certificate name}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
version=${1:?Usage: Scripts/release.sh VERSION}
workdir="$root/.build/release-artifacts"
app="$workdir/Cockpit.app"
archive="$workdir/Cockpit-$version.zip"

rm -rf "$workdir"
mkdir -p "$app/Contents/MacOS"
swift build -c release
cp .build/release/Cockpit "$app/Contents/MacOS/Cockpit"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Cockpit</string>
  <key>CFBundleIdentifier</key><string>com.codybarr.Cockpit</string>
  <key>CFBundleName</key><string>Cockpit</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$app"
ditto -c -k --keepParent "$app" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
ditto -c -k --keepParent "$app" "$archive"
echo "Notarized archive: $archive"
