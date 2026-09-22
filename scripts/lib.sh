#!/usr/bin/env bash
# Shared helpers for the dev scripts. Source this, do not execute it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="$REPO_ROOT/game"
EXPORT_DIR="$REPO_ROOT/exports/web"
CAPTURE_DIR="$REPO_ROOT/captures"

# Pinned engine version. Kept here so every script agrees, and so a version
# mismatch is a loud failure rather than a mysterious export bug.
GODOT_VERSION="4.7.2"

if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""; C_OFF=""
fi

step() { printf '%s==>%s %s%s%s\n' "$C_BLUE" "$C_OFF" "$C_BOLD" "$*" "$C_OFF"; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '%sFAIL%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

# Locates the Godot binary. Honours $GODOT so CI can point at its own download.
find_godot() {
  if [ -n "${GODOT:-}" ] && command -v "$GODOT" >/dev/null 2>&1; then
    echo "$GODOT"; return 0
  fi
  for candidate in godot godot4 Godot; do
    if command -v "$candidate" >/dev/null 2>&1; then
      echo "$candidate"; return 0
    fi
  done
  die "Godot not found. Install it (see docs/ENVIRONMENT.md) or set \$GODOT."
}

# Fails unless the export templates for the pinned version are installed. This
# check exists because Godot's own error for missing templates is easy to miss in
# a wall of import output.
require_export_templates() {
  local dir="${HOME}/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
  [ -d "$dir" ] || die "Export templates missing: $dir
  Install them, or run: godot --headless --install-export-templates"
  [ -f "$dir/web_nothreads_release.zip" ] || die \
    "Web (no-threads) release template missing in $dir.
  The web build needs it: thread support is off so the game runs on static
  hosts that cannot send COOP/COEP headers."
}

# Greps Godot's output for the error shapes that do not set a non-zero exit code.
# Godot will happily exit 0 with a broken project, so the log is the real signal.
assert_no_godot_errors() {
  local log="$1"
  local patterns=(
    'SCRIPT ERROR'
    'Parse Error'
    'Parser Error'
    'Compile Error'
    'Failed to load script'
    'Cannot open file'
    'Condition ".*" is true'
    'Invalid call'
    'Invalid access'
    'Attempt to call'
    'Nonexistent function'
    'Identifier not found'
  )
  local found=0
  for p in "${patterns[@]}"; do
    if grep -qE "$p" "$log"; then
      found=1
      printf '%s--- matched: %s%s\n' "$C_RED" "$p" "$C_OFF" >&2
      grep -nE "$p" "$log" | head -20 >&2
    fi
  done
  [ "$found" -eq 0 ] || die "Godot reported errors (see above). Full log: $log"
}
