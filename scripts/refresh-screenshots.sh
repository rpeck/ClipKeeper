#!/bin/zsh
# Regenerates the screenshots in docs/images from a demo store, so no personal
# clips appear. Idempotent. Safe to run while your own ClipKeeper is running:
# it quits the app, works in a temporary data folder at a fixed shelf width,
# then restores your width and relaunches the app.
#
#   scripts/refresh-screenshots.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/spm/ClipKeeper.app"
BIN="$APP/Contents/MacOS/ClipKeeper"
OUT="docs/images"
WORK="$(mktemp -d)"
DEMO="$WORK/demo-data"
SNAPS="$WORK/snaps"
DOMAIN="com.raymondpeck.ClipKeeper"
WIDTH=440           # points; the shelf width every screenshot uses
SCALE_NUM=3         # scale captures to 3/8 of their 2x pixel width
SCALE_DEN=8

[[ -x "$BIN" ]] || { echo "No app at $APP. Run scripts/build-with-swiftpm.sh first." >&2; exit 1; }
command -v sips >/dev/null || { echo "sips is missing; it ships with macOS." >&2; exit 1; }

was_running=0
pgrep -x ClipKeeper >/dev/null && was_running=1
saved_width="$(defaults read "$DOMAIN" shelfWidth 2>/dev/null || echo 440)"

restore() {
  pkill -x ClipKeeper 2>/dev/null || true
  defaults write "$DOMAIN" shelfWidth -float "$saved_width"
  rm -rf "$WORK"
  if [[ $was_running -eq 1 ]]; then open "$APP"; fi
}
trap restore EXIT

pkill -x ClipKeeper 2>/dev/null || true
sleep 0.5
defaults write "$DOMAIN" shelfWidth -float "$WIDTH"

# 1. Fill the demo store.
echo "Filling the demo store…"
(CLIPKEEPER_DATA_DIR="$DEMO" "$BIN" -transferEnabled NO >/dev/null 2>&1 &)
sleep 2
swift scripts/demo-clips.swift >/dev/null
sleep 1.5
pkill -x ClipKeeper || true
sleep 0.5

# 2. Render the views.
echo "Rendering…"
(CLIPKEEPER_DATA_DIR="$DEMO" CLIPKEEPER_SNAPSHOT_DIR="$SNAPS" CLIPKEEPER_SNAPSHOT_QUIT=1 "$BIN" -transferEnabled NO >/dev/null 2>&1 &)
for _ in {1..40}; do
  sleep 0.5
  pgrep -x ClipKeeper >/dev/null || break
done
pgrep -x ClipKeeper >/dev/null && { pkill -x ClipKeeper; sleep 0.5; }

# 3. Copy and scale. The README shows the shelf from a full 2x copy at half
#    size, so it stays sharp on a Retina screen; the guide uses the 3/8 copies.
mkdir -p "$OUT"
[[ -f "$SNAPS/shelf.png" ]] && cp "$SNAPS/shelf.png" "$OUT/shelf-2x.png"
count=0
for f in shelf preview preview-image picker search checked confirm settings-keys settings-storage crop editor; do
  src="$SNAPS/$f.png"
  [[ -f "$src" ]] || { echo "  missing $f.png" >&2; continue; }
  cp "$src" "$OUT/$f.png"
  w="$(sips -g pixelWidth "$OUT/$f.png" | awk '/pixelWidth/{print $2}')"
  sips --resampleWidth $(( w * SCALE_NUM / SCALE_DEN )) "$OUT/$f.png" >/dev/null
  count=$((count + 1))
done
echo "Wrote $count screenshots to $OUT"
