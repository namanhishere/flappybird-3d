#!/usr/bin/env bash
# Runs the pinned Godot binary against this project, captures the log, and
# fails if the engine reported any error.
#
# The project's success criteria include "zero ERROR lines in any run log", so
# that check lives here rather than in every make target. Warnings are allowed
# and are not treated as failures.
#
# Usage: tools/godot.sh [godot args...]
#   The project directory is supplied automatically. Set GODOT_LOG_LABEL to
#   choose the log filename; otherwise it is derived from the first argument.
#   Set GODOT_TIMEOUT to bound the run -- see the note below.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tools/toolchain.env
source "${SCRIPT_DIR}/toolchain.env"

if [ ! -x "$GODOT_BIN" ]; then
  echo "[godot] ERROR: pinned Godot binary not found at $GODOT_BIN" >&2
  echo "[godot] Run 'make setup' first." >&2
  exit 1
fi

# A scene whose script fails to parse has no code left to call quit(), so the
# engine sits in its main loop forever. Every non-interactive target therefore
# sets GODOT_TIMEOUT, so a parse error becomes a two-second failure that names
# the offending line instead of a ten-minute hang with no output. `make play`
# leaves it unset on purpose, because a human is driving that one.
TIMEOUT_ARGS=()
if [ -n "${GODOT_TIMEOUT:-}" ]; then
  TIMEOUT_ARGS=(timeout --foreground --kill-after=10s "${GODOT_TIMEOUT}s")
fi

LOG_DIR="${PROJECT_DIR}/build/logs"
mkdir -p "$LOG_DIR"
# Most invocations start with an engine flag, which makes a poor filename, so
# the make targets name their own log.
LABEL="${GODOT_LOG_LABEL:-}"
if [ -z "$LABEL" ]; then
  LABEL="$(basename -- "${1:-run}")"
fi
LOG="${LOG_DIR}/${LABEL}.log"

"${TIMEOUT_ARGS[@]}" "$GODOT_BIN" --path "$PROJECT_DIR" "$@" 2>&1 | tee "$LOG"
GODOT_STATUS=${PIPESTATUS[0]}

# `timeout` exits 124 when it fires and 137 when it had to escalate to a kill.
if [ "$GODOT_STATUS" -eq 124 ] || [ "$GODOT_STATUS" -eq 137 ]; then
  echo "[godot] FAILED: timed out after ${GODOT_TIMEOUT}s (see $LOG)" >&2
  exit 124
fi

# --- error gate -------------------------------------------------------------
# Godot prefixes engine problems with "ERROR:", script problems with
# "SCRIPT ERROR", and push_error() output with "USER ERROR"/"USER SCRIPT ERROR".
ERRORS="$(grep -nE 'SCRIPT ERROR|^ERROR:|USER SCRIPT ERROR|USER ERROR' "$LOG" || true)"

if [ -n "$ERRORS" ]; then
  echo "[godot] FAILED: engine reported errors:" >&2
  printf '%s\n' "$ERRORS" | head -40 >&2
  exit 1
fi

if [ "$GODOT_STATUS" -ne 0 ]; then
  echo "[godot] FAILED: exit code $GODOT_STATUS (see $LOG)" >&2
  exit "$GODOT_STATUS"
fi

echo "[godot] ok: no errors in $LOG"
