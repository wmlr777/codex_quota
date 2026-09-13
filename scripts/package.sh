#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${ARCH:-universal}" "$ROOT/scripts/build.sh"
cd "$ROOT/dist"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "Codex Quota.app" "Codex-Quota-macOS.zip"
/usr/bin/shasum -a 256 "Codex-Quota-macOS.zip" > SHA256SUMS.txt
printf '%s\n' "$ROOT/dist/Codex-Quota-macOS.zip"
