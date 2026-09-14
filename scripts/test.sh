#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/work/swift-cache"
swiftc -swift-version 5 -module-cache-path "$ROOT/work/swift-cache" "$ROOT/Sources/Localization.swift" "$ROOT/Sources/Quota.swift" "$ROOT/Tests/main.swift" -o "$ROOT/work/quota-tests"
"$ROOT/work/quota-tests"
BIN="$ROOT/dist/Codex Quota.app/Contents/MacOS/CodexQuota"
RESULT=$(CODEX_BIN="$ROOT/Tests/mock-codex.py" "$BIN" --probe)
[[ "$RESULT" == 'Codex: primary=32%, secondary=unavailable%' ]]
if CODEX_BIN="$ROOT/Tests/mock-codex.py" MOCK_FAILURE=1 "$BIN" --probe > "$ROOT/work/mock-error.txt" 2>&1; then
  echo 'Expected authentication failure'; exit 1
fi
printf '%s\n' 'RPC handshake, notification handling, missing windows, and error propagation passed'
