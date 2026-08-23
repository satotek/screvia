#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
cd "$repo_dir"

# LicenseList's build plugin looks for Xcode's SourcePackages layout. The
# SwiftPM CLI uses .build instead, which has the same shape
# (workspace-state.json + checkouts/), so point the plugin at it.
export PLL_SOURCE_PACKAGES_PATH="$repo_dir/.build"

# `--show-bin-path` only prints the destination; it does not compile the
# target. Build first so packaging can never reuse an older executable.
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app_dir="$repo_dir/.build/Screvia.app"

# Start clean. SwiftPM emits resource bundles read-only (mode 444), so a
# second run cannot overwrite the files left by the first one.
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/Screvia" "$app_dir/Contents/MacOS/Screvia"
cp "$repo_dir/Sources/ScreviaKit/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$repo_dir/Sources/ScreviaKit/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
# Every SwiftPM resource bundle, ours and our dependencies'. They sit at the
# .app root because that is where Bundle.module looks (Bundle.main.bundleURL).
cp -R "$bin_dir"/*.bundle "$app_dir/"
cp -R "$repo_dir/Sources/ScreviaKit/en.lproj" "$app_dir/Contents/Resources/"
cp -R "$repo_dir/Sources/ScreviaKit/ja.lproj" "$app_dir/Contents/Resources/"

if [[ "${SCREVIA_OPEN_APP:-1}" == "1" ]]; then
  open "$app_dir"
fi
