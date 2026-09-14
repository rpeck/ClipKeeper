#!/bin/zsh
# Builds ClipKeeper from the command line.
#   scripts/build.sh            debug build
#   scripts/build.sh release    release build
#   scripts/build.sh test       run unit tests
#   scripts/build.sh run        debug build, then launch the app
#   scripts/build.sh install    release build, copy to /Applications, launch
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
MODE="${1:-debug}"
DERIVED="build/DerivedData"

if ! command -v xcodegen >/dev/null; then
  echo "xcodegen is missing. Install it with: brew install xcodegen" >&2
  exit 1
fi

if [[ ! -f ClipKeeper/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png ]]; then
  echo "Generating app icon…"
  swift scripts/make-icon.swift ClipKeeper/Assets.xcassets/AppIcon.appiconset
fi

xcodegen generate --quiet

common=(-project ClipKeeper.xcodeproj -scheme ClipKeeper -derivedDataPath "$DERIVED" -quiet)

case "$MODE" in
  debug)
    xcodebuild "${common[@]}" -configuration Debug build
    echo "Built: $DERIVED/Build/Products/Debug/ClipKeeper.app"
    ;;
  release)
    xcodebuild "${common[@]}" -configuration Release build
    echo "Built: $DERIVED/Build/Products/Release/ClipKeeper.app"
    ;;
  test)
    xcodebuild "${common[@]}" -configuration Debug test 2>&1 | grep -E "Test Suite|Test Case|error|failed|passed|\*\*" || true
    ;;
  run)
    xcodebuild "${common[@]}" -configuration Debug build
    pkill -x ClipKeeper || true
    open "$DERIVED/Build/Products/Debug/ClipKeeper.app"
    ;;
  install)
    xcodebuild "${common[@]}" -configuration Release build
    pkill -x ClipKeeper || true
    rm -rf /Applications/ClipKeeper.app
    cp -R "$DERIVED/Build/Products/Release/ClipKeeper.app" /Applications/
    open /Applications/ClipKeeper.app
    echo "Installed /Applications/ClipKeeper.app"
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    exit 2
    ;;
esac
