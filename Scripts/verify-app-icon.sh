#!/bin/zsh
set -euo pipefail

app=${1:?Usage: Scripts/verify-app-icon.sh APP_PATH}
plist="$app/Contents/Info.plist"
icon="$app/Contents/Resources/Cockpit.icns"
menuBarIcon="$app/Contents/Resources/CockpitMenuBarTemplate.png"

[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$plist") == "Cockpit.icns" ]]
[[ -f "$icon" ]]
[[ -f "$menuBarIcon" ]]

iconset=$(mktemp -d)/Cockpit.iconset
trap 'rm -rf "${iconset:h}"' EXIT
iconutil --convert iconset "$icon" --output "$iconset"
for representation in \
  icon_16x16.png icon_16x16@2x.png \
  icon_32x32.png icon_32x32@2x.png \
  icon_128x128.png icon_128x128@2x.png \
  icon_256x256.png icon_256x256@2x.png \
  icon_512x512.png icon_512x512@2x.png; do
  [[ -f "$iconset/$representation" ]]
done

[[ $(sips -g pixelWidth -g pixelHeight "$menuBarIcon") == *"pixelWidth: 72"* ]]
[[ $(sips -g pixelWidth -g pixelHeight "$menuBarIcon") == *"pixelHeight: 72"* ]]
