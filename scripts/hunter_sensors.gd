class_name HunterSensors
extends RefCounted

## Everything the hunter is allowed to perceive, as one read-only value.
##
## The mirror image of BirdSensors, and the reason the hunter is as testable as
## the co-pilot: a test hands the brain a sensor set and has fully specified
## the world, with no scene and no nodes.

## Seconds since the run began, and since the last decision.
var delta: float = 0.0
var elapsed: float = 0.0

var bird_position := Vector3.ZERO
## The bird's velocity, in world axes. Its forward component is the only part
## the drone can exploit; the other two are what it is trying to catch.
var bird_velocity := Vector3.ZERO
var drone_position := Vector3.ZERO
var drone_velocity := Vector3.ZERO
## |bird_velocity| flattened into the drone's plane, precomputed because every
## state transition asks for it.
var bird_speed: float = 0.0

var lives_left: int = 0
var score: int = 0
## Seconds since the drone last caught the bird, so it knows when it may try
## again.
var since_contact: float = 0.0

static func from_world(bird: Player, drone: HunterDrone, lives: int, score: int,
		delta: float, elapsed: float) -> HunterSensors:
	var s := HunterSensors.new()
	s.delta = delta
	s.elapsed = elapsed
	var flight := bird.flight
	s.bird_position = bird.position
	s.bird_velocity = Vector3(flight.velocity_x, flight.velocity_y, -bird.forward_speed)
	s.drone_position = drone.position
	s.drone_velocity = drone.model.velocity
	s.bird_speed = Vector2(flight.velocity_x, flight.velocity_y).length()
	s.lives_left = lives
	s.score = score
	s.since_contact = drone.since_contact
	return s
