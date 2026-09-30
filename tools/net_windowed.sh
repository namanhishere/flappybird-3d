#!/usr/bin/env bash
# The full two-window acceptance check: a real host and a real client, in two
# windows on this display, over a real loopback socket, for a full minute --
# and the client's own frames captured so the shared bird can be looked at
# rather than assumed.
#
# `net-smoke` proves the protocol over the same socket with no windowing, and
# it is where the 20 Hz rate is pinned. This proves the thing the demo shows:
# two windows, one bird, and a wire log that says so.
#
# Two passes, because they are genuinely different claims and because the
# movie writer encodes at roughly 190 ms a frame: capturing a whole minute would
# be eleven minutes of encoding to prove what ten seconds of capture proves.
# The first pass runs the full minute and checks the wire; the second captures
# a few seconds and is the visual evidence.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tools/toolchain.env
source "${SCRIPT_DIR}/toolchain.env"

PORT="${NET_WINDOWED_PORT:-27021}"
SESSION_SECONDS="${NET_WINDOWED_SECONDS:-60}"
CAPTURE_FRAMES="${NET_WINDOWED_CAPTURE_FRAMES:-300}"
SHOTS="${PROJECT_DIR}/build/shots/net"
LOG_DIR="${PROJECT_DIR}/build/logs"
HOST_LOG="${LOG_DIR}/host.log"
CLIENT_LOG="${LOG_DIR}/client.log"
mkdir -p "$LOG_DIR"
rm -rf "$SHOTS"
mkdir -p "$SHOTS"
rm -f "$HOST_LOG" "$CLIENT_LOG"

if [ -z "${DISPLAY:-}" ]; then
  echo "[net-windowed] SKIPPED: no DISPLAY, so two windows cannot be shown" >&2
  exit 2
fi

HOST_PID=""

fail() {
  echo "[net-windowed] FAILED: $*" >&2
  exit 1
}

cleanup() {
  if [ -n "$HOST_PID" ]; then
    kill "$HOST_PID" 2>/dev/null
    wait "$HOST_PID" 2>/dev/null
  fi
}
trap cleanup EXIT

# --- the host window ---------------------------------------------------------
# --autoplay because nobody is at this keyboard. Two humans play this the
# obvious way, in two terminals, with `make serve` and `make client`; an
# automated check has to put a pilot on the host or the run ends on the floor
# before the client has drawn a frame.
start_host() {
  "$GODOT_BIN" --path "$PROJECT_DIR" --realtime -- \
    --mode=host --port="$PORT" --skill=unfair --overlay --autoplay \
    > "$HOST_LOG" 2>&1 &
  HOST_PID=$!
  for _ in $(seq 1 200); do
    if grep -q "NET host listening" "$HOST_LOG" 2>/dev/null; then return 0; fi
    if ! kill -0 "$HOST_PID" 2>/dev/null; then
      fail "the host exited before it started listening; see $HOST_LOG"
    fi
    sleep 0.1
  done
  fail "the host never reported listening; see $HOST_LOG"
}

start_host
echo "[net-windowed] host window up, listening on $PORT"

# --- the minute ---------------------------------------------------------------
# Bounded by the wall clock rather than by a frame count. Two rendered windows
# are renderer-bound, so a client asked for 3600 frames may take much longer
# than a minute to get there on a software rasteriser -- and the claim worth
# making is that the two windows stay in sync for a minute, not that either one
# manages a particular frame rate.
CLIENT_STARTED=$(date +%s)
timeout --signal=INT "$SESSION_SECONDS" \
  "$GODOT_BIN" --path "$PROJECT_DIR" --realtime \
  -- --mode=client --address=127.0.0.1 --port="$PORT" --overlay \
  > "$CLIENT_LOG" 2>&1 || true
ELAPSED=$(( $(date +%s) - CLIENT_STARTED ))
echo "[net-windowed] the ${SESSION_SECONDS}s session lasted ${ELAPSED}s"

# --- what actually crossed the wire ------------------------------------------
MATCHES=$(grep -c "WIRE begin_match" "$CLIENT_LOG" || true)
[ "$MATCHES" -eq 1 ] || fail "expected exactly one begin_match, got $MATCHES"

SEED_ON_WIRE=$(grep -o "seed=[0-9-]*" "$CLIENT_LOG" | head -1 | cut -d= -f2)
[ -n "${SEED_ON_WIRE:-}" ] || fail "the begin_match carried no seed"

SNAPSHOTS=$(grep -c "WIRE snapshot" "$CLIENT_LOG" || true)

[ "$ELAPSED" -ge $((SESSION_SECONDS - 3)) ] \
  || fail "the session lasted ${ELAPSED}s, short of the ${SESSION_SECONDS}s required"

# Only a floor here, and deliberately not the 20 Hz band that `net-smoke`
# pins. Snapshots are paced by the wall clock, and a host rendering a window
# with an AI on the flap axis is renderer-bound, so it cannot always reach
# 20 a second no matter what the protocol does. This check is here to prove two
# real windows stay in sync and that the wire is still only the three known
# messages; the rate is proven headlessly, where it is a property of the code
# rather than of the graphics card.
[ "$SNAPSHOTS" -ge $((ELAPSED / 2)) ] \
  || fail "the feed stalled: only $SNAPSHOTS snapshots in ${ELAPSED}s"

# The claim the whole design rests on: the course came over once as a single
# integer and not one pipe followed it.
STRAY=$(grep "^WIRE " "$CLIENT_LOG" \
  | grep -vcE "^WIRE (begin_match|snapshot|steer) " || true)
[ "$STRAY" -eq 0 ] || fail "$STRAY wire lines were not one of the three known messages"

if grep -qE 'SCRIPT ERROR|^ERROR:|USER SCRIPT ERROR|USER ERROR' "$HOST_LOG" "$CLIENT_LOG"; then
  fail "the engine reported errors; see $HOST_LOG and $CLIENT_LOG"
fi

# --- the visual proof --------------------------------------------------------
# --write-movie records exactly what the player would see. A two-window claim
# that has never been looked at is a claim about logs rather than about a
# game.
#
# A fresh host for this pass, because the minute above will have used up the
# pilot's five lives and a client joining a finished match only ever gets to
# photograph a game-over card. A card does show the roles correctly, but "both
# HUDs live" means a run in progress.
kill "$HOST_PID" 2>/dev/null
wait "$HOST_PID" 2>/dev/null
HOST_PID=""
rm -f "$HOST_LOG"
start_host
echo "[net-windowed] fresh host up, capturing a live match"

"$GODOT_BIN" --path "$PROJECT_DIR" --realtime \
  --write-movie "${SHOTS}/client.png" --fixed-fps 60 \
  -- --mode=client --address=127.0.0.1 --port="$PORT" --overlay \
  --frames="$CAPTURE_FRAMES" > "${LOG_DIR}/client_capture.log" 2>&1 \
  || fail "the capturing client failed; see ${LOG_DIR}/client_capture.log"

FRAMES=$(find "$SHOTS" -name '*.png' | wc -l)
[ "$FRAMES" -gt 100 ] || fail "expected a few hundred captured frames, got $FRAMES"

RATE=$(awk "BEGIN { printf \"%.1f\", $SNAPSHOTS / $ELAPSED }")
echo "[net-windowed] ok: seed=$SEED_ON_WIRE, $SNAPSHOTS snapshots at ${RATE}/s over ${ELAPSED}s,"
echo "               nothing else on the wire, and $FRAMES frames in $SHOTS"
