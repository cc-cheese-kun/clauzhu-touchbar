#!/bin/bash
# Builds ClaudePigCrab.app (a background agent that animates the crab in the Touch Bar).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/ClaudePigCrab.app"
BIN="$APP/Contents/MacOS/ClaudePigCrab"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

echo "Compiling…"
swiftc -O -target arm64-apple-macos11.0 Sources/*.swift -o "$BIN" -framework Cocoa

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClaudePigCrab</string>
  <key>CFBundleDisplayName</key><string>Clau猪</string>
  <key>CFBundleIdentifier</key><string>com.claudepig.crab</string>
  <key>CFBundleExecutable</key><string>ClaudePigCrab</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so it runs locally (private DFRFoundation use means it's not App Store / notarizable).
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
