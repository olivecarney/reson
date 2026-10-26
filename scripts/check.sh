#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests/release -v
cargo fmt --all -- --check
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
./scripts/build.sh
swift test --package-path macos
clang -fsyntax-only -x c macos/Bridge/include/reson.h
plutil -lint build/reson.app/Contents/Info.plist
reson_icon=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIconFile' build/reson.app/Contents/Info.plist)
test -s "build/reson.app/Contents/Resources/$reson_icon.icns"
test -s build/reson.app/Contents/Resources/Assets.car
codesign --verify --deep --strict build/reson.app
