extends Node

## The gameplay benchmark: flies the real game headlessly at a given mode,
## skill and seed, and reports how far it got.
##
## This is a permanent measurement tool, not a throwaway diagnostic. It is the
## evidence behind the project's gameplay floor, and it is the harness any
## harder bar would be measured with -- same command, different --min-pipes --
## which is why the pass mark is an argument rather than a constant in here.
##
##     -- --pilot=ai --skill=normal --seconds=60 --min-pipes=20
##     -- --pilot=script --seconds=60 --min-pipes=10
##     -- --pilot=ai --skill=unfair --runs=10        # mean over ten seeds
##     -- --pilot=ai --skill=normal --trace=20       # why it died
##
## It prints one machine-readable BENCH line per run and a summary, and exits
## non-zero when a run falls below the pass mark. Exits 0 with no --min-pipes,
## because measuring a pilot and judging it are separate acts.
##
## Pass marks are stated against the mean of several seeds, not one. A single
## seed is a valid *deterministic* measurement -- the same ten seeds give the
## same numbers every time -- but it is a poor one: a bang-bang pilot's score
## on a particular corridor turns out to be mostly luck, and a floor that sits
## inside that spread would be testing the seed rather than the pilot. The
## per-run lines are still printed so the spread is visible rather than hidden.

const MAIN_SCENE := "res://scenes/main.tscn"
const STEP := 1.0 / 60.0
const DEFAULT_SEED := 20260927

var _min_pipes: int = 0

func _ready() -> void:
	InputActions.register_actions()
	# Makefile's ARGS= lands here alongside anything passed straight to the
	# engine, so both invocations work.
	var args := OS.get_cmdline_user_args()
	var config := MatchConfig.from_args(args)
	var seconds := _number(args, "--seconds=", 60.0)
	var runs := int(_number(args, "--runs=", 1.0))
	var base_seed := int(_number(args, "--seed=", float(DEFAULT_SEED)))
	var pilot := _flag(args, "--pilot=", "ai")
	_min_pipes = int(_number(args, "--min-pipes=", 0.0))
	# Frames of per-frame AI state to print at the end of each run. Off by
	# default, because a benchmark that always dumps a trace is a benchmark
	# nobody runs in a loop.
	var trace := int(_number(args, "--trace=", 0.0))

	var total := 0
	for run in runs:
		total += _fly_once(config, pilot, base_seed + run, seconds, trace)

	var mean := float(total) / float(maxi(runs, 1))
	print("BENCH pilot=%s mode=%s skill=%s runs=%d seconds=%.0f seed=%d mean_pipes=%.2f min_pipes=%d" % [
		pilot, MatchConfig.mode_name(config.mode),
		SkillProfile.level_name(config.skill), runs, seconds, base_seed,
		mean, _min_pipes])

	if _min_pipes > 0 and mean < float(_min_pipes):
		print("BENCH FAIL: %.2f pipes is below the floor of %d" % [mean, _min_pipes])
		await get_tree().process_frame
		get_tree().quit(1)
		return
	print("BENCH ok")
	await get_tree().process_frame
	get_tree().quit(0)

## Flies one run and returns the number of pipes the bird got past.
##
## `trace` is how many of the final frames to print with their full AI state.
## A benchmark that reports only "HIT A PIPE" tells you that a pilot failed
## and nothing about why; the trace is the difference between a tuning
## problem and a bug, and it is why this harness is permanent.
func _fly_once(config: MatchConfig, pilot: String, seed_value: int, seconds: float,
		trace: int) -> int:
	var packed := load(MAIN_SCENE) as PackedScene
	var game := packed.instantiate() as Game
	var frames: Array[String] = []
	add_child(game)
	game.fixed_seed = seed_value
	game.config = config
	game.autopilot = pilot == "ai"
	game.apply_mode(config.mode, config.skill)
	game.start()

	var steps := int(seconds / STEP)
	var died_at := -1.0
	for i in steps:
		if pilot != "ai":
			_script_pilot(game)
		game.advance(STEP)
		frames.append(_frame_line(game, i))
		while frames.size() > maxi(trace, 1):
			frames.pop_front()
		if game.state != Game.State.PLAYING:
			died_at = float(i) * STEP
			break
	for line in frames:
		print("BENCH frame %s" % line)

	# A benchmark that reports only "HIT A PIPE" is a benchmark you cannot
	# act on. The pipe it hit, and how far outside the gap the bird was, is
	# the difference between a tuning problem and a bug.
	var detail := ""
	if died_at >= 0.0:
		var flight := game.player.flight
		var nearest: Obstacle = null
		for obstacle in game.spawner.obstacles:
			if absf(obstacle.position.z - game.player.position.z) \
					> GameConfig.PIPE_DEPTH * 0.5 + GameConfig.PLAYER_RADIUS:
				continue
			if nearest == null or absf(obstacle.position.z - game.player.position.z) \
					< absf(nearest.position.z - game.player.position.z):
				nearest = obstacle
		detail = " x=%.2f pipe_x=%.2f y=%.2f gap=%.2f..%.2f clear=%.2f..%.2f" % [
			flight.position_x, nearest.position.x if nearest != null else 0.0,
			flight.position_y, nearest.gap_bottom_y() if nearest != null else 0.0,
			nearest.gap_top_y() if nearest != null else 0.0,
			nearest.clearance_bottom_y() if nearest != null else 0.0,
			nearest.clearance_top_y() if nearest != null else 0.0]
	print("BENCH run seed=%d pipes=%d survived=%.2fs reason=%s%s" % [
		seed_value, game.score,
		steps * STEP if died_at < 0.0 else died_at,
		game.game_over_reason() if died_at >= 0.0 else "ALIVE", detail])
	game.queue_free()
	return game.score

## One line per frame: the bird, where the co-pilot believes the gap is, both
## brains' decisions, and the flap brain's whole utility table. Enough to tell
## a tuning problem from a logic bug without attaching a debugger to a
## headless run.
func _frame_line(game: Game, frame: int) -> String:
	var flight := game.player.flight
	var flap_brain := game.brain_for(MatchConfig.Role.FLAP)
	var steer_brain := game.brain_for(MatchConfig.Role.STEER)
	var steer_value := 0.0
	if not steer_brain.last_candidates.is_empty():
		steer_value = steer_brain.last_candidates[steer_brain.last_candidates.size() - 1]
	return "i=%4d z=%7.2f x=%6.2f y=%6.2f aim=(%6.2f,%6.2f) v=%6.2f flap=%s in=%+.2f steer=%s s=%+.2f u=%s" % [
		frame, game.player.position.z, flight.position_x, flight.position_y,
		flap_brain.aim.x, flap_brain.aim.y, flight.velocity_y,
		CoPilotBrain.state_name(flap_brain.state), flap_brain.flap_in,
		CoPilotBrain.state_name(steer_brain.state), steer_value,
		str(flap_brain.last_utility)]

## A stand-in for two humans at one keyboard: player one flaps, player two
## steers. Deliberately plain, because the point of this pilot is to measure
## whether the course is flyable by a team at all, not to be a good AI.
##
## It holds the current pipe as its target until the bird is clear of that
## pipe's collision reach, which is the rule a diagnostic trace proved the hard
## way: aiming at the next gap while the bird is still inside the current
## pipe's slab is how you climb into the lip of the pipe you just passed.
func _script_pilot(game: Game) -> void:
	if game.state != Game.State.PLAYING:
		return
	var flight := game.player.flight
	var target := flight.position_y
	var target_x := flight.position_x
	var held: Obstacle = null
	for candidate in game.spawner.obstacles:
		if absf(candidate.position.z - game.player.position.z) \
				<= GameConfig.PIPE_DEPTH * 0.5 + GameConfig.PLAYER_RADIUS:
			held = candidate
			break
	var obstacle: Obstacle = held if held != null else game.spawner.next_obstacle()
	if obstacle != null:
		target = obstacle.gap_center_y
		target_x = obstacle.gap_center_x
	if flight.velocity_y < 0.0 and flight.position_y < target:
		game.flap()
	var lateral_error := target_x - flight.position_x
	flight.set_steer(clampf(lateral_error * 2.5 - flight.velocity_x * 0.6, -1.0, 1.0))

func _number(args: PackedStringArray, prefix: String, fallback: float) -> float:
	for arg in args:
		if arg.begins_with(prefix):
			return float(arg.substr(prefix.length()))
	return fallback

func _flag(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
