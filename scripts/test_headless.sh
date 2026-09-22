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

# --- chase fairness counter-test ---------------------------------------------
# The run above proves a competent player escapes the pursuer. That is only half the
# contract: a pursuer that can *never* catch anyone is scenery, and nothing in the
# normal run would reveal it. This stands still and requires a catch.
step "Running chase fairness counter-test (stall)"
STALL_LOG="$LOG_DIR/autopilot_stall.log"
set +e
timeout 180 "$GODOT" --headless --path "$GAME_DIR" \
  res://tests/autopilot_harness.tscn -- --stall 2>&1 | tee "$STALL_LOG" \
  | grep -E '^(mode|outcome|summary|chase)' 
set -e

if grep -q '^AUTOPILOT: PASS' "$STALL_LOG"; then
  ok "a stalled runner is caught — the chase has teeth"
else
  die "stall test failed: the pursuer never caught a stationary runner. See $STALL_LOG"
fi

printf '\n%sGameplay tests passed.%s\n' "$C_GREEN$C_BOLD" "$C_OFF"
