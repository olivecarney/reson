#!/bin/bash
# Package an already built app without modifying its signature.
set -euo pipefail
cd "$(dirname "$0")/.."
reson_app="build/Reson.app"
reson_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$reson_app/Contents/Info.plist")
if [[ -n "${RESON_RELEASE_TAG:-}" && "$RESON_RELEASE_TAG" != "v$reson_version" ]]; then
    printf 'Release tag %s does not match app version v%s\n' "$RESON_RELEASE_TAG" "$reson_version" >&2
    exit 1
fi
codesign --verify --deep --strict "$reson_app"
mkdir -p build/dist
reson_archive="Reson-$reson_version-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$reson_app" "build/dist/$reson_archive"
(cd build/dist && shasum -a 256 "$reson_archive" > "$reson_archive.sha256")
printf 'Packaged build/dist/%s\n' "$reson_archive"
