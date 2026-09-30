class_name Protocol
extends RefCounted

## Every wire constant in one file.
##
## Both peers import this, so renaming an RPC or moving a channel between
## reliable and unreliable is a load error in both builds at once, rather than
## a silent no-op on the side that was not rebuilt.

## ENet channel 0 is reliable, channel 1 is unreliable. Godot's reliable mode
## is already ordered -- ENet guarantees it -- which is what the design wanted
## from it, so "reliable_ordered" in the plan is spelled "reliable" here.
##
## The split is deliberate and is the single most important decision in the netcode:
## a dropped flap is a missing climb impulse, which on a tight gap is death,
## while a dropped steer packet is superseded by the next one 16 ms later and
## costs nothing but a frame of smoothness.
const CHANNEL_RELIABLE := 0
const CHANNEL_UNRELIABLE := 1

## Snapshots per second the host publishes to the client.
const SNAPSHOT_HZ := 20
## Shortest gap the authority accepts between two accepted flaps from one peer.
const MIN_FLAP_INTERVAL := 0.06
## Flaps one peer may send per second, past the first. Bounds the cost of
## head-of-line blocking on the reliable channel.
const FLAP_BUDGET_PER_SECOND := 12

## How many peers a host will accept. One client is the whole design, so this
## is two: the host and the single remote player.
const MAX_CLIENTS := 2
const DEFAULT_PORT := 27015
const LOOPBACK_ADDRESS := "127.0.0.1"

## ENet peer id of a host: the server is always peer 1.
const SERVER_PEER_ID := 1

# --- RPC names ---------------------------------------------------------------

const RPC_SUBMIT_FLAP := &"submit_flap"
const RPC_SUBMIT_STEER := &"submit_steer"
const RPC_PUSH_SNAPSHOT := &"push_snapshot"
const RPC_BEGIN_MATCH := &"begin_match"
const RPC_REQUEST_START := &"request_start"
const RPC_REQUEST_ROLE := &"request_role"
const RPC_END_MATCH := &"end_match"
const RPC_ROLE_REJECTED := &"role_rejected"

## Every RPC the protocol defines. Both peers must agree on this set.
const RPC_NAMES := [
	RPC_SUBMIT_FLAP, RPC_SUBMIT_STEER, RPC_PUSH_SNAPSHOT, RPC_BEGIN_MATCH,
	RPC_REQUEST_START, RPC_REQUEST_ROLE, RPC_END_MATCH, RPC_ROLE_REJECTED,
]

## Everything a client is allowed to say to the host.
##
## None of these can carry a position, a score or a life count. The client has
## no vocabulary for lying about them: the only numbers it can influence are
## the ones the host then re-validates for rate limit, axis ownership and NaN.
const CLIENT_TO_SERVER := [
	RPC_SUBMIT_FLAP, RPC_SUBMIT_STEER, RPC_REQUEST_START, RPC_REQUEST_ROLE,
]

## Everything only the host is allowed to say.
const SERVER_TO_CLIENT := [
	RPC_PUSH_SNAPSHOT, RPC_BEGIN_MATCH, RPC_END_MATCH, RPC_ROLE_REJECTED,
]

## Seconds between snapshot publishes.
static func snapshot_interval() -> float:
	return 1.0 / float(SNAPSHOT_HZ)

## Human-readable name of a role id, for the HUD and the wire log.
static func role_name(role_id: int) -> String:
	match role_id:
		0: return "FLAP"
		1: return "STEER"
	return "?"
