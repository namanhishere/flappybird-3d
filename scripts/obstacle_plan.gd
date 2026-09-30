class_name ObstaclePlan
extends RefCounted

## Deterministic procedural generator for pipe layouts.
##
## The plan is a seeded sequence: the same seed always yields the same pipes,
## which is what lets a test assert exact gap positions. It is also
## reachability-constrained -- each gap centre is pulled toward the previous
## one by at most MAX_GAP_CENTER_DELTA, so the generator cannot produce a
## layout that is impossible to fly through.

var gap_center: float = GameConfig.GAP_CENTER_DEFAULT
## Sideways centre of the gap. Pipes used to sit on the flight axis at x = 0,
## which made lateral movement a centring problem rather than a navigation
## one; the whole steer axis rests on this offset existing.
var gap_center_x: float = 0.0
var generated_count: int = 0
var current_score: int = 0

var _rng := RandomNumberGenerator.new()

## Restarts the sequence. Passing the same seed reproduces the same layout.
func reset(seed_value: int, start_gap_center: float = GameConfig.GAP_CENTER_DEFAULT) -> void:
	_rng.seed = seed_value
	gap_center_x = 0.0
	gap_center = start_gap_center
	generated_count = 0
	current_score = 0

## Produces the next pipe description, tightened for the current score.
## Returns a dictionary with the gap centre, the gap size and the forward
func next_obstacle(score: int) -> Dictionary:
	current_score = score
	var gap := Difficulty.gap_size(score)
	var half := gap * 0.5
	# Keep the whole gap inside the playable band, clear of floor and ceiling.
	var lowest := GameConfig.FLOOR_Y + half + GameConfig.PIPE_RADIUS
	var highest := GameConfig.CEILING_Y - half - GameConfig.PIPE_RADIUS
	var target := _rng.randf_range(lowest, highest)
	var reach := max_gap_center_delta(score)
	var step := clampf(target - gap_center, -reach, reach)
	gap_center = clampf(gap_center + step, lowest, highest)
	generated_count += 1

	# The same constraint sideways, on the same flight-time budget. One
	# generator, two axes, one reachability proof.
	var x_bounds := gap_x_bounds()
	var x_target := _rng.randf_range(x_bounds.x, x_bounds.y)
	var x_reach := max_gap_center_x_delta(score)
	var x_step := clampf(x_target - gap_center_x, -x_reach, x_reach)
	gap_center_x = clampf(gap_center_x + x_step, x_bounds.x, x_bounds.y)
	return {
		"index": generated_count - 1,
		"gap_center_y": gap_center,
		"gap_center_x": gap_center_x,
		"gap_size": gap,
		"forward_speed": Difficulty.forward_speed(score),
	}

## The largest vertical jump the bird could actually clear between two
## consecutive pipes at the given score. A faster bird covers the spacing in
## less time, so the generator tightens the bound as the game speeds up --
## which is what keeps every generated course flyable at high scores.
static func max_gap_center_delta(score: int) -> float:
	var speed := Difficulty.forward_speed(score)
	var flight_time := GameConfig.PIPE_SPACING / speed
	return minf(GameConfig.MAX_GAP_CENTER_DELTA, GameConfig.CLIMB_RATE * flight_time)

## The largest sideways jump the bird could actually clear between two
## consecutive pipes at the given score. The vertical bound above is the same
## expression with CLIMB_RATE substituted for LATERAL_SPEED, and the reason it
## uses LATERAL_SPEED rather than LATERAL_MAX_SPEED is the same reason the
## vertical one uses a safety factor: the bird spends part of the gap
## accelerating from a standstill, and the generator's promise is that every
## course it emits is flyable.
static func max_gap_center_x_delta(score: int) -> float:
	var speed := Difficulty.forward_speed(score)
	var flight_time := GameConfig.PIPE_SPACING / speed
	return minf(GameConfig.MAX_GAP_CENTER_X_DELTA, GameConfig.LATERAL_SPEED * flight_time)

## The sideways band a gap centre may legally occupy. Independent of the
## score, unlike the vertical band, which tightens with the gap size: the
## lane is the same width all game long.
static func gap_x_bounds() -> Vector2:
	return Vector2(-GameConfig.LANE_HALF_WIDTH, GameConfig.LANE_HALF_WIDTH)

## The range of gap centres a pipe at the given score may legally occupy.
## Used by the spawner to size the pipe meshes and by tests to prove that every
## generated gap actually fits.
static func gap_center_bounds(score: int) -> Vector2:
	var half := Difficulty.gap_size(score) * 0.5
	var lowest := GameConfig.FLOOR_Y + half + GameConfig.PIPE_RADIUS
	var highest := GameConfig.CEILING_Y - half - GameConfig.PIPE_RADIUS
	return Vector2(lowest, highest)
