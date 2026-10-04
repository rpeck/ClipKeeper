#!/bin/zsh
# Builds ClipKeeper.app from the SwiftPM release build, without Xcode.
# Output: build/spm/ClipKeeper.app
#   scripts/bundle-spm.sh          build the bundle
#   scripts/bundle-spm.sh run      build, then launch
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
MODE="${1:-build}"
OUT="build/spm"
APP="$OUT/ClipKeeper.app"
ICONSET="ClipKeeper/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$ICONSET/icon_512x512@2x.png" ]]; then
  swift scripts/make-icon.swift "$ICONSET"
fi

swift build -c release 2>&1 | grep -E "error|Build complete" || true
BIN=".build/release/ClipKeeper"
[[ -x "$BIN" ]] || { echo "build failed" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClipKeeper"

# Resource bundles of dependencies (highlight.js, localizations).
for b in .build/release/*.bundle; do
  [[ -d "$b" ]] && cp -R "$b" "$APP/Contents/Resources/"
done

# The user guide, opened from the menu bar.
cp docs/USER-GUIDE.md "$APP/Contents/Resources/USER-GUIDE.md"

# Icon: build an .icns from the PNG set.
TMPICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$TMPICONSET"
cp "$ICONSET"/icon_*.png "$TMPICONSET/"
iconutil -c icns "$TMPICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

VERSION="$(grep -m1 'MARKETING_VERSION' project.yml | awk '{print $2}')"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>ClipKeeper</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.raymondpeck.ClipKeeper</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>ClipKeeper</string>
  <key>CFBundleDisplayName</key><string>ClipKeeper</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-0.1.0}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Raymond Peck.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.raymondpeck.ClipKeeper</string>
      <key>CFBundleURLSchemes</key><array><string>clipkeeper</string></array>
    </dict>
  </array>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Add to ClipKeeper</string></dict>
      <key>NSMessage</key><string>addToClipKeeper</string>
      <key>NSPortName</key><string>ClipKeeper</string>
      <key>NSSendFileTypes</key><array><string>public.item</string></array>
      <key>NSRequiredContext</key><dict/>
    </dict>
  </array>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

# Sign with the stable development identity when it exists (scripts/make-dev-cert.sh),
# so the Accessibility permission survives rebuilds. Otherwise sign ad hoc.
IDENTITY="ClipKeeper Development"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" --identifier com.raymondpeck.ClipKeeper --timestamp=none "$APP" 2>&1 | grep -v "replacing existing signature" || true
  echo "Signed with \"$IDENTITY\""
else
  codesign --force --sign - --identifier com.raymondpeck.ClipKeeper "$APP" >/dev/null
  echo "Signed ad hoc. Run scripts/make-dev-cert.sh for a stable identity."
fi
echo "Built: $APP"

if [[ "$MODE" == "run" ]]; then
  pkill -x ClipKeeper || true
  sleep 0.3
  open "$APP"
fi
