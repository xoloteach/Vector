#!/usr/bin/env bash
# Renders every interface screen at four viewport sizes and fails if any panel is
# larger than the screen it is on.
#
#   ./scripts/ui_sheet.sh [name]
#
# A panel taller than the display hides its own close button and strands the player.
# That happened, and a browser capture did not reveal it — it photographed the panel's
# top seven times and reported success. This checks the geometry directly.

source "$(dirname "$0")/lib.sh"

NAME="${1:-latest}"
OUT="$CAPTURE_DIR/ui_sheet/$NAME"
GODOT="$(find_godot)"
export GODOT_SILENCE_ROOT_WARNING=1

DISPLAY_NUM="${XVFB_DISPLAY:-:99}"
if ! xdpyinfo -display "$DISPLAY_NUM" >/dev/null 2>&1; then
  step "Starting Xvfb on $DISPLAY_NUM"
  Xvfb "$DISPLAY_NUM" -screen 0 1600x1000x24 >/dev/null 2>&1 &
  XVFB_PID=$!
  trap 'kill "$XVFB_PID" 2>/dev/null || true' EXIT
  sleep 2
fi

rm -rf "$OUT"
mkdir -p "$OUT"

step "Rendering UI sheet -> $OUT"
set +e
DISPLAY="$DISPLAY_NUM" timeout 180 "$GODOT" --path "$GAME_DIR" \
  --resolution 1280x720 --audio-driver Dummy \
  res://tests/ui_harness.tscn -- --out "$OUT" 2>&1 \
  | grep -vE '^\[ *[0-9]+%|^\s*$|ALSA lib|snd_|audio driver' | tee "$OUT/harness.log"
set -e

if grep -q '^UI SHEET: FAIL' "$OUT/harness.log"; then
  grep 'OVERFLOW' "$OUT/harness.log" >&2
  die "a panel does not fit its screen — see $OUT"
fi
grep -q '^UI SHEET: DONE' "$OUT/harness.log" || die "UI sheet did not finish — see $OUT/harness.log"

count=$(ls -1 "$OUT"/*.png 2>/dev/null | wc -l)
step "Captured $count screens, all within their viewport"
printf '\n%sUI sheet complete.%s %s\n' "$C_GREEN$C_BOLD" "$C_OFF" "$OUT"
