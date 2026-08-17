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
mkdir -p "$workdir"
"$root/Scripts/create-app.sh" "$version" "$app"

codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$app"
ditto -c -k --keepParent "$app" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
ditto -c -k --keepParent "$app" "$archive"
echo "Notarized archive: $archive"
