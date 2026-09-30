class_name CoPilotBrain
extends RefCounted

## The co-pilot: an agent that owns one control axis of a bird it does not fly.
##
## It never touches the bird. It reads a BirdSensors snapshot, simulates a set
## of candidate actions through the real FlightModel, scores each one, and
## returns a BirdIntent -- the same message a keystroke produces. Everything
## about "two players, one bird" is enforced by the fact that this brain can
## only ever fill one half of that message.
##
## It is explainable by construction rather than by a post-hoc narration: the
## utility of every candidate is retained in `last_utility`, and the F1 overlay
## prints that table next to the decision. If the overlay and the brain ever
## disagreed, a test would catch it, so the number on screen is the number the
## brain chose by.

enum State { CRUISE, ALIGN, CLOSE, RECOVER, PANIC }

## Candidate flap schedules scored per tick: flap now, then one per
## CANDIDATE_STEP up to the look-ahead, then never.
##
## The count is tied to the look-ahead rather than chosen. Sixteen candidates at
## a twentieth of a second reach 0.75 s, but the flap axis only ever simulates
## MAX_FLAP_HORIZON -- one flap period, 0.39 s. Every candidate past 0.39 s is a
## schedule that never fires inside the window it is being scored over, so all
## of them trace exactly the "never flap" path. That is not merely wasted work:
## the argmax breaks ties towards the last candidate, so eight identical copies
## of "do nothing" gave the bird eight chances to win a tie that a real flap
## schedule had earned, and the co-pilot under-flew. Eight candidates plus
## "never" covers the horizon exactly, with no duplicates.
const FLAP_CANDIDATES := 8
## Spacing of the candidate flap times, in seconds. Also the resolution of a
## scheduled flap's countdown, so a committed time is honoured exactly rather
## than rounded to the nearest twentieth.
const CANDIDATE_STEP := 0.05
## The period a candidate rhythm repeats on, in seconds: one flap impulse's
## worth of climb, which gravity takes exactly this long to undo.
const FLAP_PERIOD := GameConfig.FLAP_IMPULSE / GameConfig.GRAVITY
## Steer candidates, sampled across the axis.
##
## Order matters. The argmax breaks ties towards the *last* candidate -- the
## same rule that stops the flap axis from creeping upward -- so the neutral
## value is listed last and "when in doubt, hold still" holds on both axes.
## In the obvious order, with +1.0 last, a tie sent the bird hard right on
## every tick and it flew off down the corridor.
const STEER_CANDIDATES := [-1.0, -0.5, 0.5, 1.0, 0.0]
## How close to a wall counts as being in trouble.
const RECOVER_MARGIN := 1.0
## Longest look-ahead the steer axis will consider, in seconds.
##
## Derived rather than tuned, and for the same reason the flap axis is:
## LATERAL_MAX_SPEED / LATERAL_ACCEL is the time it takes the steer axis to
## go from rest to its top speed, which is exactly the window over which a
## steering command is a decision rather than a guess.
##
## It matters because a candidate steer is held constant for the whole
## horizon. Over two seconds that is not a plan at all -- full lock for two
## seconds overshoots by five metres -- so the score found that every
## candidate was worse than doing nothing and the co-pilot sat still until the
## error grew so large that even a bad command was better, then locked over
## and sailed past. A horizon of one acceleration ramp makes "hold half a lock
## for a quarter of a second" a real option, which is the choice a player
## actually makes.
##
## Over ten seeds this is also the value that survives best: at 0.20 the bird
## is too twitchy, and at 0.40 and 0.80 it loses roughly three pipes per run.
const MAX_STEER_HORIZON := GameConfig.LATERAL_MAX_SPEED / GameConfig.LATERAL_ACCEL
## Longest look-ahead the flap axis will consider, in seconds.
##
## Exactly one flap period: FLAP_IMPULSE / GRAVITY is the time gravity takes
## to undo a flap, and so the time over which the bird has any authority to
## choose. See _steps_for for why looking further is self-defeating.
const MAX_FLAP_HORIZON := GameConfig.FLAP_IMPULSE / GameConfig.GRAVITY

var state: State = State.CRUISE
## The single axis this brain is allowed to drive.
var axis: int = MatchConfig.Role.FLAP
var profile := SkillProfile.new()

## Utility of each candidate, parallel to `last_candidates`. Index 0 is "flap
## now"; the final entry is "never flap". This is the overlay's table.
var last_utility: Array[float] = []
## What each candidate *was*: a flap time in seconds on the flap axis, a steer
## value on the steer axis.
var last_candidates: Array[float] = []
## Seconds until the scheduled flap fires, or -1 when nothing is scheduled.
var flap_in: float = -1.0
## The point the brain is actually aiming at, after aim noise.
var aim := Vector2.ZERO
## Where the bird was on the last decision, for the overlay's readouts.
var last_position := Vector2.ZERO
## Index into `last_utility` of the candidate that was chosen.
##
## Published so the overlay marks the row the brain actually picked rather than
## recomputing the argmax. Recomputing is how the panel came to disagree with
## the brain on a tie: the brain breaks ties towards the last candidate, the
## panel broke them towards the first, and on a run where "never flap" and
## "flap now" scored identically the panel highlighted a row the bird was not
## going to fly.
var best_index: int = 0
## The trajectory the winning candidate actually traced.
##
## Kept so the ribbon in the world and the number on the overlay are the same
## decision: the ribbon is not a fresh guess about where the bird is going, it
## is the path whose utility the brain actually chose by.
var last_path: Array[Vector2] = []

var _elapsed: float = 0.0
var _stale: BirdSensors = null
var _noise_aim := Vector2.ZERO
var _noise_index: int = -999

func _init() -> void:
	reset()

## Points this brain at one axis, at one skill level, with one seed.
func configure(assigned_axis: int, level: int = SkillProfile.Level.NORMAL,
		seed_value: int = 0) -> void:
	axis = assigned_axis
	profile.configure(level, seed_value)
	reset()

func reset() -> void:
	state = State.CRUISE
	flap_in = -1.0
	aim = Vector2.ZERO
	last_position = Vector2.ZERO
	last_utility.clear()
	last_candidates.clear()
	last_path.clear()
	_elapsed = 0.0
	_stale = null
	_noise_aim = Vector2.ZERO
	_noise_index = -999

## The only entry point. One decision, one intent.
func decide(s: BirdSensors) -> BirdIntent:
	_elapsed += s.delta
	# A less skilled brain acts on a slightly out-of-date view of the world.
	# The staleness is real rather than cosmetic: the fresh sensors are simply
	# not read until reaction_delay has elapsed.
	if _stale == null or _elapsed - _stale.elapsed >= profile.reaction_delay:
		_stale = s
	last_position = _stale.position
	if axis == MatchConfig.Role.STEER:
		return _decide_steer(_stale)
	return _decide_flap(_stale)

# --- the flap axis -----------------------------------------------------------

func _decide_flap(s: BirdSensors) -> BirdIntent:
	var intent := BirdIntent.new()
	var target := _aim_for(s)
	aim = target

	# A flap that is already scheduled fires when it comes due, and planning
	# resumes from wherever that leaves the bird.
	if flap_in >= 0.0:
		flap_in -= maxf(s.delta, 0.0)
		if flap_in > 0.0:
			state = State.ALIGN
			return intent
		flap_in = -1.0
		intent.request_flap()
		state = State.CLOSE
		return intent

	# Out of bounds: climb out of the floor, and let go near the ceiling.
	# Nothing else survives the floor, and flapping into the ceiling is just
	# as fatal as falling into it.
	if s.position.y < s.floor_y + RECOVER_MARGIN:
		state = State.RECOVER
		intent.request_flap()
		return intent
	if s.position.y > s.ceiling_y - RECOVER_MARGIN:
		state = State.RECOVER
		return intent

	if s.gap_size <= 0.0:
		state = State.CRUISE
		return intent

	var dt := maxf(s.delta, 0.0001)
	var steps := _steps_for(s, dt)
	var horizon := float(steps) * dt
	var flight := _model_for(s)
	# One extra candidate beyond the flap times: doing nothing at all, which
	# is the schedule that has to lose for the bird to be flown rather than
	# dropped.
	last_utility.clear()
	last_candidates.clear()
	var chosen := 0
	var best_score := -INF
	var best_path: Array[Vector2] = []
	for i in FLAP_CANDIDATES + 1:
		var when := float(i) * CANDIDATE_STEP
		# A candidate is when to *begin a rhythm*, not a single impulse.
		# A flappy bird does not flap once and hope: it flaps, falls back
		# through the height the impulse gave it, and flaps again on the same
		# period for as long as it needs to hold a line. Scoring only one
		# impulse leaves "flap now" and "never flap" bracketing every possible
		# arrival, so a well-timed start is never strictly the best of the
		# three and the scheduling machinery is present but unreachable. A
		# rhythm makes the *phase* the decision, which is what "ALIGN -> flap
		# in 0.21s" is actually reporting.
		var flap_times: Array = []
		if i < FLAP_CANDIDATES:
			var start := 0.0 if i == 0 \
				else maxf(0.0, when + profile.flap_timing_jitter())
			var beat := start
			while beat <= horizon:
				flap_times.append(beat)
				beat += FLAP_PERIOD
		var path := FlightPredictor.trajectory(flight, 0.0, flap_times, steps, dt)
		var value := AiUtility.score(path, target, s.gap_size, s.time_to_gap,
			s.wind, flap_times.size(), dt)
		last_utility.append(value)
		last_candidates.append(when)
		# >= rather than >, so a tie is won by the *last* candidate, and the
		# last candidate is "never flap". Sitting exactly on the gap's height,
		# flapping now and doing nothing can score identically, and breaking
		# that tie towards flapping makes the bird rise on every tick until it
		# is in the ceiling. When two actions are equally good, a bird should
		# hold still.
		if value >= best_score:
			best_score = value
			chosen = i
			best_path = path
	last_path = best_path
	best_index = chosen

	if chosen == 0:
		intent.request_flap()
		# PANIC is not "flapped now"; it is "the gap is too far below for any
		# other action to be survivable", which is the situation rather than
		# the schedule.
		state = State.PANIC if _is_urgent(s, target) else State.CLOSE
		return intent
	if chosen < FLAP_CANDIDATES:
		flap_in = last_candidates[chosen]
		# A flap this close to now is as good as immediate: at 60 Hz it is
		# three frames, and a brain that reported an emergency only on an exact
		# zero would sit in ALIGN through the whole of one.
		if flap_in <= CANDIDATE_STEP:
			state = State.PANIC if _is_urgent(s, target) else State.CLOSE
		else:
			state = State.ALIGN
		return intent
	state = State.CRUISE
	return intent

# --- the steer axis ----------------------------------------------------------

func _decide_steer(s: BirdSensors) -> BirdIntent:
	var intent := BirdIntent.new()
	var target := _aim_for(s)
	aim = target
	if s.gap_size <= 0.0:
		state = State.CRUISE
		return intent

	var dt := maxf(s.delta, 0.0001)
	var steps := _steps_for(s, dt)
	var flight := _model_for(s)
	last_utility.clear()
	last_candidates.clear()
	var best := 0.0
	var best_score := -INF
	var chosen := 0
	var best_path: Array[Vector2] = []
	for i in STEER_CANDIDATES.size():
		var candidate: float = STEER_CANDIDATES[i]
		var path := FlightPredictor.trajectory(flight, candidate, [], steps, dt)
		var value := AiUtility.steer_score(path, target.x, dt)
		last_utility.append(value)
		last_candidates.append(candidate)
		if value >= best_score:
			best_score = value
			best = candidate
			chosen = i
			best_path = path
	last_path = best_path
	best_index = chosen

	intent.set_steer(best)
	var error := absf(s.position.x - target.x)
	if absf(s.position.x) > GameConfig.LANE_HALF_WIDTH - RECOVER_MARGIN:
		state = State.RECOVER
	elif error > profile.panic_threshold:
		state = State.PANIC
	elif absf(best) > 0.1:
		state = State.ALIGN
	else:
		state = State.CRUISE
	return intent

# --- shared ------------------------------------------------------------------

## The point the brain aims at, with the skill profile's aim error applied.
##
## The error is redrawn when the target gap changes, not every tick. Noise that
## changed every frame would be indistinguishable from a brain that merely
## jitters; a weaker aim should be a consistent misjudgement of one gap, which
## is also what makes a run reproducible from a seed.
func _aim_for(s: BirdSensors) -> Vector2:
	if s.target_index != _noise_index:
		_noise_index = s.target_index
		# The aim error is scaled by how tight the gap actually is, and not
		# merely anchored to the tightest gap the curve will ever reach. The
		# same number of metres means something quite different in a five-metre
		# opening and a 2.8-metre closing one, and an error fixed in metres is
		# therefore a large fraction of a late gap and a rounding error in an
		# early one. Scaling continuously is what lets a mid-skill pilot stay
		# survivable all the way down the curve instead of falling off a cliff
		# where the gaps start closing.
		# The draw comes from the profile's own generator, so a run stays
		# reproducible from its seed; only the deviation is scaled.
		var band := s.gap_size / GameConfig.GAP_START
		_noise_aim = s.target_gap \
			+ Vector2(profile.aim_error(), profile.aim_error()) * band
	return _noise_aim


## True when the gap is so far below the bird that this flap is the only
## survivable action available, rather than merely the best of several.
func _is_urgent(s: BirdSensors, target: Vector2) -> bool:
	return s.position.y < target.y - profile.panic_threshold

## A runnable model of the bird as the brain believes it to be. Includes the
## hunter's wind, so a candidate that ignores the shove is scored as the bird
## that ignored the shove would actually be.
func _model_for(s: BirdSensors) -> FlightModel:
	var model := FlightModel.new()
	model.position_x = s.position.x
	model.position_y = s.position.y
	model.velocity_x = s.velocity.x
	model.velocity_y = s.velocity.y
	model.external_accel = s.wind
	return model

## How many fixed steps a decision simulates forward.
##
## The two axes need different horizons, and the reason is the shape of the
## authority each one has.
##
## Flap is a single impulse with exactly one period's worth of reach:
## MAX_FLAP_HORIZON, derived as FLAP_IMPULSE / GRAVITY, the time gravity
## takes to undo it. A longer horizon is self-defeating. However far ahead you
## look, the bird will have fallen well below the gap by the end of it, and
## the only action that delays that is a flap -- so "flap now" wins on every
## single tick, the bird is handed sixty fresh impulses a second, and it
## climbs into the ceiling without ever reaching a pipe.
##
## Steer has no such asymmetry. It is continuous and symmetric in both
## directions, so a long horizon is pure gain: because the score is a mean
## over the path, looking two seconds ahead rewards *holding the line the
## whole way* rather than merely arriving on it, and the bird starts moving
## the moment the next pipe's offset is known instead of when it is too late.
func _steps_for(s: BirdSensors, dt: float) -> int:
	var horizon := minf(s.time_to_gap, MAX_STEER_HORIZON)
	if axis == MatchConfig.Role.FLAP:
		horizon = minf(s.time_to_gap, MAX_FLAP_HORIZON)
	return maxi(2, int(ceil(horizon / dt)))

static func state_name(state_id: int) -> String:
	match state_id:
		State.CRUISE: return "CRUISE"
		State.ALIGN: return "ALIGN"
		State.CLOSE: return "CLOSE"
		State.RECOVER: return "RECOVER"
		State.PANIC: return "PANIC"
	return "?"

## One line of plain English, for the overlay. Every number here comes from the
## decision that was just made, so the sentence cannot drift from it.
func describe() -> String:
	var gap := aim - last_position
	if axis == MatchConfig.Role.STEER:
		var chosen := 0.0
		if not last_candidates.is_empty():
			chosen = last_candidates[last_candidates.size() - 1]
		return "%s -> steer %+.2f, target %+.1fm sideways" % [
			state_name(state), chosen, gap.x]
	match state:
		State.RECOVER:
			return "RECOVER -> out of bounds, correcting now"
		State.PANIC:
			return "PANIC -> gap %.1fm below, flapping now" % absf(gap.y)
		State.CLOSE:
			return "CLOSE -> flapping now, gap %+.1fm above" % gap.y
		State.ALIGN:
			return "ALIGN -> flap in %.2fs, target %+.1fm above" % [flap_in, gap.y]
	return "CRUISE -> no flap needed, gap %+.1fm above" % gap.y
