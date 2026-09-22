#!/usr/bin/env bash
# Serves exports/web/ over HTTP.
#
# The build cannot run from file:// — browsers refuse to instantiate the WASM
# module from that origin — so a server is mandatory even for a quick local look.

source "$(dirname "$0")/lib.sh"

PORT="${PORT:-8080}"
[ -f "$EXPORT_DIR/index.html" ] || die "No export found. Run ./scripts/export_web.sh first."

step "Serving $EXPORT_DIR on http://localhost:$PORT"
printf '  open http://localhost:%s  (Ctrl-C to stop)\n\n' "$PORT"
exec python3 -m http.server "$PORT" --directory "$EXPORT_DIR" --bind 0.0.0.0
