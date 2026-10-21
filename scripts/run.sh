#!/bin/bash
# Development launches use a distinct bundle identity and writable storage root.
set -euo pipefail
reson_root="$(cd "$(dirname "$0")/.." && pwd)"
reson_app="$reson_root/build/Reson.app"
reson_development="$reson_root/build/Reson Development.app"
if [[ "${1:-}" == "--personal" ]]; then
    if [[ ! -x "$reson_app/Contents/MacOS/Reson" ]]; then "$reson_root/scripts/build.sh"; fi
    open "$reson_app"
    exit 0
fi
if [[ $# -gt 0 ]]; then echo 'Usage: scripts/run.sh [--personal]' >&2; exit 1; fi
if [[ ! -x "$reson_app/Contents/MacOS/Reson" ]]; then "$reson_root/scripts/build.sh"; fi
rm -rf "$reson_development"
ditto "$reson_app" "$reson_development"
/usr/libexec/PlistBuddy -c 'Set CFBundleIdentifier dev.reson.player.development' "$reson_development/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set CFBundleDisplayName Reson Development' "$reson_development/Contents/Info.plist"
codesign --force --sign - "$reson_development"
open "$reson_development"
