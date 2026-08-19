#!/bin/zsh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
app=${1:-"$HOME/Applications/Cockpit.app"}
identity=$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/"Apple Development:/{ print $2; exit }')

if [[ -z "$identity" ]]; then
  echo "An Apple Development signing identity is required. Add one in Xcode > Settings > Accounts > Manage Certificates." >&2
  exit 1
fi

"$root/Scripts/create-app.sh" local "$app"
codesign --force --options runtime --sign "$identity" "$app"
"$root/Scripts/verify-app-icon.sh" "$app"
open "$app"

echo "Installed locally signed build: $app"
