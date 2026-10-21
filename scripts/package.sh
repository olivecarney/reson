#!/bin/bash
# Package and verify an already built app without modifying its signature.
set -euo pipefail
cd "$(dirname "$0")/.."
reson_app="build/Reson.app"
reson_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$reson_app/Contents/Info.plist")
if [[ -n "${RESON_RELEASE_TAG:-}" && "$RESON_RELEASE_TAG" != "v$reson_version" ]]; then
    printf 'Release tag %s does not match app version v%s\n' "$RESON_RELEASE_TAG" "$reson_version" >&2
    exit 1
fi
codesign --verify --deep --strict "$reson_app"
reson_venv="build/packaging-venv"
if [[ ! -x "$reson_venv/bin/python" ]]; then
    python3 -m venv "$reson_venv"
fi
"$reson_venv/bin/python" -m pip install --quiet --disable-pip-version-check \
    --require-hashes -r scripts/requirements-packaging.txt
reson_work=$(mktemp -d "$PWD/build/package.XXXXXXXX")
reson_mount="$reson_work/mounted"
reson_attached=false
reson_cleanup() {
    if [[ "$reson_attached" == true ]]; then hdiutil detach "$reson_mount" >/dev/null || true; fi
    rm -rf "$reson_work"
}
trap reson_cleanup EXIT
reson_image="Reson-$reson_version-macos-arm64.dmg"
swift scripts/dmg-background.swift "$reson_work/background.png"
"$reson_venv/bin/dmgbuild" -s scripts/dmg-settings.py -D "app=$reson_app" -D "background=$reson_work/background.png" \
    "Reson $reson_version" "$reson_work/$reson_image"
hdiutil verify "$reson_work/$reson_image" >/dev/null
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$reson_mount" \
    "$reson_work/$reson_image" >/dev/null
reson_attached=true
codesign --verify --deep --strict "$reson_mount/Reson.app"
test "$(readlink "$reson_mount/Applications")" = /Applications
test -s "$reson_mount/.DS_Store"
test -s "$reson_mount/Reson.app/Contents/Resources/AppIcon.icns"
test -s "$reson_mount/Reson.app/Contents/Resources/Assets.car"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$reson_mount/Reson.app/Contents/Info.plist")" = "$reson_version"
hdiutil detach "$reson_mount" >/dev/null
reson_attached=false
mkdir -p build/dist
mv "$reson_work/$reson_image" "build/dist/$reson_image"
(cd build/dist && shasum -a 256 "$reson_image" > "$reson_image.sha256")
printf 'Verified disk image: build/dist/%s\n' "$reson_image"
