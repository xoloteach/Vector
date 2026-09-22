#!/usr/bin/env bash
# Builds the browser export into exports/web/.
#
# Fails loudly. Godot's exporter exits 0 in several failure modes (missing
# templates, unresolved resources, script errors at pack time), so this script
# checks the produced artefacts rather than trusting the exit code.

source "$(dirname "$0")/lib.sh"

GODOT="$(find_godot)"
export GODOT_SILENCE_ROOT_WARNING=1

PRESET="Web"
LOG_DIR="$REPO_ROOT/exports/tmp"
mkdir -p "$LOG_DIR" "$EXPORT_DIR"
LOG="$LOG_DIR/export_web.log"

step "Godot: $($GODOT --version)"
require_export_templates
ok "export templates present"

step "Importing resources"
"$GODOT" --headless --path "$GAME_DIR" --import >"$LOG" 2>&1 || true
assert_no_godot_errors "$LOG"

step "Exporting preset '$PRESET' -> $EXPORT_DIR"
# Remove previous artefacts so a failed export cannot masquerade as a good one by
# leaving yesterday's files behind.
rm -f "$EXPORT_DIR"/index.* "$EXPORT_DIR"/*.wasm "$EXPORT_DIR"/*.pck \
      "$EXPORT_DIR"/*.js "$EXPORT_DIR"/*.worker.js 2>/dev/null || true

set +e
"$GODOT" --headless --path "$GAME_DIR" \
  --export-release "$PRESET" "$EXPORT_DIR/index.html" >>"$LOG" 2>&1
export_status=$?
set -e

if [ "$export_status" -ne 0 ]; then
  tail -40 "$LOG" >&2
  die "godot --export-release exited $export_status"
fi

step "Verifying artefacts"
required=(index.html index.js index.wasm index.pck)
for f in "${required[@]}"; do
  [ -s "$EXPORT_DIR/$f" ] || { tail -40 "$LOG" >&2; die "missing or empty: $EXPORT_DIR/$f"; }
done
ok "all required files present"

# A threads-enabled build ships an extra worker script and needs COOP/COEP
# headers that GitHub Pages cannot send. Catch that regression here rather than
# as a black screen in a browser.
if [ -f "$EXPORT_DIR/index.worker.js" ]; then
  die "index.worker.js present — the export has thread support enabled.
  Set variant/thread_support=false in game/export_presets.cfg. A threads build
  needs Cross-Origin-Opener-Policy / Cross-Origin-Embedder-Policy headers, which
  static hosts like GitHub Pages do not provide, and it will not boot there."
fi
ok "no-threads build confirmed"

assert_no_godot_errors "$LOG"

step "Result"
( cd "$EXPORT_DIR" && du -ch index.* 2>/dev/null | tail -1 | sed 's/^/  total  /' )
ls -la "$EXPORT_DIR" | sed 's/^/  /'
printf '\n%sWeb export complete.%s\n' "$C_GREEN$C_BOLD" "$C_OFF"
printf '  path : %s\n' "$EXPORT_DIR/index.html"
printf '  serve: ./scripts/serve_web.sh   then open http://localhost:8080\n'
printf '  note : the build will NOT run from file:// — it must be served.\n'
