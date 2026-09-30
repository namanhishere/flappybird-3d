class_name HunterBrain
extends RefCounted

## The hunter: an agent that reads the bird and tries to catch it, mostly by
## shoving it off course rather than by touching it.
##
## It is a lead-pursuit interceptor, and that is the whole point. A drone that
## chases where the bird *is* always arrives after the bird has gone, because
## the bird keeps moving while the drone crosses the distance. Aiming at where
## the bird *will be* -- its position plus its velocity times the time it will
## take to close the separation -- is three lines of arithmetic, and it is the
## whole difference between a pursuer and an interceptor.

enum State {IDLE, APPROACH, PRESSURE, DIVE, RETREAT}

var state: State = State.IDLE
var profile := SkillProfile.new()
## Where the drone is aiming this step, kept for the overlay.
var lead := Vector3.ZERO
## Seconds the drone has been in its current state.
var state_time: float = 0.0
## Seconds spent in the current dive. A dive is a transit with an end, not a
## state the drone can sit in -- see _advance_dive.
var dive_time: float = 0.0
## True while the last decision was a committed pass, for the HUD.
var diving: bool = false

var _rng := RandomNumberGenerator.new()

func _init() -> void:
	profile.configure(SkillProfile.Level.NORMAL, 0)

func configure(level: int, seed_value: int) -> void:
	profile.configure(level, seed_value)
	_rng.seed = seed_value
	reset()

func reset() -> void:
	state = State.IDLE
	state_time = 0.0
	dive_time = 0.0
	lead = Vector3.ZERO
	diving = false

## Where to aim: not the bird, but the bird's future position.
##
## Capped at HUNTER_MAX_LEAD, because the further away the drone is, the longer
## the "time to close the separation" is, and extrapolating the bird's velocity
## a whole pipe spacing forward puts the intercept point off in the fog. The cap
## is what keeps the lead honest.
func lead_point(s: HunterSensors) -> Vector3:
	var separation := Vector2(
		s.drone_position.x - s.bird_position.x,
		s.drone_position.y - s.bird_position.y).length()
	var closing := GameConfig.HUNTER_MAX_SPEED - s.bird_speed
	var time_to_close := 0.0
	if closing > 0.01:
		time_to_close = separation / closing
	time_to_close = minf(time_to_close, GameConfig.HUNTER_MAX_LEAD)
	return s.bird_position + s.bird_velocity * time_to_close

## The only entry point. One decision, one thrust.
func decide(s: HunterSensors) -> HunterThrust:
	state_time += s.delta
	lead = lead_point(s)
	diving = false

	# A catch puts the drone in RETREAT, and it stays there long enough for the
	# bird to get away. Without this the drone sits on top of the bird and
	# takes a life every frame.
	if s.since_contact < GameConfig.HUNTER_RETREAT_TIME:
		state = State.RETREAT
		return _steer_to(s, s.bird_position + _retreat_offset(s))

	# The opening: the drone hangs out of reach so the first seconds are not
	# spent being chased.
	if s.elapsed < GameConfig.HUNTER_START_DELAY:
		state = State.IDLE
		return _steer_to(s, s.bird_position + _idle_offset())

	var to_bird := Vector2(
		s.bird_position.x - s.drone_position.x,
		s.bird_position.y - s.drone_position.y).length()

	# Aggression rises with the score, so the hunter is a second difficulty
	# axis on top of the pipes'.
	var nerve := clampf(profile.aggression + float(s.score) * 0.01, 0.0, 1.0)

	if state == State.RETREAT:
		# Out of the retreat and back to hunting.
		state = State.APPROACH
		state_time = 0.0
	elif state == State.DIVE:
		# A dive runs itself out. See _advance_dive.
		_advance_dive(s)
	elif to_bird <= GameConfig.HUNTER_DIVE_RADIUS \
			and _rng.randf() < nerve * s.delta * GameConfig.HUNTER_DIVE_CHANCE:
		# Close enough, and willing enough: commit to a pass.
		state = State.DIVE
		state_time = 0.0
		dive_time = 0.0
		diving = true
	elif to_bird <= GameConfig.HUNTER_PRESSURE_RADIUS:
		state = State.PRESSURE
		state_time = 0.0
	else:
		state = State.APPROACH

	match state:
		State.PRESSURE:
			# Hold station at the edge of the bird's wake, where the wind is
			# strong but a catch is not imminent.
			return _steer_to(s, s.bird_position
				+ _orbit_offset(s.elapsed).limit_length(GameConfig.HUNTER_PRESSURE_RADIUS))
		State.DIVE:
			# Ballistic, on purpose. See _launch_at.
			return _launch_at(s, lead)
	return _steer_to(s, lead)

## Runs a dive out.
##
## A dive has to be a transit, not a state the drone can loiter in. Held open
## by proximity, DIVE became "stay on the bird": the drone reached it, stayed
## within a metre, and the third life was gone in the first seconds of the
## hunt -- every dive connected, because there was nothing for the bird to
## dodge with. Giving the dive a fixed duration makes it a pass that can
## genuinely miss, which is the only way a drone is a threat rather than a
## countdown.
func _advance_dive(s: HunterSensors) -> void:
	dive_time += s.delta
	if dive_time >= GameConfig.HUNTER_DIVE_TIME:
		state = State.RETREAT if s.since_contact < GameConfig.HUNTER_RETREAT_TIME \
			else State.APPROACH
		state_time = 0.0
		dive_time = 0.0
		diving = false

## A circular station-keeping offset, so the orbit genuinely goes round rather
## than settling at one fixed bearing. Squashed vertically because the wake is
## wider than it is tall, which is what makes the bird's flapper and its steerer
## feel the drone differently.
func _orbit_offset(elapsed: float) -> Vector3:
	var angle := elapsed * GameConfig.HUNTER_ORBIT_RATE
	return Vector3(cos(angle), sin(angle) * 0.55, 0.0)

## Where the drone loiters before the hunt starts: high, and off to one side.
func _idle_offset() -> Vector3:
	return Vector3(4.5, 9.0, 3.0)

## Where it goes after a catch: the opposite side of the bird, well clear.
func _retreat_offset(s: HunterSensors) -> Vector3:
	var away := Vector2(
		s.drone_position.x - s.bird_position.x,
		s.drone_position.y - s.bird_position.y)
	if away.length() < 0.01:
		away = Vector2(0.0, 1.0)
	var unit := away.normalized()
	return Vector3(unit.x * 9.0, unit.y * 9.0, 4.0)

## Proportional steering towards a point, saturated to the drone's own thrust
## limit. The same shape as the co-pilot's steer, for the same reason: this
## control is an acceleration, so it wants a term for the error and a term for
## the velocity that is about to overshoot it.
func _steer_to(s: HunterSensors, target: Vector3, is_dive: bool = false) -> HunterThrust:
	var error := target - s.drone_position
	var desired_velocity := error * GameConfig.HUNTER_GAIN
	var acceleration := (desired_velocity - s.drone_velocity) * GameConfig.HUNTER_RESPONSE
	acceleration = acceleration.limit_length(GameConfig.HUNTER_THRUST)
	return HunterThrust.make(acceleration, is_dive)

## A committed pass: full thrust straight at a point, with no braking.
##
## The difference between this and _steer_to is the whole reason a dive can
## miss. _steer_to is a servo -- it damps the drone's velocity towards the
## target -- so on a dive it decelerated as it closed, arrived at the bird
## with almost no speed, and parked on it. Every dive connected, because the
## drone was not passing through anything: it was homing. Letting it keep its
## speed means it goes *by*, and whether it clips the bird on the way past
## becomes a question of aim rather than a certainty.
func _launch_at(s: HunterSensors, target: Vector3) -> HunterThrust:
	var direction := target - s.drone_position
	if direction.length_squared() < 0.0001:
		return HunterThrust.make(Vector3.ZERO, false)
	return HunterThrust.make(
		direction.normalized() * GameConfig.HUNTER_THRUST, true)

static func state_name(state_id: int) -> String:
	match state_id:
		State.IDLE: return "IDLE"
		State.APPROACH: return "APPROACH"
		State.PRESSURE: return "PRESSURE"
		State.DIVE: return "DIVE"
		State.RETREAT: return "RETREAT"
	return "?"

## One line for the overlay, in the same voice as the co-pilot's.
func describe() -> String:
	match state:
		State.IDLE: return "IDLE -> still hanging back"
		State.APPROACH: return "APPROACH -> closing on the intercept point"
		State.PRESSURE: return "PRESSURE -> holding station in the bird's wake"
		State.DIVE: return "DIVE -> committing to a pass through the bird"
		State.RETREAT: return "RETREAT -> pulling back after a catch"
	return "?"
