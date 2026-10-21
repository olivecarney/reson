#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
reson_iconset="build/AppIcon.iconset"
mkdir -p "$reson_iconset" build/Reson.app/Contents/Resources
for reson_size in 16 32 128 256 512; do
    sips -z "$reson_size" "$reson_size" macos/Resources/AppIcon.png \
        --out "$reson_iconset/icon_${reson_size}x${reson_size}.png" >/dev/null
    reson_retina=$((reson_size * 2))
    sips -z "$reson_retina" "$reson_retina" macos/Resources/AppIcon.png \
        --out "$reson_iconset/icon_${reson_size}x${reson_size}@2x.png" >/dev/null
done
iconutil -c icns "$reson_iconset" -o build/Reson.app/Contents/Resources/AppIcon.icns
