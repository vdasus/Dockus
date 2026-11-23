#!/bin/bash
# Builds a universal, ad-hoc signed Dockus.app and build/Dockus.zip. Requires macOS with Xcode (the Command Line Tools lack XCBuild, which universal builds need).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-0.0.0}"
APP=build/Dockus.app

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
cp "$BIN/Dockus" "$APP/Contents/MacOS/Dockus"
sed "s/__VERSION__/$VERSION/g" Info.plist > "$APP/Contents/Info.plist"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --identifier io.github.vdasus.Dockus "$APP"
codesign --verify --strict "$APP"
lipo -archs "$APP/Contents/MacOS/Dockus"
# Fails the build unless every slice targets macOS 12 (Monterey).
[[ "$(otool -l "$APP/Contents/MacOS/Dockus" | awk '/minos/ {print $2}' | sort -u)" == "12.0" ]]

ditto -c -k --keepParent "$APP" build/Dockus.zip
echo "Built $APP ($VERSION)"
