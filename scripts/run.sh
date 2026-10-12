#!/bin/bash
set -euo pipefail
reson_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -x "$reson_root/build/Reson.app/Contents/MacOS/Reson" ]]; then "$reson_root/scripts/build.sh"; fi
open "$reson_root/build/Reson.app"
