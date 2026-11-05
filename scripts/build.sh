#!/bin/bash
set -euo pipefail
reson_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$reson_root"
export MACOSX_DEPLOYMENT_TARGET=14.0
cargo build --locked --release --target aarch64-apple-darwin
# SPM's linker path is relative to macos; the explicit target keeps architecture reproducible.
mkdir -p target/release
cp target/aarch64-apple-darwin/release/libreson_engine.a target/release/libreson_engine.a
# Native AppKit/SwiftUI styling depends on the SDK recorded in LC_BUILD_VERSION.
# Some newer toolchains otherwise record the deployment target as the SDK version.
reson_sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
reson_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
reson_minimum="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' macos/Info.plist)"
reson_swift_flags=(-c release --arch arm64 --sdk "$reson_sdk_path"
    -Xlinker -platform_version -Xlinker macos -Xlinker "$reson_minimum" -Xlinker "$reson_sdk_version")
cd macos
swift build "${reson_swift_flags[@]}"
reson_bin="$(swift build "${reson_swift_flags[@]}" --show-bin-path)"
cd "$reson_root"
mkdir -p build/reson.app/Contents/MacOS
cp "$reson_bin/Reson" build/reson.app/Contents/MacOS/reson
reson_linked_sdk="$(xcrun vtool -show-build build/reson.app/Contents/MacOS/reson | awk '$1 == "sdk" { print $2; exit }')"
if [[ "$reson_linked_sdk" != "$reson_sdk_version" ]]; then
    printf 'Expected linked SDK %s, found %s\n' "$reson_sdk_version" "$reson_linked_sdk" >&2
    exit 1
fi
cp macos/Info.plist build/reson.app/Contents/Info.plist
./scripts/build-icon.sh
python3 scripts/bundle-licenses.py
codesign --force --sign - build/reson.app
printf 'Built %s/build/reson.app\n' "$reson_root"
