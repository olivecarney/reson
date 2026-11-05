#!/bin/bash
# Development launches use a distinct bundle identity and writable storage root.
set -euo pipefail
reson_root="$(cd "$(dirname "$0")/.." && pwd)"
reson_app="$reson_root/build/reson.app"
reson_development="$reson_root/build/reson Development.app"
reson_personal=false
case "${1:-}" in
    "") ;;
    --personal) reson_personal=true ;;
    *) echo 'Usage: scripts/run.sh [--personal]' >&2; exit 1 ;;
esac
if [[ $# -gt 1 ]]; then echo 'Usage: scripts/run.sh [--personal]' >&2; exit 1; fi
if [[ ! -x "$reson_app/Contents/MacOS/reson" ]]; then "$reson_root/scripts/build.sh"; fi
if [[ "$reson_personal" == true ]]; then
    open "$reson_app"
    exit 0
fi
rm -rf "$reson_development"
ditto "$reson_app" "$reson_development"
/usr/libexec/PlistBuddy -c 'Set CFBundleIdentifier dev.reson.player.development' "$reson_development/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set CFBundleDisplayName reson Development' "$reson_development/Contents/Info.plist"
codesign --force --sign - "$reson_development"
open "$reson_development"
