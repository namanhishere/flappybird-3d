class_name BirdState
extends RefCounted

## The replicated value: everything about the bird that crosses the wire,
## twenty times a second.
##
## Compact on purpose. A snapshot that carried anything the client could
## argue with would be a snapshot the client could lie through, so the only
## numbers on it are the ones the host computed.

var x: float = 0.0
var y: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
var score: int = 0
var lives: int = 0
var alive: bool = true
## The host's Game.State, so the client can show the same card the host does.
var game_state: int = 0

func set_values(
		position: Vector2, velocity: Vector2, score_value: int,
		lives_value: int, alive_value: bool, state_value: int) -> void:
	x = position.x
	y = position.y
	vx = velocity.x
	vy = velocity.y
	score = score_value
	lives = lives_value
	alive = alive_value
	game_state = state_value

## The wire form. A flat Array rather than a Dictionary so the order is
## positional and both peers cannot disagree about what field three is.
func to_payload() -> Array:
	return [x, y, vx, vy, score, lives, alive, game_state]

## Reads the wire form, ignoring anything short or malformed rather than
## trusting the payload's length. A truncated unreliable packet must not be
## able to crash the prediction path.
static func from_payload(payload: Variant) -> BirdState:
	var state := BirdState.new()
	var values: Array = payload as Array
	if values.size() < 8:
		return state
	state.x = float(values[0])
	state.y = float(values[1])
	state.vx = float(values[2])
	state.vy = float(values[3])
	state.score = int(values[4])
	state.lives = int(values[5])
	state.alive = bool(values[6])
	state.game_state = int(values[7])
	return state

func position() -> Vector2:
	return Vector2(x, y)

func velocity() -> Vector2:
	return Vector2(vx, vy)

## True when the two states are close enough that reconciliation is a nudge
## rather than a visible snap. Used by the client to distinguish a normal
## correction from a desync it should just accept.
func within_tolerance(other: BirdState, distance: float, speed: float) -> bool:
	return position().distance_to(other.position()) <= distance \
		and velocity().distance_to(other.velocity()) <= speed
