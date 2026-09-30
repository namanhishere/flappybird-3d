class_name HunterModel
extends RefCounted

## The drone's kinematics, as a pure value object.
##
## Exactly like FlightModel, and for the same reason: no nodes, an exact delta,
## and a copy a test can step a thousand times in microseconds. The HunterDrone
## node owns one of these and copies the result onto its own transform.

## Where the drone is, in the same space as the bird.
var position := Vector3.ZERO
var velocity := Vector3.ZERO

func reset(at: Vector3) -> void:
	position = at
	velocity = Vector3.ZERO

## One fixed step: thrust, then drag, then the speed clamp, then motion.
##
## The drag and the clamp are what make the drone a *hunter* rather than a
## projectile. Without them it would accelerate without limit and every
## approach would be a straight line at ever-increasing speed; with them it
## tops out at HUNTER_MAX_SPEED, so where it wants to be still matters.
func step(delta: float, thrust: Vector3) -> void:
	velocity += thrust * delta
	velocity *= maxf(0.0, 1.0 - GameConfig.HUNTER_DRAG * delta)
	velocity = velocity.limit_length(GameConfig.HUNTER_MAX_SPEED)
	position += velocity * delta

## True once the drone is close enough to the bird to count as a catch.
func is_touching(bird: Vector3) -> bool:
	return Vector2(position.x - bird.x, position.y - bird.y).length() \
		<= GameConfig.HUNTER_CONTACT_RADIUS
