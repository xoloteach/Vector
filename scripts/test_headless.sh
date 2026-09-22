#!/usr/bin/env bash
# Runs the autopilot: a bot plays the level end to end and reports whether the
# course is completable.
#
# This is the project's main gameplay gate. It catches softlocks, unclearable
# gaps, momentum-killing geometry and movement regressions in a few seconds with
# no display attached — the class of bug that a compile check cannot see and that
# is expensive to find by hand.

source "$(dirname "$0")/lib.sh"

GODOT="$(find_godot)"
export GODOT_SILENCE_ROOT_WARNING=1
LOG_DIR="$REPO_ROOT/exports/tmp"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/autopilot.log"

step "Refreshing import cache"
"$GODOT" --headless --path "$GAME_DIR" --import >/dev/null 2>&1 || true

step "Running autopilot"
set +e
timeout 240 "$GODOT" --headless --path "$GAME_DIR" \
  res://tests/autopilot_harness.tscn 2>&1 | tee "$LOG" \
  | grep -vE '^\[ *[0-9]+%|DONE|^\s*$'
set -e

# The harness prints an explicit verdict line. Trusting that rather than the exit
# code, because Godot's exit status is unreliable when quitting from script.
if grep -q '^AUTOPILOT: PASS' "$LOG"; then
  ok "course is completable"
else
  die "autopilot failed — see $LOG"
fi

assert_no_godot_errors "$LOG"
printf '\n%sGameplay test passed.%s\n' "$C_GREEN$C_BOLD" "$C_OFF"
