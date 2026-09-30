class_name FlightModel
extends RefCounted

## The bird's flight physics, as a pure value object.
##
## It holds no nodes, touches no engine state and is stepped with an exact
## delta, so a headless test can run a thousand frames in microseconds and get
## bit-identical results every time. The Player node owns one of these and
## copies the result onto its own transform.
##
## Two axes, one bird. The flap axis is vertical and belongs to one player; the
## steer axis is lateral and belongs to the other. Neither axis can move the
## other, which is what makes "two people, one bird" a real constraint rather
## than a shared hotkey.

var position_y: float = 0.0
var velocity_y: float = 0.0
## Sideways position and speed: the steer axis.
var position_x: float = 0.0
var velocity_x: float = 0.0
## Steer demand in -1..1, set once per step by whichever player owns the axis.
var steer_input: float = 0.0
## Force written in by the world, in m/s^2. x shoves sideways, y shoves
## vertically. The hunter drone's wake is the only thing that uses it today.
var external_accel := Vector2.ZERO
var flap_count: int = 0

## Returns the bird to a known state. Called on spawn and on every restart.
func reset(start_y: float = GameConfig.START_Y) -> void:
	position_y = start_y
	velocity_y = 0.0
	position_x = 0.0
	velocity_x = 0.0
	steer_input = 0.0
	external_accel = Vector2.ZERO
	flap_count = 0


## A detached copy of the model, so a predictor can run it forward without
## disturbing the bird it is predicting for. Written out field by field
## rather than relying on Object.duplicate(), so adding a field to the model
## and forgetting the copy is a visible omission rather than a silent one.
func copy() -> FlightModel:
	var clone := FlightModel.new()
	clone.position_y = position_y
	clone.velocity_y = velocity_y
	clone.position_x = position_x
	clone.velocity_x = velocity_x
	clone.steer_input = steer_input
	clone.external_accel = external_accel
	clone.flap_count = flap_count
	return clone

## Applies a single flap: set upward velocity, do not add to it. Flapping
## always gives the same impulse regardless of how fast the bird is already
## moving, which is what makes the game learnable.
func flap() -> void:
	velocity_y = GameConfig.FLAP_IMPULSE
	flap_count += 1

## Sets the steer demand, clamped to the range the axis actually accepts.
func set_steer(value: float) -> void:
	steer_input = clampf(value, -1.0, 1.0)

## Integrates one fixed step of gravity, lateral input, world force and motion.
func step(delta: float) -> void:
	velocity_y = maxf(
		velocity_y + (external_accel.y - GameConfig.GRAVITY) * delta,
		GameConfig.MAX_FALL_SPEED)
	position_y += velocity_y * delta

	# Steer, then the world, then drag, then the hard clamp. The order matters:
	# drag and the clamp bound a long hold, and the clamp has to come last or
	# the world's force could push the bird past the limit.
	velocity_x += (steer_input * GameConfig.LATERAL_ACCEL + external_accel.x) * delta
	velocity_x *= maxf(0.0, 1.0 - GameConfig.LATERAL_DAMPING * delta)
	velocity_x = clampf(velocity_x, -GameConfig.LATERAL_MAX_SPEED, GameConfig.LATERAL_MAX_SPEED)
	position_x += velocity_x * delta

## True once the bird has fallen below the ground plane.
func is_below_floor() -> bool:
	return position_y < GameConfig.FLOOR_Y

## True once the bird has risen above the ceiling plane.
func is_above_ceiling() -> bool:
	return position_y > GameConfig.CEILING_Y
