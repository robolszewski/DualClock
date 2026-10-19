#!/bin/bash
# Builds "DualClock.app" (with its "Two Hands" icon) using Apple's Swift compiler.
# Keep this file in the same folder as DualClock.swift.
# Run from Terminal:   bash Build.command

set -e
cd "$(dirname "$0")"
SRC="DualClock.swift"
APP="DualClock.app"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Apple's Command Line Tools are needed (free, ~1 GB). Opening the installer..."
  xcode-select --install || true
  echo "When the install finishes, run this script again."
  exit 1
fi

# Quit a running copy so the new build (and icon) take effect
osascript -e 'tell application "DualClock" to quit' >/dev/null 2>&1 || true

echo "Compiling $SRC ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -o "$APP/Contents/MacOS/DualClock" "$SRC"

echo "Drawing app icon ..."
ICONSET="$(mktemp -d)/DualClock.iconset"
"$APP/Contents/MacOS/DualClock" --make-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/DualClock.icns"
rm -rf "$(dirname "$ICONSET")"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>DualClock</string>
  <key>CFBundleIdentifier</key><string>local.dualclock</string>
  <key>CFBundleName</key><string>DualClock</string>
  <key>CFBundleDisplayName</key><string>DualClock</string>
  <key>CFBundleIconFile</key><string>DualClock</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.9</string>
  <key>CFBundleVersion</key><string>1.9</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force -s - "$APP" >/dev/null 2>&1 || true   # ad-hoc signature (required on Apple Silicon)
touch "$APP"                                            # nudge Finder to pick up the new icon
echo "Built $APP"

# Clean up the separate apps from v1.5, if present
rm -rf "DualClock 12h.app" "DualClock 24h.app"

open "$APP"
