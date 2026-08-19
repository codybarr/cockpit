#!/bin/zsh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
assets="$root/Assets"
master="$assets/CockpitIcon.svg"
menuBarMaster="$assets/CockpitMenuBarTemplate.svg"
iconset=$(mktemp -d)/Cockpit.iconset
trap 'rm -rf "${iconset:h}"' EXIT

mkdir -p "$iconset"
for spec in \
  "icon_16x16.png 16" \
  "icon_16x16@2x.png 32" \
  "icon_32x32.png 32" \
  "icon_32x32@2x.png 64" \
  "icon_128x128.png 128" \
  "icon_128x128@2x.png 256" \
  "icon_256x256.png 256" \
  "icon_256x256@2x.png 512" \
  "icon_512x512.png 512" \
  "icon_512x512@2x.png 1024"; do
  name=${spec% *}
  size=${spec##* }
  sips -s format png -z "$size" "$size" "$master" --out "$iconset/$name" >/dev/null
done

iconutil --convert icns "$iconset" --output "$assets/Cockpit.icns"
sips -s format png -z 72 72 "$menuBarMaster" --out "$assets/CockpitMenuBarTemplate.png" >/dev/null
