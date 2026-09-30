class_name FlightPredictor
extends RefCounted

## Runs a copy of the flight model forward and answers the two questions the
## co-pilot asks every tick: where would the bird be, and would it get through?
##
## Everything here is static and pure. It is given a model, a plan, and a step
## size, and it hands back a path -- the real model is never touched, so the
## brain can score a dozen hypothetical futures inside one tick without the
## bird moving.

## The sampled path a candidate flight would follow.
##
## The steer demand is held constant for the whole run, which is what makes a
## candidate a *schedule* rather than a controller. The co-pilot re-decides
## every tick, so holding the axis steady for a third of a second is a fair
## approximation and a much smaller thing to reason about.
static func trajectory(
		flight: FlightModel, steer: float, flap_times: Array,
		steps: int, dt: float) -> Array[Vector2]:
	var model := flight.copy()
	var path: Array[Vector2] = []
	var pending: Array = flap_times.duplicate()
	pending.sort()
	var next_flap := 0
	var elapsed := 0.0
	model.set_steer(steer)
	for step in steps:
		while next_flap < pending.size() and float(pending[next_flap]) <= elapsed:
			model.flap()
			next_flap += 1
		model.step(dt)
		elapsed += dt
		path.append(Vector2(model.position_x, model.position_y))
	return path

## True when the whole path stays clear of one pipe.
##
## Every sample inside the pipe's collision reach is checked, not just the one
## nearest its mid-plane: a path can be inside the slab for a dozen frames,
## and a single-sample check is exactly the kind of shortcut that lets a bird
## clip a lip it was already committed to.
static func clears_obstacle(
		path: Array[Vector2], start_z: float, forward_speed: float,
		gap_center: Vector2, gap_size: float, pipe_z: float, dt: float) -> bool:
	var reach := GameConfig.PIPE_DEPTH * 0.5 + GameConfig.PLAYER_RADIUS
	for i in path.size():
		var sample_z := start_z - float(i) * forward_speed * dt
		if absf(sample_z - pipe_z) > reach:
			continue
		if not clears_pipe(path[i], gap_center, gap_size):
			return false
	return true

## True when one point misses one pipe, using the same two tests Obstacle makes:
## the pipe is a slab of half-width PIPE_RADIUS, so a point beside the slab
## entirely is safe at any height, and a point level with the slab is safe only
## inside the drawn gap less the bird's own radius.
static func clears_pipe(point: Vector2, gap_center: Vector2, gap_size: float) -> bool:
	if absf(point.x - gap_center.x) > GameConfig.PIPE_RADIUS + GameConfig.PLAYER_RADIUS:
		return true
	return absf(point.y - gap_center.y) <= gap_size * 0.5 - GameConfig.PLAYER_RADIUS
