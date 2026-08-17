#!/bin/zsh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
app=${1:-"$HOME/Applications/Cockpit.app"}

"$root/Scripts/create-app.sh" local "$app"
open "$app"

echo "Installed unsigned local build: $app"
