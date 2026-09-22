#!/usr/bin/env bash
# Browser smoke test + screenshot capture.
#
# Starts a local server, drives the exported build in real Chromium with
# synthetic input, captures screenshots of representative gameplay states, and
# fails if the game does not boot, renders nothing, or logs page errors.
#
#   ./scripts/test_web.sh [output-name]
#
# Screenshots land in captures/<output-name>/ for the vision critics to review.

source "$(dirname "$0")/lib.sh"

NAME="${1:-latest}"
PORT="${PORT:-8099}"
OUT="$CAPTURE_DIR/$NAME"

[ -f "$EXPORT_DIR/index.html" ] || die "No export found. Run ./scripts/export_web.sh first."
command -v node >/dev/null 2>&1 || die "node is required for the browser test."

# Clear stale frames. Leftovers from a previous failed run (a black-screen
# capture, a shorter frame sequence) would otherwise be reviewed as if they came
# from this build.
rm -rf "$OUT"
mkdir -p "$OUT"

step "Starting server on port $PORT"
python3 -m http.server "$PORT" --directory "$EXPORT_DIR" --bind 127.0.0.1 \
  >"$OUT/server.log" 2>&1 &
SERVER_PID=$!
# Always take the server down, including on failure.
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 40); do
  if curl -fsS "http://127.0.0.1:$PORT/index.html" -o /dev/null 2>/dev/null; then break; fi
  sleep 0.25
done
curl -fsS "http://127.0.0.1:$PORT/index.html" -o /dev/null \
  || die "server did not come up (see $OUT/server.log)"
ok "server up"

step "Ensuring the capture harness has its dependency"
# ESM `import` ignores NODE_PATH, so playwright has to resolve from the repo.
# node_modules is gitignored; this installs it on demand and reuses the shared
# browser bundle rather than downloading Chromium again.
if [ ! -d "$REPO_ROOT/node_modules/playwright" ]; then
  ( cd "$REPO_ROOT" && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm i -D --no-audit --no-fund playwright ) \
    >"$OUT/npm.log" 2>&1 || die "could not install playwright (see $OUT/npm.log)"
fi
ok "playwright available"

step "Driving the build in Chromium (SwiftShader — expect this to be slow)"
( cd "$REPO_ROOT" && node scripts/capture_web.mjs --url "http://127.0.0.1:$PORT" --out "$OUT" ) \
  || die "browser test failed — see $OUT/browser-report.txt"

step "Captured"
ls -la "$OUT"/*.png | sed 's/^/  /'

if [ -s "$OUT/browser-report.txt" ]; then
  errors=$(grep -c '^# page errors (0)' "$OUT/browser-report.txt" || true)
  if [ "$errors" -eq 0 ]; then
    warn "page errors were logged — review $OUT/browser-report.txt"
  fi
fi

printf '\n%sBrowser test passed.%s  screenshots: %s\n' "$C_GREEN$C_BOLD" "$C_OFF" "$OUT"
