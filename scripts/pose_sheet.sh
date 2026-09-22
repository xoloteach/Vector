#!/usr/bin/env bash
# Renders the runner alone, large, on a neutral backdrop — one frame per pose.
#
#   ./scripts/pose_sheet.sh [name]
#
# Use this when a pose looks wrong in gameplay and it is unclear whether the pose,
# the model, or the reading of a 150 px dark shape is at fault. Isolating the figure
# removes every variable except the rig itself.

source "$(dirname "$0")/lib.sh"

NAME="${1:-latest}"
OUT="$CAPTURE_DIR/poses/$NAME"
GODOT="$(find_godot)"
export GODOT_SILENCE_ROOT_WARNING=1

DISPLAY_NUM="${XVFB_DISPLAY:-:99}"
if ! xdpyinfo -display "$DISPLAY_NUM" >/dev/null 2>&1; then
  step "Starting Xvfb on $DISPLAY_NUM"
  Xvfb "$DISPLAY_NUM" -screen 0 1280x720x24 >/dev/null 2>&1 &
  XVFB_PID=$!
  trap 'kill "$XVFB_PID" 2>/dev/null || true' EXIT
  sleep 2
fi

rm -rf "$OUT"
mkdir -p "$OUT"

step "Rendering pose sheet -> $OUT"
set +e
DISPLAY="$DISPLAY_NUM" timeout 180 "$GODOT" --path "$GAME_DIR" \
  --resolution 900x900 --audio-driver Dummy \
  res://tests/pose_sheet.tscn -- --out "$OUT" 2>&1 \
  | grep -vE '^\[ *[0-9]+%|^\s*$|ALSA lib|snd_|audio driver' | tee "$OUT/harness.log"
set -e

grep -q '^POSE SHEET: DONE' "$OUT/harness.log" || die "pose sheet failed — see $OUT/harness.log"

count=$(ls -1 "$OUT"/*.png 2>/dev/null | wc -l)
step "Captured $count poses"
printf '\n%sPose sheet complete.%s %s\n' "$C_GREEN$C_BOLD" "$C_OFF" "$OUT"
