#!/usr/bin/env bash
# The online check that net-test cannot make: a real host and a real client,
# in two processes, over a real loopback socket.
#
# net-test drives both peers in one process through the real handlers with no
# socket open, which is what makes it fast and deterministic. What it cannot
# prove is that ENet works, that the RPC annotations are right, or that the
# channels behave. This does, in about fifteen seconds, and it checks the thing
# the whole design rests on -- that the course arrives as a single integer and
# no pipe is ever sent.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tools/toolchain.env
source "${SCRIPT_DIR}/toolchain.env"

PORT="${NET_SMOKE_PORT:-27020}"
CLIENT_SECONDS="${NET_SMOKE_SECONDS:-12}"
LOG_DIR="${PROJECT_DIR}/build/logs"
HOST_LOG="${LOG_DIR}/host.log"
CLIENT_LOG="${LOG_DIR}/client.log"
mkdir -p "$LOG_DIR"
rm -f "$HOST_LOG" "$CLIENT_LOG"

fail() {
  echo "[net-smoke] FAILED: $*" >&2
  kill "${HOST_PID:-0}" 2>/dev/null
  exit 1
}

cleanup() {
  kill "${HOST_PID:-0}" 2>/dev/null
  wait "${HOST_PID:-0}" 2>/dev/null
}
trap cleanup EXIT

# --- the host ----------------------------------------------------------------
# --autoplay so the host flies its own bird: this check is about protocol
# shape -- ENet, the channel annotations, the handshake, the snapshot rate --
# and not about two people playing. Whether a client's steer moves the host's
# bird is proved by `make net-test`, which drives that path directly.
# --realtime caps the frame rate, which matters more than it looks: headless
# Godot runs frames as fast as the CPU allows, so without it a "twelve second"
# run finishes in about one and the two peers drift apart in real time. This is
# a socket test, so the seconds have to be real ones.
"$GODOT_BIN" --headless --path "$PROJECT_DIR" -- \
  --mode=host --port="$PORT" --skill=unfair --autoplay --realtime \
  > "$HOST_LOG" 2>&1 &
HOST_PID=$!

# Wait for the socket rather than sleeping a guessed interval: a fixed sleep is
# a race on a loaded machine, and a race that only fails sometimes is a test
# nobody trusts.
for _ in $(seq 1 100); do
  if grep -q "NET host listening" "$HOST_LOG" 2>/dev/null; then break; fi
  if ! kill -0 "$HOST_PID" 2>/dev/null; then
    fail "the host exited before it started listening; see $HOST_LOG"
  fi
  sleep 0.1
done
grep -q "NET host listening" "$HOST_LOG" || fail "the host never reported listening"
echo "[net-smoke] host listening on port $PORT"

# --- the client --------------------------------------------------------------
# --quit-after counts frames, and headless runs them faster than real time, so
# the rate below is divided by the wall clock this actually took rather than by
# the nominal duration.
CLIENT_STARTED=$(date +%s)
"$GODOT_BIN" --headless --path "$PROJECT_DIR" \
  --quit-after $((CLIENT_SECONDS * 60)) -- \
  --mode=client --address=127.0.0.1 --port="$PORT" --realtime \
  > "$CLIENT_LOG" 2>&1
CLIENT_STATUS=$?
ELAPSED=$(( $(date +%s) - CLIENT_STARTED ))
[ "$ELAPSED" -gt 0 ] || ELAPSED=1
if [ "$CLIENT_STATUS" -ne 0 ]; then
  fail "the client exited $CLIENT_STATUS; see $CLIENT_LOG"
fi

# --- what actually crossed the wire ------------------------------------------
# The host has to have seen a peer arrive, or nothing was sent to anyone.
grep -q "NET host listening" "$HOST_LOG" || fail "the host log is missing its banner"

MATCHES=$(grep -c "WIRE begin_match" "$CLIENT_LOG" || true)
[ "$MATCHES" -eq 1 ] || fail "expected exactly one begin_match on the wire, got $MATCHES"

SNAPSHOTS=$(grep -c "WIRE snapshot" "$CLIENT_LOG" || true)
# A band, not a floor. The budget is 20 Hz and the reliable/unreliable split
# means a few packets are allowed to be lost, so anything under about 15 a
# second means the feed is not being spent, and anything much over 20 means a
# host is flooding the socket -- which is a real bug this check exists to
# catch, and a floor on its own would sail straight past it.
FLOOR=$((ELAPSED * 15))
CEILING=$((ELAPSED * 25))
[ "$SNAPSHOTS" -ge "$FLOOR" ] \
  || fail "expected at least $FLOOR snapshots in ${ELAPSED}s, got $SNAPSHOTS"
[ "$SNAPSHOTS" -le "$CEILING" ] \
  || fail "expected at most $CEILING snapshots in ${ELAPSED}s, got $SNAPSHOTS"

# The claim the whole design rests on: the seed came over once and no pipe
# followed. Anything in the wire log that is not begin_match, snapshot or steer
# would mean something else was transmitted.
STRAY=$(grep "^WIRE " "$CLIENT_LOG" \
  | grep -vcE "^WIRE (begin_match|snapshot|steer) " || true)
[ "$STRAY" -eq 0 ] || fail "$STRAY lines on the wire were not one of the three known messages"

# The client must have joined the host's course rather than inventing one.
SEED_ON_WIRE=$(grep -o "seed=[0-9-]*" "$CLIENT_LOG" | head -1)
[ -n "$SEED_ON_WIRE" ] || fail "no seed arrived on the wire"

# And nothing anywhere may have errored.
if grep -qE 'SCRIPT ERROR|^ERROR:|USER SCRIPT ERROR|USER ERROR' "$HOST_LOG" "$CLIENT_LOG"; then
  fail "the engine reported errors; see $HOST_LOG and $CLIENT_LOG"
fi

RATE=$(awk "BEGIN { printf \"%.1f\", $SNAPSHOTS / $ELAPSED }")
echo "[net-smoke] ok: 1 begin_match ($SEED_ON_WIRE), $SNAPSHOTS snapshots at ${RATE}/s over ${ELAPSED}s, nothing else on the wire"
