class_name BirdSensors
extends RefCounted

## Everything a brain is allowed to perceive, as one read-only value.
##
## The brain cannot reach into the world, so a test that hands it a sensor set
## has fully specified the world it is flying in -- no scene, no nodes, no
## spawner. That is what makes an AI testable at all, and it is why this is a
## plain class and not a view onto a node.

## Seconds since this snapshot was taken. The brain owns no clock of its own,
## so the world's tick is the only time base in the AI.
var delta: float = 0.0
## Monotonic seconds since the run began, so a brain acting on deliberately
## stale sensors knows how stale they are.
var elapsed: float = 0.0

## The bird's own state, as (x, y).
var position := Vector2.ZERO
var velocity := Vector2.ZERO

## The gap the bird should be aiming at, as (x, y) of its centre.
##
## This is the pipe the bird is level with if there is one, and otherwise the
## nearest pipe ahead. Holding the current pipe until the bird is clear of its
## collision reach is the rule a diagnostic trace proved the hard way: aiming
## at the next gap while the bird is still inside the current pipe's slab is
## how you climb into the lip of the pipe you just passed.
var target_gap := Vector2.ZERO
## The gap after that one, so a brain can start lining up early without
## mistaking "early" for "now".
var next_gap := Vector2.ZERO
## True when `next_gap` is a real pipe rather than a placeholder.
var has_next_gap: bool = false

## Drawn height of the target gap, and the clear half-window the bird's centre
## has to stay inside: the drawn half less the bird's own radius.
var gap_size: float = GameConfig.GAP_START
## Seconds until the bird reaches the target gap's plane. Zero when the bird is
## level with it, which makes the constraint immediate rather than future.
var time_to_gap: float = 0.0

## Index of the target and next gaps, so a brain can tell "a new gap" from
## "the same gap, one frame later" and redraw its aim error only on the former.
var target_index: int = -1
var next_index: int = -1
## Where the hunter drone is relative to the bird, in the bird's own plane.
var hunter_offset := Vector2.ZERO
var hunter_active: bool = false
## The force the drone is currently writing into the bird, in m/s^2.
var wind := Vector2.ZERO

var floor_y: float = GameConfig.FLOOR_Y
var ceiling_y: float = GameConfig.CEILING_Y

## The clear half-window of the target gap: what the bird's centre may occupy.
func clearance_half() -> float:
	return maxf(gap_size * 0.5 - GameConfig.PLAYER_RADIUS, 0.0)

## Reads the live world. `hunter` is optional and duck-typed, because the
## drone is a later addition to the scene and the co-pilot has to work, and be
## tested, with nothing but pipes in the world.
static func from_world(
		player: Player, spawner: ObstacleSpawner, hunter: Node = null,
		delta: float = 0.0, elapsed: float = 0.0) -> BirdSensors:
	var s := BirdSensors.new()
	s.delta = delta
	s.elapsed = elapsed
	var flight := player.flight
	s.position = Vector2(flight.position_x, flight.position_y)
	s.velocity = Vector2(flight.velocity_x, flight.velocity_y)
	s.wind = flight.external_accel

	var reach := GameConfig.PIPE_DEPTH * 0.5 + GameConfig.PLAYER_RADIUS
	var current: Obstacle = null
	var upcoming: Obstacle = null
	for candidate in spawner.obstacles:
		# The bird flies toward -z, so a pipe ahead has a more negative z and
		# the nearest one ahead is the largest such z.
		if absf(candidate.position.z - player.position.z) <= reach:
			current = candidate
		elif candidate.position.z < player.position.z:
			if upcoming == null or candidate.position.z > upcoming.position.z:
				upcoming = candidate

	var target: Obstacle = current if current != null else upcoming
	if target != null:
		s.target_gap = Vector2(target.position.x, target.gap_center_y)
		s.gap_size = target.gap_size
		s.time_to_gap = maxf(
			0.0, (player.position.z - target.position.z) / maxf(player.forward_speed, 0.001))
		s.target_index = target.index
	if upcoming != null and upcoming != target:
		s.next_gap = Vector2(upcoming.position.x, upcoming.gap_center_y)
		s.has_next_gap = true
		s.next_index = upcoming.index
	if hunter != null and is_instance_valid(hunter):
		s.hunter_active = true
		s.hunter_offset = Vector2(hunter.position.x, hunter.position.y) - s.position
		if hunter.has_method("wind_at"):
			s.wind = hunter.wind_at(s.position)
	return s
