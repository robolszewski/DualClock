#!/bin/bash
# Builds "DualClock 12h.app" and "DualClock 24h.app" with Apple's Swift compiler.
# Keep this file in the same folder as DualClock.swift.
# Run from Terminal:   bash Build.command

set -e
cd "$(dirname "$0")"
SRC="DualClock.swift"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Apple's Command Line Tools are needed (free, ~1 GB). Opening the installer..."
  xcode-select --install || true
  echo "When the install finishes, run this script again."
  exit 1
fi

echo "Compiling $SRC ..."
swiftc -O -o DualClock.bin "$SRC"

make_app() {
  local NAME="$1" MODE="$2"
  local APP="$NAME.app"
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS"
  cp DualClock.bin "$APP/Contents/MacOS/DualClock"
  cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>DualClock</string>
  <key>CFBundleIdentifier</key><string>local.dualclock.${MODE}h</string>
  <key>CFBundleName</key><string>${NAME}</string>
  <key>CFBundleDisplayName</key><string>${NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.5</string>
  <key>CFBundleVersion</key><string>1.5</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>DualClockMode</key><string>${MODE}</string>
</dict>
</plist>
EOF
  codesign --force -s - "$APP" >/dev/null 2>&1 || true   # ad-hoc signature (required on Apple Silicon)
  echo "Built $APP"
}

make_app "DualClock 12h" 12
make_app "DualClock 24h" 24
rm -f DualClock.bin

open "DualClock 12h.app"
open "DualClock 24h.app"
