#!/usr/bin/env bash
# Fast deterministic screenshots straight out of the engine.
#
#   ./scripts/shots.sh [name]        -> captures/shots/<name>/
#
# Renders the level from a fixed list of viewpoints with the runner teleported to
# each mark and the camera snapped, so two runs differ only by what changed in
# between. Takes seconds, where the browser capture path takes minutes — which is
# the difference between being able to tune lighting and composition at all and
# not.
#
# This does NOT replace ./scripts/test_web.sh. This renders with a desktop GL
# driver; only the browser test proves the *exported* build works on WebGL2.

source "$(dirname "$0")/lib.sh"

NAME="${1:-latest}"
OUT="$CAPTURE_DIR/shots/$NAME"
GODOT="$(find_godot)"
export GODOT_SILENCE_ROOT_WARNING=1

# Godot needs a display even to render offscreen into a viewport texture.
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

step "Rendering stations -> $OUT"
set +e
DISPLAY="$DISPLAY_NUM" timeout 180 "$GODOT" --path "$GAME_DIR" \
  --resolution 1280x720 --audio-driver Dummy \
  res://tests/shot_harness.tscn -- --out "$OUT" 2>&1 \
  | grep -vE '^\[ *[0-9]+%|^\s*$|ALSA lib|snd_|audio driver' | tee "$OUT/harness.log"
set -e

grep -q '^SHOTS: DONE' "$OUT/harness.log" || die "shot harness did not finish — see $OUT/harness.log"

count=$(ls -1 "$OUT"/*.png 2>/dev/null | wc -l)
[ "$count" -gt 0 ] || die "no PNGs were written"

step "Captured $count frames"
ls -la "$OUT"/*.png | sed 's/^/  /'
printf '\n%sShots complete.%s %s\n' "$C_GREEN$C_BOLD" "$C_OFF" "$OUT"
