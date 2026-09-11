#!/bin/zsh

set -eu

native_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$native_dir/.." && pwd)"
output_dir="${1:-$project_dir/dist/native}"

mkdir -p "$output_dir"

swift build --package-path "$native_dir" -c release --arch arm64
binary_dir="$(swift build --package-path "$native_dir" -c release --arch arm64 --show-bin-path)"

staging_dir="$(mktemp -d "$output_dir/.tibo-radar-build.XXXXXX")"
staging_app="$staging_dir/Tibo Radar.app"
mkdir -p "$staging_app/Contents/MacOS" "$staging_app/Contents/Resources"
cp "$native_dir/Info.plist" "$staging_app/Contents/Info.plist"
cp "$binary_dir/TiboRadar" "$staging_app/Contents/MacOS/TiboRadar"
chmod +x "$staging_app/Contents/MacOS/TiboRadar"

iconset_dir="$native_dir/.build/TiboRadar.iconset"
swift "$native_dir/Tools/GenerateIcon.swift" "$iconset_dir"
iconutil -c icns "$iconset_dir" -o "$staging_app/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$staging_app"

final_app="$output_dir/Tibo Radar.app"
if [[ -e "$final_app" ]]; then
    previous_dir="$(mktemp -d /tmp/tibo-radar-previous.XXXXXX)"
    mv "$final_app" "$previous_dir/"
fi
mv "$staging_app" "$final_app"
rmdir "$staging_dir"

echo "$final_app"
