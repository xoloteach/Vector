#!/usr/bin/env bash
# Captures the interface screens from the real exported build.
#
#   ./scripts/test_ui.sh [output-name]
#
# The gameplay capture launches straight into a run with the autopilot driving, so it
# never sees the title, controls, settings, pause or results screens. Those are the
# ones most likely to be quietly broken, and nothing about a layout overflowing or a
# panel rendering behind another is visible from reading code.

source "$(dirname "$0")/lib.sh"

NAME="${1:-ui}"
PORT="${PORT:-8097}"
OUT="$CAPTURE_DIR/$NAME"

[ -f "$EXPORT_DIR/index.html" ] || die "No export found. Run ./scripts/export_web.sh first."
command -v node >/dev/null 2>&1 || die "node is required for the browser test."

rm -rf "$OUT"
mkdir -p "$OUT"

step "Starting server on port $PORT"
python3 -m http.server "$PORT" --directory "$EXPORT_DIR" --bind 127.0.0.1 \
  >"$OUT/server.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 40); do
  curl -fsS "http://127.0.0.1:$PORT/index.html" -o /dev/null 2>/dev/null && break
  sleep 0.25
done
curl -fsS "http://127.0.0.1:$PORT/index.html" -o /dev/null \
  || die "server did not come up (see $OUT/server.log)"
ok "server up"

if [ ! -d "$REPO_ROOT/node_modules/playwright" ]; then
  step "Installing playwright"
  ( cd "$REPO_ROOT" && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm i -D --no-audit --no-fund playwright ) \
    >"$OUT/npm.log" 2>&1 || die "could not install playwright (see $OUT/npm.log)"
fi

step "Driving the menus in Chromium"
( cd "$REPO_ROOT" && node scripts/capture_ui.mjs --url "http://127.0.0.1:$PORT" --out "$OUT" ) \
  || die "UI capture failed — see $OUT/ui-report.txt"

step "Captured"
ls -la "$OUT"/*.png | sed 's/^/  /'
printf '\n%sUI screens captured.%s %s\n' "$C_GREEN$C_BOLD" "$C_OFF" "$OUT"
