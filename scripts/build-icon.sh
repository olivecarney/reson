#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
reson_iconset="build/AppIcon.iconset"
mkdir -p "$reson_iconset" build/reson.app/Contents/Resources
for reson_size in 16 32 128 256 512; do
    sips -z "$reson_size" "$reson_size" macos/Resources/AppIcon.icon/Assets/AppIcon.png \
        --out "$reson_iconset/icon_${reson_size}x${reson_size}.png" >/dev/null
    reson_retina=$((reson_size * 2))
    sips -z "$reson_retina" "$reson_retina" macos/Resources/AppIcon.icon/Assets/AppIcon.png \
        --out "$reson_iconset/icon_${reson_size}x${reson_size}@2x.png" >/dev/null
done
iconutil -c icns "$reson_iconset" -o build/reson.app/Contents/Resources/AppIcon.icns

# Compile the native macOS 26+ icon alongside the transparent legacy fallback.
mkdir -p build/NativeIcon
xcrun actool macos/Resources/AppIcon.icon --compile build/NativeIcon \
    --app-icon AppIcon --output-format human-readable-text \
    --output-partial-info-plist build/NativeIcon/Info.plist \
    --include-all-app-icons --target-device mac \
    --minimum-deployment-target 14.0 --platform macosx
cp build/NativeIcon/Assets.car build/reson.app/Contents/Resources/Assets.car
