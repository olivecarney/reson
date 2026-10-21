#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo fmt --all -- --check
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
./scripts/build.sh
swift test --package-path macos
clang -fsyntax-only -x c macos/Bridge/include/reson.h
plutil -lint build/Reson.app/Contents/Info.plist
codesign --verify --deep --strict build/Reson.app
