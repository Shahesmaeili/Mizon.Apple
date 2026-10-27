#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
scratch_path="${SWIFT_SCRATCH_PATH:-$PWD/.build}"
swift build --scratch-path "$scratch_path" -c "$configuration" --product MizonPreview
binary_dir="$(swift build --scratch-path "$scratch_path" -c "$configuration" --show-bin-path)"
app="$PWD/build/Mizon.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/MizonPreview" "$app/Contents/MacOS/Mizon"
for bundle in "$binary_dir"/*.bundle; do
    if [[ -d "$bundle" ]]; then ditto "$bundle" "$app/Contents/Resources/$(basename "$bundle")"; fi
done
cp App/Info.plist "$app/Contents/Info.plist"
if [[ -f App/AppIcon.icns ]]; then cp App/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"; fi
codesign --force --deep --sign - "$app"
echo "$app"
