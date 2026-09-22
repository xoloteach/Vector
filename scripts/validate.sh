#!/usr/bin/env bash
# Headless project validation: imports every resource and fails on any script or
# scene error.
#
# Godot exits 0 even when scripts fail to parse, so a plain "did it run" check is
# worthless. This script scrapes the log for error signatures instead.
#
# The import runs twice on a cold cache: the first pass generates .import files
# and UIDs, and resources that reference those can only resolve on the second.

source "$(dirname "$0")/lib.sh"

GODOT="$(find_godot)"
LOG_DIR="$REPO_ROOT/exports/tmp"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/validate.log"

step "Godot: $($GODOT --version)"

step "Importing resources (pass 1)"
"$GODOT" --headless --path "$GAME_DIR" --import >"$LOG" 2>&1 || true

step "Importing resources (pass 2)"
"$GODOT" --headless --path "$GAME_DIR" --import >>"$LOG" 2>&1 || true

step "Checking for script and scene errors"
assert_no_godot_errors "$LOG"
ok "no import errors"

# --- parse every script -------------------------------------------------------
# `--import` does NOT parse GDScript bodies, so a plain import pass happily
# reports success on a project full of syntax errors. That gap let a duplicate
# local variable reach a browser build, where it surfaced as a blank canvas and
# cost a full export-and-capture cycle to diagnose.
#
# Done from inside a running project (not `--check-only --script`) so autoloads
# and global class names are registered; otherwise every script that references
# the `Game` singleton reports a spurious "Identifier not found".
step "Parsing all GDScript files"
PARSE_LOG="$LOG_DIR/parse.log"
set +e
timeout 120 "$GODOT" --headless --path "$GAME_DIR" \
  res://tests/parse_check.tscn >"$PARSE_LOG" 2>&1
set -e

if ! grep -q '^PARSE CHECK: PASS' "$PARSE_LOG"; then
  grep -E 'Parse Error|Compile Error|SCRIPT ERROR|failed|^  res://' "$PARSE_LOG" | head -40 >&2
  die "GDScript parse errors (see above). Full log: $PARSE_LOG"
fi
ok "$(grep 'scripts checked' "$PARSE_LOG" | head -1)"

# Boot the real main scene for a moment. Parse errors are caught above; this
# catches the much larger class of bugs that only appear once nodes are
# instantiated and _ready() has run.
step "Booting main scene headlessly (3s smoke test)"
BOOT_LOG="$LOG_DIR/boot.log"
timeout 25 "$GODOT" --headless --path "$GAME_DIR" \
  --quit-after 180 res://scenes/Main.tscn >"$BOOT_LOG" 2>&1 || {
  status=$?
  # 124 is timeout's signal that it had to kill the process; anything else is a
  # genuine crash and we want to see the log either way.
  if [ "$status" -ne 124 ]; then
    cat "$BOOT_LOG" >&2
    die "Main scene crashed on boot (exit $status)."
  fi
  warn "boot smoke test hit the timeout rather than exiting cleanly"
}
assert_no_godot_errors "$BOOT_LOG"
ok "main scene boots clean"

printf '\n%sValidation passed.%s  logs: %s\n' "$C_GREEN$C_BOLD" "$C_OFF" "$LOG_DIR"
