#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/xcode-env.sh
configuration="${1:-release}"
swift build --build-system xcode -c "$configuration"
bin_path="$(swift build --build-system xcode -c "$configuration" --show-bin-path)"
app_path="$PWD/dist/Mac Power Toys.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/MacPowerToys" "$app_path/Contents/MacOS/"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
# The Xcode build system's Bundle.module accessor uses the app Resources directory.
for resource in "$bin_path"/*.bundle; do
    [ -d "$resource" ] || continue
    cp -R "$resource" "$app_path/Contents/Resources/"
done
cp LICENSE "$app_path/Contents/Resources/"
cp THIRD_PARTY_NOTICES.md "$app_path/Contents/Resources/"
codesign --force --deep --sign - "$app_path"
printf 'Built: %s\n' "$app_path"
