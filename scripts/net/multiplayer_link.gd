extends Node
class_name MultiplayerLink

## The wire. Owns the ENet peer, declares the eight RPCs, and turns them into
## signals. It contains no game logic at all.
##
## The split is deliberate. Everything that decides *whether* a message is
## acceptable lives in Authority, and everything that decides *what it means*
## lives in Game; this file's whole job is moving bytes and naming them. That is
## what lets `make net-test` drive a host and a client through the real
## replication path with no socket open, and it is why the authority rules can
## be unit tested without a network in the room.
##
## Both peers load the same main.tscn, so this node is at the same path on both
## and the RPCs need no explicit path.

## Emitted when the other peer sends input. The payload is unvalidated: it is
## the receiver's job to decide whether to believe it.
signal intent_received(flap: bool, steer: float)
## Emitted with the host's authoritative state, twenty times a second.
signal snapshot_received(payload: Array)
## Emitted once, before the countdown, with everything needed to build the
## same course locally.
signal match_received(seed_value: int, host_role: int, client_role: int, skill: int)
## A peer has said hello, and is waiting to be told what it is flying.
signal start_requested(peer_id: int)
## A peer has claimed an axis.
signal role_requested(role: int, peer_id: int)
## Emitted when the host refuses this peer's claim to an axis. Not called
## `role_rejected`, because that is the RPC's name and a signal cannot share it.
signal role_was_rejected()
## Emitted when a peer's connection appears or goes away.
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

## Set by host() or join(). Null while the link is not connected, and in a
## headless test that drives the two peers in process.
var peer: ENetMultiplayerPeer = null
## True once this process is listening.
var is_host: bool = false
## How many steer messages have been logged, so the log shows the first few
## and then goes quiet instead of repeating "still here" twenty times a second.
var _steer_lines: int = 0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

# --- opening and closing ----------------------------------------------------

## Opens a listening socket. The host is always peer 1, which is why a client
## only ever addresses peer 1.
func host(port: int = Protocol.DEFAULT_PORT) -> Error:
	var server := ENetMultiplayerPeer.new()
	var result := server.create_server(port, Protocol.MAX_CLIENTS)
	if result != OK:
		peer = null
		is_host = false
		return result
	peer = server
	is_host = true
	multiplayer.multiplayer_peer = peer
	return OK

## Dials a host. Only the loopback address is used by the project's own targets;
## anything else is the operator's choice and nothing in here assumes it is
## reachable.
func join(address: String, port: int = Protocol.DEFAULT_PORT) -> Error:
	var client := ENetMultiplayerPeer.new()
	var result := client.create_client(address, port)
	if result != OK:
		peer = null
		is_host = false
		return result
	peer = client
	is_host = false
	multiplayer.multiplayer_peer = peer
	return OK

func close() -> void:
	if peer != null:
		peer.close()
	peer = null
	is_host = false
	multiplayer.multiplayer_peer = null

## True when there is a peer on the other end.
func connected() -> bool:
	if peer == null or multiplayer.multiplayer_peer == null:
		return false
	return not multiplayer.get_peers().is_empty()

## The peer to address, or -1 if there is nobody to address.
##
## Zero means "the other peer", resolved here rather than at the call site,
## because the two directions do not share a target. A client only ever talks to
## the host, which is peer 1. A host is peer 1 itself, so the client is
## whatever else is connected -- and scanning for "not me" is not enough,
## because a host's own id is not always reported while the socket is still
## settling. Picking the wrong one makes the host address its snapshots to
## itself, which the engine refuses and a two-process test reports as zero
## packets.
func _target(explicit: int) -> int:
	if explicit > 0:
		return explicit
	if multiplayer.multiplayer_peer == null:
		return -1
	if not is_host:
		return Protocol.SERVER_PEER_ID
	for peer_id in multiplayer.get_peers():
		if peer_id != Protocol.SERVER_PEER_ID:
			return peer_id
	return -1

# --- sending ----------------------------------------------------------------
#
# Each sender resolves its own destination. The resolution is shared as
# `_target`, but the call itself is not: an RPC is an `Rpc` object, not a
# Callable, so there is nothing to pass a helper.

## A flap, reliable and ordered. A dropped flap is a missing climb impulse and
## on a tight gap it is death, so it is the one message that cannot afford to
## be lost.
func send_flap(to: int = 0) -> void:
	if peer == null:
		return
	var dest := _target(to)
	if dest > 0:
		submit_flap.rpc_id(dest)

## Steer, unreliable. It is continuous state, so the next packet supersedes the
## last one and a dropped packet costs a frame of smoothness and nothing else.
func send_steer(value: float, to: int = 0) -> void:
	if peer == null:
		return
	var dest := _target(to)
	if dest > 0:
		submit_steer.rpc_id(dest, value)

## The whole course, as one integer, once. Everything after this is the host's
## twenty snapshots a second: no pipe is ever transmitted.
func send_match(seed_value: int, host_role: int, client_role: int, skill: int,
		to: int = 0) -> void:
	if peer == null:
		return
	var dest := _target(to)
	if dest > 0:
		begin_match.rpc_id(dest, seed_value, host_role, client_role, skill)

func send_snapshot(payload: Array, to: int = 0) -> void:
	if peer == null:
		return
	var dest := _target(to)
	if dest > 0:
		push_snapshot.rpc_id(dest, payload)

func send_end(reason: String, to: int = 0) -> void:
	if peer == null:
		return
	var dest := _target(to)
	if dest > 0:
		end_match.rpc_id(dest, reason)

func send_role_rejected(to: int = 0) -> void:
	if peer == null:
		return
	var dest := _target(to)
	if dest > 0:
		role_rejected.rpc_id(dest)

func send_start_request(to: int = 0) -> void:
	if peer == null:
		return
	var dest := _target(to)
	if dest > 0:
		request_start.rpc_id(dest)

func send_role_request(role: int, to: int = 0) -> void:
	if peer == null:
		return
	var dest := _target(to)
	if dest > 0:
		request_role.rpc_id(dest, role)

# --- receiving --------------------------------------------------------------

## Every `receive_*` method is the body of the matching RPC, and is public so
## that a test can drive a real host and a real client through the real signal
## handlers with no sockets open at all. One inbound path rather than eight
## copies of it.
func receive_flap() -> void:
	intent_received.emit(true, 0.0)

func receive_steer(value: float) -> void:
	# Logged sparingly: steer is a continuous state, and every message after the
	# first few says only "still here".
	_steer_lines += 1
	if _steer_lines <= 3:
		print("WIRE steer %.3f" % value)
	intent_received.emit(false, value)

func receive_snapshot(payload: Array) -> void:
	# One line per snapshot, on purpose. The wire log is the evidence for the
	# central claim of the whole design -- one integer of course, then the
	# bird's position twenty times a second, and not one pipe -- and a claim
	# nobody can grep for is not a claim.
	print("WIRE snapshot ", payload)
	snapshot_received.emit(payload)

func receive_match(seed_value: int, host_role: int, client_role: int, skill: int) -> void:
	print("WIRE begin_match seed=%d host_role=%s client_role=%s skill=%s" % [
		seed_value, Protocol.role_name(host_role), Protocol.role_name(client_role),
		SkillProfile.level_name(skill)])
	match_received.emit(seed_value, host_role, client_role, skill)

func receive_start(from: int) -> void:
	start_requested.emit(from)

func receive_role(role: int, from: int) -> void:
	role_requested.emit(role, from)

func receive_end(_reason: String) -> void:
	pass

func receive_role_rejected() -> void:
	role_was_rejected.emit()

# --- the eight RPCs ---------------------------------------------------------
#
# Declared with explicit annotations rather than the `func.rpc(...)` builder,
# because the annotation is checked at parse time and the builder is not. The
# RPC's name on the wire is the function's name, so the functions here are
# named exactly as Protocol names them -- which is the point of having those
# constants: renaming a message is a load error on both peers at once rather
# than a silent no-op on the side nobody rebuilt. The channel argument is the
# third: 0 is reliable, 1 is unreliable. Godot spells the reliable mode
# "reliable" rather than "reliable_ordered" because ENet's reliable channel is
# ordered already, which is what the design wanted from it.

@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func submit_flap() -> void:
	receive_flap()

@rpc("any_peer", "call_remote", "unreliable", Protocol.CHANNEL_UNRELIABLE)
func submit_steer(value: float) -> void:
	receive_steer(value)

@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func request_start() -> void:
	receive_start(multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func request_role(role: int) -> void:
	receive_role(role, multiplayer.get_remote_sender_id())

@rpc("authority", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func begin_match(seed_value: int, host_role: int, client_role: int, skill: int) -> void:
	receive_match(seed_value, host_role, client_role, skill)

@rpc("authority", "call_remote", "unreliable", Protocol.CHANNEL_UNRELIABLE)
func push_snapshot(payload: Array) -> void:
	receive_snapshot(payload)

@rpc("authority", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func end_match(reason: String) -> void:
	receive_end(reason)

@rpc("authority", "call_remote", "reliable", Protocol.CHANNEL_RELIABLE)
func role_rejected() -> void:
	receive_role_rejected()

func _on_peer_connected(peer_id: int) -> void:
	peer_joined.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	peer_left.emit(peer_id)
