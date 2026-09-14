#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Codex Quota.app"
mkdir -p "$APP/Contents/MacOS" "$ROOT/work/swift-cache"
ARCH="${ARCH:-$(uname -m)}"
compile() {
  swiftc -swift-version 5 -O -target "$1-apple-macosx14.0" -module-cache-path "$ROOT/work/swift-cache" -framework AppKit -framework SwiftUI "$ROOT/Sources/Localization.swift" "$ROOT/Sources/Quota.swift" "$ROOT/Sources/main.swift" -o "$2"
}
case "$ARCH" in
  universal)
    compile arm64 "$ROOT/work/CodexQuota-arm64"
    compile x86_64 "$ROOT/work/CodexQuota-x86_64"
    lipo -create "$ROOT/work/CodexQuota-arm64" "$ROOT/work/CodexQuota-x86_64" -output "$APP/Contents/MacOS/CodexQuota"
    ;;
  arm64|x86_64) compile "$ARCH" "$APP/Contents/MacOS/CodexQuota" ;;
  *) echo "Unsupported ARCH: $ARCH" >&2; exit 1 ;;
esac
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexQuota</string>
<key>CFBundleIdentifier</key><string>local.codex.quota</string>
<key>CFBundleName</key><string>Codex Quota</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string><string>zh-Hant</string></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
