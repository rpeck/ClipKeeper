#!/bin/zsh
# One-command Xcode build. Idempotent: checks Xcode, its license, and
# XcodeGen (and tells you what to install if one is missing), creates the
# signing identity if it is missing, generates the project, builds, and
# optionally launches, tests, or installs.
#
#   scripts/build-with-xcode.sh          debug build
#   scripts/build-with-xcode.sh run      debug build, then launch
#   scripts/build-with-xcode.sh test     unit tests through xcodebuild
#   scripts/build-with-xcode.sh release  release build
#   scripts/build-with-xcode.sh install  release build into /Applications, then launch
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-debug}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

fail() { echo "error: $*" >&2; exit 1; }

# 1. Tools.
[[ -d "$DEVELOPER_DIR" ]] || fail "Xcode is missing at $DEVELOPER_DIR. Install Xcode 26 from the App Store."
if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  fail "Xcode needs its license accepted. Run: sudo xcodebuild -license accept"
fi
if ! command -v xcodegen >/dev/null; then
  if command -v brew >/dev/null; then
    fail "XcodeGen is missing. Run: brew install xcodegen"
  else
    fail "XcodeGen is missing, and so is Homebrew. Install Homebrew from https://brew.sh, then run: brew install xcodegen"
  fi
fi

# 2. Signing identity, created once.
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "ClipKeeper Development"; then
  echo "Creating the local signing identity…"
  scripts/make-dev-cert.sh
fi

# 3. Build through the existing script, which generates the project first.
case "$MODE" in
  debug|release|test|run|install) scripts/build.sh "$MODE" ;;
  *) fail "unknown mode: $MODE (use debug, run, test, release, or install)" ;;
esac
