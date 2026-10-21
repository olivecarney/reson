#!/bin/bash
set -euo pipefail
reson_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$reson_root"
export MACOSX_DEPLOYMENT_TARGET=14.0
cargo build --locked --release --target aarch64-apple-darwin
# SPM's linker path is relative to macos; the explicit target keeps architecture reproducible.
mkdir -p target/release
cp target/aarch64-apple-darwin/release/libreson_engine.a target/release/libreson_engine.a
cd macos
swift build -c release --arch arm64
reson_bin="$(swift build -c release --arch arm64 --show-bin-path)"
cd "$reson_root"
mkdir -p build/Reson.app/Contents/MacOS
cp "$reson_bin/Reson" build/Reson.app/Contents/MacOS/Reson
cp macos/Info.plist build/Reson.app/Contents/Info.plist
./scripts/build-icon.sh
python3 scripts/bundle-licenses.py
codesign --force --sign - build/Reson.app
printf 'Built %s/build/Reson.app\n' "$reson_root"
