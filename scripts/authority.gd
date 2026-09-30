class_name Authority
extends RefCounted

## All host-authoritative validation, with no networking anywhere in the file.
##
## Constructed with the role a peer was assigned, it decides what that peer is
## allowed to do. Keeping it pure is the point: "a client asked for the axis it
## does not own and the server said no" is a unit test here rather than an
## integration test with two live sockets.
##
## The rules it enforces:
##   * a peer owns exactly one axis, and anything else is dropped silently;
##   * flaps are rate-limited by a minimum interval and a per-second budget;
##   * steer is clamped, and NaN or infinity is rejected outright;
##   * a dead bird accepts nothing.
##
## There is deliberately no message here that can set a position, a score or a
## life count. The client has no vocabulary for lying about them.

## The axis this peer drives. Anything else it sends is ignored.
var role: int = MatchConfig.Role.FLAP
var alive: bool = true

var _last_flap_at: float = -INF
var _flap_times: Array[float] = []

func configure(assigned_role: int) -> void:
	role = assigned_role
	reset()

func reset() -> void:
	alive = true
	_last_flap_at = -INF
	_flap_times.clear()

## True when this peer may move the given axis at all.
func owns(axis: int) -> bool:
	return axis == role

## Whether the host would take this peer's flap right now.
##
## `now` is the host's clock, supplied by the caller rather than read here, so
## a test can drive a whole second of flaps in microseconds.
func accept_flap(now: float) -> bool:
	if not alive:
		return false
	if now - _last_flap_at < Protocol.MIN_FLAP_INTERVAL:
		return false
	if _flaps_in_last_second(now) > Protocol.FLAP_BUDGET_PER_SECOND:
		return false
	_last_flap_at = now
	_flap_times.append(now)
	return true

## The steer value the host is willing to apply, which is the requested value
## clamped to the axis or 0.0 if the request is not usable. Zero is a real
## steer, not an error: a rejected steer releases the axis rather than freezing
## it, because a peer whose last good value is replayed forever is a peer the
## bird cannot get away from.
func accept_steer(value: float) -> float:
	if not alive:
		return 0.0
	if is_nan(value) or is_inf(value):
		return 0.0
	return clampf(value, -1.0, 1.0)

## Validates a whole intent for this peer and returns the intent that is
## actually safe to apply. The flap and steer fields are filtered separately,
## so a peer that sends a good steer with an over-rate flap keeps its steer.
func apply(intent: BirdIntent, now: float) -> BirdIntent:
	var accepted := BirdIntent.new()
	if intent.flap and accept_flap(now):
		accepted.request_flap()
	accepted.set_steer(accept_steer(intent.steer))
	return accepted


## A peer's request to flap, if it owns the flap axis at all.
##
## A peer that was assigned STEER and is sending flaps anyway gets false, and
## nothing else: no error, no reply, no hint that the host noticed. Telling a
## client that its flap was refused is more information than the client needs
## to work out which half of the bird it is allowed to move.
func request_flap(now: float) -> bool:
	if not owns(MatchConfig.Role.FLAP):
		return false
	return accept_flap(now)

## A peer's steer request, if it owns the steer axis at all.
##
## 0.0 both when the peer does not own the axis and when the request is
## unusable, so a refused steer releases the axis rather than freezing the
## bird at the last value the peer managed to send -- an axis pinned to a
## stale input is an axis the other player can never take back.
func request_steer(value: float) -> float:
	if not owns(MatchConfig.Role.STEER):
		return 0.0
	return accept_steer(value)

## How many flaps this peer has sent in the trailing second. The list is
## pruned rather than merely counted, so a peer that has been playing for an
## hour does not accumulate an hour of timestamps.
func _flaps_in_last_second(now: float) -> int:
	var oldest := now - 1.0
	while not _flap_times.is_empty() and _flap_times[0] < oldest:
		_flap_times.pop_front()
	return _flap_times.size()
