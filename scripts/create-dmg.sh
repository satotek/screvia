#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
cd "$repo_dir"

app_name="Screvia"
plist_path="$repo_dir/Sources/ScreviaKit/Resources/Info.plist"
version="$(plutil -extract CFBundleShortVersionString raw -o - "$plist_path")"
app_dir="$repo_dir/.build/${app_name}.app"
dmg_dir="$repo_dir/dist"
dmg_path="$dmg_dir/${app_name}-${version}.dmg"
staging_root="$(mktemp -d /tmp/screvia-dmg.XXXXXX)"

cleanup() {
    rm -rf "$staging_root"
}
trap cleanup EXIT

mkdir -p "$dmg_dir" "$staging_root/$app_name"

# Reuse the canonical app-bundle build, but do not launch the app while
# preparing a distributable image.
SCREVIA_OPEN_APP=0 "$repo_dir/scripts/build-app.sh"

ditto "$app_dir" "$staging_root/$app_name/${app_name}.app"
ln -s /Applications "$staging_root/$app_name/Applications"

# UDZO is a compressed, read-only disk image suitable for drag-and-drop
# distribution. Signing and notarization are intentionally separate steps.
hdiutil create \
    -volname "$app_name" \
    -srcfolder "$staging_root/$app_name" \
    -ov \
    -format UDZO \
    "$dmg_path" >/dev/null

printf 'Created %s\n' "$dmg_path"
