#!/bin/zsh
# One-command SwiftPM build. Idempotent: checks the tools, creates the signing
# identity if it is missing, builds, signs, and optionally launches or tests.
#
#   scripts/build-with-swiftpm.sh          build  -> build/spm/ClipKeeper.app
#   scripts/build-with-swiftpm.sh run      build, then launch
#   scripts/build-with-swiftpm.sh test     run the unit tests
#   scripts/build-with-swiftpm.sh lint     run SwiftLint with the repository rules
#   scripts/build-with-swiftpm.sh check    test, lint, and audit the dependencies: run before a pull request
#   scripts/build-with-swiftpm.sh install  build, copy to /Applications, launch
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-build}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
# SwiftLint loads SourceKit from the selected toolchain. Point it at the same one.
export TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$DEVELOPER_DIR}"

fail() { echo "error: $*" >&2; exit 1; }

# 1. Tools.
if ! xcode-select -p >/dev/null 2>&1; then
  fail "the Command Line Tools are missing. Run: xcode-select --install"
fi
if [[ ! -d "$DEVELOPER_DIR" ]]; then
  fail "DEVELOPER_DIR does not exist: $DEVELOPER_DIR"
fi
if ! swift --version >/dev/null 2>&1; then
  fail "swift does not run. If Xcode is selected, accept its license: sudo xcodebuild -license accept"
fi

# 2. Signing identity, created once.
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "ClipKeeper Development"; then
  echo "Creating the local signing identity…"
  scripts/make-dev-cert.sh
fi

# 3. Build, test, or run.
case "$MODE" in
  build)   scripts/bundle-spm.sh ;;
  run)     scripts/bundle-spm.sh run ;;
  test)    swift test -c release -Xswiftc -enable-testing 2>&1 | grep -E "error:|✘|Test run with" || true ;;
  lint)
    command -v swiftlint >/dev/null || fail "SwiftLint is missing. Run: brew install swiftlint"
    swiftlint lint --strict
    ;;
  check)
    echo "== Tests"
    swift test -c release -Xswiftc -enable-testing 2>&1 | grep -E "error:|✘|Test run with"
    echo "== Lint"
    command -v swiftlint >/dev/null || fail "SwiftLint is missing. Run: brew install swiftlint"
    swiftlint lint --strict --quiet && echo "no lint findings"
    echo "== Dependency audit"
    scripts/audit-deps.sh
    echo "== All checks passed"
    ;;
  install)
    scripts/bundle-spm.sh
    pkill -x ClipKeeper || true
    rm -rf /Applications/ClipKeeper.app
    cp -R build/spm/ClipKeeper.app /Applications/
    open /Applications/ClipKeeper.app
    echo "Installed /Applications/ClipKeeper.app"
    ;;
  *) fail "unknown mode: $MODE (use build, run, test, or install)" ;;
esac
