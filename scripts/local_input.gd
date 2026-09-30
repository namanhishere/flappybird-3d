class_name LocalInput
extends RefCounted

## Reads the two players' keys and turns them into a BirdIntent per tick.
##
## Deliberately a plain object with no node and no state machine of its own.
## The game owns the flapped flag rather than polling an action, so a press
## that arrives between two fixed steps is never lost and never double-counted
## -- and so the headless test suite can drive the whole input path by
## synthesising one InputEvent, with no keyboard in sight.
##
## A flap is a discrete press and therefore goes through the event handler.
## Steer is continuous state, so it is polled from the two actions each step:
## the latest reading is simply the current truth, and a dropped sample costs
## one frame of smoothness and nothing else.

var _flap_queued: bool = false

func clear() -> void:
	_flap_queued = false

## Called by the game when a flap action arrives as an input event.
func queue_flap() -> void:
	_flap_queued = true

## True if a flap was pressed since the last call. Reading it consumes it.
func take_flap() -> bool:
	if not _flap_queued:
		return false
	_flap_queued = false
	return true

## The intent the local player is asking for on one axis this tick.
##
## `axis` decides which half of the intent is filled. Passing the flap axis
## gives a flap request; passing the steer axis gives a steer value. Neither
## ever touches the other's field, which is what makes the two axes
## independent in every mode rather than only in the one the test remembers.
func intent_for(axis: int) -> BirdIntent:
	var intent := BirdIntent.new()
	if axis == MatchConfig.Role.STEER:
		intent.set_steer(steer())
	return intent

## The current sideways demand, -1 to 1. Both keys held is a hard stop rather
## than the difference of two held keys, so a player who mashes both is
## stationary instead of jittering.
func steer() -> float:
	var right := Input.is_action_pressed(InputActions.ACTION_STEER_RIGHT)
	var left := Input.is_action_pressed(InputActions.ACTION_STEER_LEFT)
	if right == left:
		return 0.0
	return 1.0 if right else -1.0
