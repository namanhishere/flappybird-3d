extends Node

## The project's automated validation: a headless run of the real game.
##
## Everything here loads the actual main scene and drives the actual game loop
## through Game.advance(delta) with a fixed delta, so results do not depend on
## frame timing, wall clock, or the physics server. Run it with:
##
##     make test
##
## Exits 0 when every test passes, 1 otherwise.

const MAIN_SCENE := "res://scenes/main.tscn"
## One physics frame at the project's configured tick rate.
const STEP := 1.0 / 60.0
## Fixed course seed, so every mechanic is asserted against a known layout.
const SEED := 20260927

var _t := TestFramework.new()
var _spawned: Array[Game] = []

func _ready() -> void:
	InputActions.register_actions()
	# Preflight: if the game cannot be loaded at all, say so once and stop,
	# rather than reporting twenty confusing downstream failures.
	if not _preflight():
		get_tree().quit(1)
		return

	var suite := _suite()
	print("Running %d tests against %s" % [suite.size(), MAIN_SCENE])
	print("---")
	for test: Array in suite:
		_t.begin(test[0])
		(test[1] as Callable).call()
		_t.finish()

	_report()
	_cleanup()
	# Let the engine drain deletions before quitting, so ObjectDB does not
	# report leaked instances at exit.
	await get_tree().process_frame
	get_tree().quit(0 if _t.failed_count() == 0 else 1)

func _preflight() -> bool:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		print("[FATAL] main scene failed to load: %s" % MAIN_SCENE)
		return false
	var probe := packed.instantiate()
	if not probe is Game:
		print("[FATAL] main scene root is not a Game node")
		probe.free()
		return false
	probe.free()
	return true

# --- suite ------------------------------------------------------------------

func _suite() -> Array:
	return [
		["project configuration loads", _test_project_configuration_loads],
		["main game scene loads", _test_main_scene_loads],
		["main scene contains the gameplay nodes", _test_main_scene_contains_nodes],
		["input actions are registered", _test_input_actions_registered],
		["a flap press reaches the bird through the input map", _test_flap_input_path],
		["player spawns in first person", _test_player_spawns_in_first_person],
		["sound effects are wired up", _test_sound_effects_are_wired_up],
		["flap applies an upward impulse", _test_flap_applies_upward_impulse],
		["flapping makes the bird climb", _test_flapping_makes_the_bird_climb],
		["gravity accelerates the bird down every step", _test_gravity_pulls_down_every_step],
		["fall speed is clamped", _test_fall_speed_is_clamped],
		["obstacles spawn on reset", _test_obstacles_spawn_on_reset],
		["spawned gaps are valid and passable", _test_spawned_gaps_are_valid],
		["pipe collision matches the drawn gap", _test_pipe_collision_matches_drawn_gap],
		["obstacle generation is reproducible from a seed", _test_obstacle_generation_is_reproducible],
		["consecutive gaps stay reachable", _test_consecutive_gaps_stay_reachable],
		["difficulty increases as the score rises", _test_difficulty_increases_with_score],
		["the HUD shows the score the simulation has", _test_hud_matches_simulation],
		["difficulty is clamped at its ceiling", _test_difficulty_is_clamped],
		["flying into a pipe ends the run", _test_collision_with_pipe_ends_run],
		["flying through a clear gap is safe", _test_clear_gap_is_safe],
		["falling past the floor ends the run", _test_floor_ends_run],
		["rising past the ceiling ends the run", _test_ceiling_ends_run],
		["score increases once per pipe passed", _test_score_increases_once_per_pipe],
		["restart resets score, position and state", _test_restart_resets_state],
		["restart rebuilds the same course", _test_restart_rebuilds_same_course],
		["pipes behind the bird are culled", _test_pipes_behind_are_culled],
		["the bird is frozen before the run starts", _test_bird_frozen_before_start],
		["one seed builds an identical course on both peers", _test_course_syncs_from_seed_alone],
		["lateral gap layout stays reachable", _test_lateral_layout_is_reachable],
		["steering is real, bounded, lane-clamped physics", _test_lateral_flight_is_bounded],
		["every mode's control source is wired as specified", _test_control_map_table],
		["the command line reaches the same configuration as the table", _test_match_config_from_args],
		["skill levels are parameters, not a second implementation", _test_skill_profile_levels],
		["a flap request is an event, not a state", _test_intent_is_edge_triggered],
		["the authority owns exactly one axis", _test_authority_owns_one_axis],
		["the authority rate-limits flaps and clamps steer", _test_authority_rate_limits],
		["a client has no vocabulary for lying about the bird", _test_client_cannot_lie],
		["local 2P: the two players' axes never touch each other", _test_local_2p_axes_independent],
		["the title menu chooses a mode and a skill", _test_mode_menu_chooses_a_mode],
		["the co-pilot acts when it would otherwise fall short", _test_copilot_acts_when_falling_short],
		["the co-pilot schedules a flap before the last safe moment", _test_copilot_schedules_a_flap],
		["a downward wind beats doing nothing", _test_copilot_beats_doing_nothing],
		["the co-pilot panics only when the gap is out of reach", _test_copilot_panics_when_far_below],
		["two co-pilots on one seed make identical decisions", _test_copilot_is_reproducible],
		["the co-pilot steers onto the gap without oscillating", _test_copilot_steers_onto_the_gap],
		["the overlay shows the brain's own decision, not a description of it", _test_overlay_reads_the_brain],
		["a pipe the camera has flown through stops being drawn", _test_passed_pipe_stops_drawing],
		["the hunter aims where the bird will be, not where it is", _test_hunter_leads_the_bird],
		["the hunter passes through all five of its states", _test_hunter_states_are_reachable],
		["the drone's wake exists only inside its radius", _test_hunter_wake_is_bounded],
		["the drone costs exactly one life per catch", _test_hunter_contact_costs_one_life],
		["an unfair hunter dives more often than an easy one", _test_hunter_skill_scales_diving],
	]



## A hand-built hunter sensor set, so the brain is exercised with no scene.
func _hunter_sensors(
		drone: Vector3, bird: Vector3, drone_velocity: Vector3,
		elapsed: float, since_contact := 99.0, lives := 3) -> HunterSensors:
	var s := HunterSensors.new()
	s.delta = STEP
	s.elapsed = elapsed
	s.drone_position = drone
	s.drone_velocity = drone_velocity
	s.bird_position = bird
	# A bird that is actually flying forward, so the lead has something to lead.
	s.bird_velocity = Vector3(0.0, 0.0, -Difficulty.forward_speed(0))
	s.bird_speed = 0.0
	s.since_contact = since_contact
	s.lives_left = lives
	return s

## The hunter is a lead-pursuit interceptor, and this is the assertion that
## makes it one: the point it aims at is in front of the bird, not on it. A
## drone that chases where the bird *is* arrives after the bird has gone, and
## the whole difference is the bird's velocity times the time to close.
func _test_hunter_leads_the_bird() -> void:
	var brain := HunterBrain.new()
	brain.configure(SkillProfile.Level.NORMAL, SEED)
	var bird := Vector3(0.0, 6.0, -20.0)
	var flying := Vector3(0.0, 0.0, -Difficulty.forward_speed(0))
	# The drone holds station in the bird's frame, so the separation that
	# matters is the in-plane one: ten metres to the right, same depth.
	var far := _hunter_sensors(Vector3(10.0, 6.0, bird.z), bird, Vector3.ZERO,
		GameConfig.HUNTER_START_DELAY + 1.0)
	brain.decide(far)

	var lead := brain.lead_point(far)
	_t.expect_lt(lead.z, bird.z,
		"the intercept point is ahead of the bird, not on it")
	# The lead is the bird plus a bounded slice of its velocity.
	var offset := lead - bird
	var slice_seconds := offset.z / flying.z
	_t.expect_gt(slice_seconds, 0.0, "the lead uses some of the bird's forward speed")
	_t.expect_le(slice_seconds, GameConfig.HUNTER_MAX_LEAD + 0.001,
		"but the lead is capped, or the drone would aim into the fog")
	var separation := 10.0
	var closing := GameConfig.HUNTER_MAX_SPEED
	_t.expect_almost_eq(slice_seconds, minf(separation / closing,
		GameConfig.HUNTER_MAX_LEAD), 0.001,
		"the lead is exactly the time it takes the drone to close the separation")


	# A bird that is not moving forward gets no lead at all, which is what
	# stops the drone from chasing a phantom.
	var hovering := _hunter_sensors(Vector3(10.0, 6.0, bird.z), bird, Vector3.ZERO,
		GameConfig.HUNTER_START_DELAY + 1.0)
	hovering.bird_velocity = Vector3.ZERO
	_t.expect_almost_eq((brain.lead_point(hovering) - bird).length(), 0.0, 0.001,
		"a bird with no velocity has nothing to lead")
	_t.complete()

## All five states, each reached by putting the drone in the situation the
## state is for. A state machine whose states cannot be reached is a state
## machine with decoration in it.
func _test_hunter_states_are_reachable() -> void:
	var brain := HunterBrain.new()
	brain.configure(SkillProfile.Level.NORMAL, SEED)
	var bird := Vector3(0.0, 6.0, 0.0)
	var past_start := GameConfig.HUNTER_START_DELAY + 1.0

	brain.decide(_hunter_sensors(Vector3(0.0, 12.0, 0.0), bird, Vector3.ZERO, 0.0))
	_t.expect_eq(brain.state, HunterBrain.State.IDLE,
		"the drone hangs back before the hunt starts")

	brain.decide(_hunter_sensors(Vector3(30.0, 30.0, 0.0), bird, Vector3.ZERO, past_start))
	_t.expect_eq(brain.state, HunterBrain.State.APPROACH,
		"from far away the drone approaches")

	brain.decide(_hunter_sensors(
		Vector3(GameConfig.HUNTER_PRESSURE_RADIUS - 0.5, 6.0, 0.0),
		bird, Vector3.ZERO, past_start))
	_t.expect_eq(brain.state, HunterBrain.State.PRESSURE,
		"inside the pressure radius the drone holds station instead of closing")

	# A dive is a random commitment, so it is stepped into rather than
	# asserted from one draw: at DIVE_CHANCE per second it is a near-certainty
	# within a few seconds of sitting in range.
	var diving := false
	for i in 400:
		var s := _hunter_sensors(
			Vector3(GameConfig.HUNTER_DIVE_RADIUS - 0.2, 6.0, 0.0),
			bird, Vector3.ZERO, past_start + float(i) * STEP)
		brain.decide(s)
		if brain.state == HunterBrain.State.DIVE:
			diving = true
			break
	_t.expect_true(diving,
		"a drone sitting inside the dive radius commits to a pass within seconds")

	brain.decide(_hunter_sensors(
		Vector3(GameConfig.HUNTER_DIVE_RADIUS - 0.2, 6.0, 0.0),
		bird, Vector3.ZERO, past_start, 0.0))
	_t.expect_eq(brain.state, HunterBrain.State.RETREAT,
		"a catch puts the drone into a retreat")
	_t.complete()

## The wake is a place the player can be outside of. If the force leaked past
## its radius the drone would be an unavoidable constant drag rather than a
## thing to fly away from, and "pressure" would be a word rather than a
## mechanic.
func _test_hunter_wake_is_bounded() -> void:
	var game := _new_game()
	game.start()
	var drone: HunterDrone = game.hunter
	var centre := Vector2(drone.position.x, drone.position.y)

	_t.expect_almost_eq(drone.wind_at(centre).length(),
		GameConfig.HUNTER_FORCE, 0.001, "the wake is strongest at the drone's centre")
	_t.expect_gt(drone.wind_at(centre).length(), 0.0, "and it is a real force")

	var halfway := centre + Vector2(GameConfig.HUNTER_FORCE_RADIUS * 0.5, 0.0)
	_t.expect_almost_eq(drone.wind_at(halfway).length(),
		GameConfig.HUNTER_FORCE * 0.5, 0.001, "the wake falls off linearly")

	var edge := centre + Vector2(GameConfig.HUNTER_FORCE_RADIUS * 0.999, 0.0)
	_t.expect_lt(drone.wind_at(edge).length(), GameConfig.HUNTER_FORCE * 0.01,
		"and it is almost nothing at the edge of the radius")
	_t.expect_eq(drone.wind_at(centre + Vector2(GameConfig.HUNTER_FORCE_RADIUS, 0.0)),
		Vector2.ZERO, "and exactly nothing outside it")
	_t.expect_eq(drone.wind_at(centre + Vector2(GameConfig.HUNTER_FORCE_RADIUS * 2.0, 0.0)),
		Vector2.ZERO, "and nothing well outside it either")

	# The wake pushes the bird away from the drone, not towards it.
	var push := drone.wind_at(centre + Vector2(1.0, 0.0))
	_t.expect_gt(push.x, 0.0, "a bird to the right of the drone is pushed further right")
	_t.complete()

## One catch, one life -- and the bird is untouchable for a moment afterwards,
## so a drone sitting on top of it cannot spend the whole team in one second.
func _test_hunter_contact_costs_one_life() -> void:
	var game := _new_game()
	game.start()
	_t.expect_eq(game.lives, GameConfig.LIVES, "the team starts with its lives")

	game.hunter.model.position = game.player.position
	game.hunter.diving = true
	game._check_hunter_contact()
	_t.expect_eq(game.lives, GameConfig.LIVES - 1, "a catch costs exactly one life")
	_t.expect_almost_eq(game.hunter.since_contact, 0.0, 0.000001,
		"and puts the drone into its retreat")

	# Standing right on the bird again changes nothing while the grace period
	# runs: the retreat is the same event seen from the other side.
	game.hunter.model.position = game.player.position
	game.hunter.diving = true
	game._check_hunter_contact()
	_t.expect_eq(game.lives, GameConfig.LIVES - 1,
		"a second catch inside the grace period costs nothing")

	# Once the grace period is over, the next catch counts.
	game._invulnerable = 0.0
	game.hunter.diving = true
	game._check_hunter_contact()
	_t.expect_eq(game.lives, GameConfig.LIVES - 2, "and then the next one does")

	# Running out of lives ends the run.
	while game.lives > 0:
		game._invulnerable = 0.0
		game.hunter.diving = true
		game.hunter.model.position = game.player.position
		game._check_hunter_contact()
	_t.expect_eq(game.lives, 0, "the team can be run out of lives")
	_t.expect_eq(game.state, Game.State.GAME_OVER, "the last life ends the run")
	_t.expect_eq(game.game_over_reason(), "CAUGHT", "and the drone is the stated cause")
	_t.complete()

## Aggression is a number in a table, not a second brain: given the same seed
## and the same situation, a harder hunter commits to a pass more often.
func _test_hunter_skill_scales_diving() -> void:
	var easy_dives := 0
	var unfair_dives := 0
	for level_id: int in [SkillProfile.Level.EASY, SkillProfile.Level.UNFAIR]:
		var brain := HunterBrain.new()
		brain.configure(level_id, SEED)
		var past_start := GameConfig.HUNTER_START_DELAY + 1.0
		var count := 0
		for i in 1200:
			var s := _hunter_sensors(
				Vector3(GameConfig.HUNTER_DIVE_RADIUS - 0.2, 6.0, 0.0),
				Vector3(0.0, 6.0, 0.0), Vector3.ZERO, past_start + float(i) * STEP)
			brain.decide(s)
			if brain.state == HunterBrain.State.DIVE:
				count += 1
		if level_id == SkillProfile.Level.EASY:
			easy_dives = count
		else:
			unfair_dives = count
	_t.expect_lt(float(easy_dives), float(unfair_dives),
		"an UNFAIR hunter commits to more passes than an EASY one in the same "
		+ "twenty seconds at the same range")
	_t.expect_gt(float(unfair_dives), 0.0, "and it commits at all")
	_t.complete()

## A pipe the bird has flown through must stop being drawn even though it is
## still alive for another twenty metres of culling.
##
## The camera sits a third of a metre behind the bird's own centre and a pipe
## slab is three metres deep, so "the bird has passed it" and "the camera is
## outside it" are not the same moment. Getting that wrong fills the view with
## the inside of a green box, and no assertion on a position or a score can
## see it -- which is exactly why it is a test here.
func _test_passed_pipe_stops_drawing() -> void:
	var game := _new_game()
	game.start()
	var pipe: Obstacle = null
	for obstacle in game.spawner.obstacles:
		pipe = obstacle
		break
	_t.expect_ne(pipe, null, "there is a pipe to check")
	if pipe == null:
		_t.complete()
		return
	pipe.set_drawn(true)

	# Move the bird just past the pipe's mid-plane: scored, but the camera is
	# still inside the slab.
	var just_past := pipe.position.z + GameConfig.CAMERA_Z_OFFSET * 0.4
	game.player.teleport(Vector3(pipe.position.x, pipe.gap_center_y, just_past))
	game.advance(STEP)
	_t.expect_true(pipe.scored, "the bird has passed the pipe")
	_t.expect_false(pipe.is_passed_by(game.player.position.z + GameConfig.CAMERA_Z_OFFSET),
		"but the camera is still inside it, so the pipe must still be drawn")

	# Clear the slab entirely.
	game.player.teleport(Vector3(pipe.position.x, pipe.gap_center_y,
		pipe.position.z + GameConfig.PIPE_DEPTH))
	game.advance(STEP)
	_t.expect_false(pipe.is_passed_by(game.player.position.z + GameConfig.CAMERA_Z_OFFSET),
		"the camera has cleared the pipe")
	_t.complete()

## The overlay has to be a readout, not a narration. Everything it shows is
## read back out of the text that is actually on screen, and compared against
## the brain that just decided -- so if the panel were ever written by hand
## from a description of the AI rather than from the AI, this is the test that
## would notice.
func _test_overlay_reads_the_brain() -> void:
	var game := _new_game()
	game.autopilot = true
	game.apply_mode(MatchConfig.Mode.AI_HUMAN_STEER)
	game.start()
	_t.expect_false(game.overlay.visible, "the overlay is off until it is asked for")

	# F1 turns it on, and the game's own input handler is what turns it on.
	_press(game, &"toggle_overlay")
	_t.expect_true(game.overlay.visible, "F1 puts the explainability panel up")

	for i in 40:
		game.advance(STEP)
	var brain := game.overlay_brain()
	game._refresh_ai_overlay()

	_t.expect_eq(game.overlay.displayed_state().contains(
		CoPilotBrain.state_name(brain.state)), true,
		"the panel names the state the brain is actually in")
	_t.expect_eq(game.overlay.displayed_summary(), brain.describe(),
		"the panel's sentence is the brain's own sentence, not a copy of one")
	_t.expect_true(game.overlay.displayed_target().contains("%.2f" % brain.aim.y),
		"the panel shows the aim the brain is holding")

	# The candidate table is the point of the panel: the numbers must be the
	# brain's own numbers, best candidate marked.
	_t.expect_gt(float(brain.last_utility.size()), 0.0,
		"the brain scored candidates to display")
	_t.expect_true(game.overlay.displayed_table().contains(
		"%.2f" % brain.last_utility[0]),
		"the table shows the first candidate's real utility")
	# The panel must mark the row the brain chose. It reads the brain's own
	# index rather than recomputing the argmax, because recomputing it is
	# exactly how the two came to disagree on a tie in the first place.
	var best := brain.best_index
	_t.expect_eq(game.overlay.displayed_best_candidate(),
		_utility_label(best, brain.last_candidates.size()),
		"the highlighted candidate is the one the argmax actually chose")

	# The ribbon is drawn from the very path that was scored, so the line in
	# the air and the table on screen are one decision.
	_t.expect_gt(float(game.marker.ribbon_vertex_count()), 0.0,
		"the predicted-path ribbon was drawn")
	_t.expect_true(game.marker.marker_visible(), "the target marker is up with the panel")
	_t.expect_almost_eq(game.marker.crosshair_position().x, brain.aim.x, 0.001,
		"the crosshair sits on the gap the brain is aiming at")

	# TAB moves to the other brain rather than to nothing.
	_press(game, &"cycle_ai_view")
	_t.expect_eq(game.overlay.current_view(), AIOverlay.View.COPILOT_STEER,
		"TAB moves the panel to the steer brain")
	_t.expect_ne(game.overlay_brain(), brain, "and the panel follows it")
	_t.complete()

## The label the overlay would print for candidate `index`, derived from the
## brain's own candidate list rather than from the panel's formatting.
func _utility_label(index: int, count: int) -> String:
	if index >= count - 1:
		return "never"
	return "flap"


# --- intent and authority ---------------------------------------------------

## A flap request has to be an event, because a bird that flaps continuously
## is a bird that cannot fall. This is also what makes a duplicated packet
## inert: the request is spent when it is read, so there is nothing left to
## replay.
func _test_intent_is_edge_triggered() -> void:
	var intent := BirdIntent.new()
	_t.expect_false(intent.consume_flap(), "a fresh intent has no flap to give")
	intent.request_flap()
	_t.expect_true(intent.consume_flap(), "a requested flap is given exactly once")
	_t.expect_false(intent.consume_flap(), "the same request cannot be spent twice")

	# Stored raw, because clamping is the authority's job. A peer that sends
	# 9.0 has to be visibly clamped, not quietly corrected before validation.
	intent.set_steer(9.0)
	_t.expect_almost_eq(intent.steer, 9.0, 0.0, "an intent stores the value it was given")
	var clone := intent.copy()
	clone.set_steer(-1.0)
	_t.expect_almost_eq(intent.steer, 9.0, 0.0,
		"a copied intent is detached, so a predictor cannot mutate the live one")

	# The two axes are separate fields, so filling one can never disturb the
	# other. That is the mechanical basis of "two players, one bird".
	var flap_only := BirdIntent.new()
	flap_only.request_flap()
	_t.expect_almost_eq(flap_only.steer, 0.0, 0.0, "requesting a flap leaves the steer axis at rest")
	var steer_only := BirdIntent.new()
	steer_only.set_steer(0.5)
	_t.expect_false(steer_only.consume_flap(), "steering does not flap the bird")

	intent.clear()
	_t.expect_almost_eq(intent.steer, 0.0, 0.0, "clear() releases the steer axis")
	_t.expect_false(intent.flap, "clear() drops a pending flap")
	_t.complete()

## The rule the whole authority exists for. A peer assigned one axis that
## sends the other changes nothing at all -- not slowed down, not corrected,
## not even refused out loud, because telling a client its flap was turned
## down is more information than it needs to learn which half it may move.
func _test_authority_owns_one_axis() -> void:
	var steer_peer := Authority.new()
	steer_peer.configure(MatchConfig.Role.STEER)
	_t.expect_true(steer_peer.owns(MatchConfig.Role.STEER), "a STEER peer owns the steer axis")
	_t.expect_false(steer_peer.owns(MatchConfig.Role.FLAP), "a STEER peer does not own the flap axis")
	_t.expect_false(steer_peer.request_flap(1.0),
		"a flap from a peer assigned STEER is dropped silently")
	_t.expect_almost_eq(steer_peer.request_steer(0.5), 0.5, 0.0,
		"the axis a peer does own is still taken from it")

	# The mirror image: a FLAP peer cannot steer.
	var flap_peer := Authority.new()
	flap_peer.configure(MatchConfig.Role.FLAP)
	_t.expect_true(flap_peer.request_flap(1.0), "a FLAP peer may flap")
	_t.expect_almost_eq(flap_peer.request_steer(1.0), 0.0, 0.0,
		"a steer from a peer assigned FLAP is dropped silently")
	_t.complete()

## The host is the authority, so it gets to decide what a peer may do. Three
## rules, each a separate failure mode: a minimum interval between flaps, a
## budget per second on top of it, and a clamp that refuses non-finite input
## outright rather than propagating it into the physics.
func _test_authority_rate_limits() -> void:
	var authority := Authority.new()
	authority.configure(MatchConfig.Role.FLAP)
	_t.expect_true(authority.request_flap(1.0), "the first flap is accepted")
	_t.expect_false(authority.request_flap(1.0 + Protocol.MIN_FLAP_INTERVAL * 0.5),
		"a second flap inside the minimum interval is rejected")
	_t.expect_true(authority.request_flap(1.0 + Protocol.MIN_FLAP_INTERVAL),
		"a flap exactly at the minimum interval is accepted")

	# A peer that respects the interval but sends a great many of them is
	# still bounded, which is what bounds the reliable channel a flap travels
	# on. One second of flooding, measured rather than assumed.
	var accepted := 0
	var moment := 20.0
	for i in 100:
		if authority.request_flap(moment):
			accepted += 1
		moment += 0.01
	_t.expect_le(float(accepted), float(Protocol.FLAP_BUDGET_PER_SECOND) + 1.0,
		"a peer flooding at 100 Hz cannot exceed the per-second flap budget")
	_t.expect_gt(float(accepted), 0.0, "the flood is rate limited, not blocked wholesale")

	# Steer is the other peer's axis, so it gets its own authority: asking a
	# FLAP peer for steer is the case the previous test proved returns nothing.
	var steer_peer := Authority.new()
	steer_peer.configure(MatchConfig.Role.STEER)
	_t.expect_almost_eq(steer_peer.request_steer(9.0), 1.0, 0.0, "steer is clamped to the axis")
	_t.expect_almost_eq(steer_peer.request_steer(-9.0), -1.0, 0.0, "steer is clamped below it too")
	_t.expect_almost_eq(steer_peer.request_steer(NAN), 0.0, 0.0, "NaN is refused outright")
	_t.expect_almost_eq(steer_peer.request_steer(INF), 0.0, 0.0, "infinity is refused outright")
	_t.expect_almost_eq(steer_peer.request_steer(0.25), 0.25, 0.0, "a legal steer passes through")

	# A dead bird takes nothing. A refused steer is 0.0 rather than the last
	# good value, so the axis is released instead of left pinned to a stale
	# input the other player can never take back.
	authority.alive = false
	_t.expect_false(authority.request_flap(30.0), "a dead bird takes no flaps")
	steer_peer.alive = false
	_t.expect_almost_eq(steer_peer.request_steer(0.5), 0.0, 0.0, "a dead bird takes no steer")
	_t.complete()

## The only messages a client may send are input. There is deliberately no
## RPC that can carry a position, a score or a life count, so a modified
## client has no vocabulary for lying about them -- the two RPC sets are
## disjoint, which is the property that makes that true.
func _test_client_cannot_lie() -> void:
	_t.expect_len(Protocol.RPC_NAMES.size(), 8, "the protocol declares eight RPCs")
	_t.expect_len(Protocol.CLIENT_TO_SERVER.size(), 4, "a client may send four messages")
	_t.expect_len(Protocol.SERVER_TO_CLIENT.size(), 4, "the host pushes four messages")
	for rpc_name: StringName in Protocol.CLIENT_TO_SERVER:
		_t.expect_true(Protocol.RPC_NAMES.has(rpc_name), "%s is a declared RPC" % rpc_name)
		_t.expect_false(Protocol.SERVER_TO_CLIENT.has(rpc_name),
			"%s is not a host-only message" % rpc_name)
	for rpc_name: StringName in Protocol.SERVER_TO_CLIENT:
		_t.expect_false(Protocol.CLIENT_TO_SERVER.has(rpc_name),
			"%s is not a client message" % rpc_name)
	_t.complete()

## The premise of the game, asserted mechanically. Two players share one bird
## and each can move exactly one of its axes: a flap may not change the
## sideways speed, and a steer may not change the fall. If either could, "two
## people, one bird" would be a shared hotkey rather than a constraint.
##
## Both are driven through the real input path -- a synthesised action press
## and a held action -- because the game rewrites the model's steer demand from
## the intent every step, and a value poked straight into the model would be
## discarded before it could move anything.
func _test_local_2p_axes_independent() -> void:
	var game := _new_game()
	game.apply_mode(MatchConfig.Mode.LOCAL_2P)
	game.start()

	var before_x := game.player.flight.position_x
	var before_vx := game.player.flight.velocity_x
	var before_vy := game.player.flight.velocity_y
	_press(game, &"flap")
	game.advance(STEP)
	_t.expect_eq(game.player.flight.flap_count, 1, "player one flapped the bird")
	_t.expect_almost_eq(game.player.flight.position_x, before_x, 0.0,
		"a flap does not move the bird sideways")
	_t.expect_almost_eq(game.player.flight.velocity_x, before_vx, 0.0,
		"a flap does not change the sideways speed")

	# Hold the steer key down and let gravity act for exactly one step. The
	# fall has to be precisely what gravity alone would have produced, which
	# is a much stronger statement than "it did not go up" -- and it is only
	# checkable if the vertical state is read immediately before that step.
	var vy_before := game.player.flight.velocity_y
	var y_before := game.player.flight.position_y
	Input.action_press(InputActions.ACTION_STEER_RIGHT)
	game.advance(STEP)
	Input.action_release(InputActions.ACTION_STEER_RIGHT)
	_t.expect_gt(game.player.flight.position_x, before_x, "player two steered the bird sideways")
	_t.expect_almost_eq(game.player.flight.velocity_y,
		vy_before - GameConfig.GRAVITY * STEP, 0.000001,
		"a steer leaves the fall exactly where gravity alone would have left it")
	_t.expect_almost_eq(game.player.flight.position_y,
		y_before + vy_before * STEP - GameConfig.GRAVITY * STEP * STEP, 0.000001,
		"a steer does not lift the bird")

	# The HUD has to say who is driving what, or a two-player match is
	# indistinguishable from a one-player match to anyone watching.
	_t.expect_true(game.ui.displayed_mode().contains("FLAP: LOCAL"),
		"the HUD says player one drives the flap axis")
	_t.expect_true(game.ui.displayed_mode().contains("STEER: LOCAL"),
		"the HUD says player two drives the steer axis")
	_t.complete()

## The menu is the other door into the same configuration the command line
## provides, so it has to be able to actually choose something and hand it
## over -- and a game launched without a mode has to open on it.
func _test_mode_menu_chooses_a_mode() -> void:
	var game := _new_game()
	_t.expect_eq(game.state, Game.State.READY, "a fixture with a mode chosen is on the title card")
	_t.expect_false(game.menu.visible, "the menu is down once a mode exists")

	# The un-launched case: no mode has been chosen, so the game waits.
	var bare := _new_game()
	bare._mode_chosen = false
	bare.reset()
	_t.expect_eq(bare.state, Game.State.MENU, "a game with no mode opens on the menu")
	_t.expect_true(bare.menu.visible, "the menu is up while the mode is undecided")
	# Bounded by the menu's own list rather than by a pair of modes written
	# here, so adding a mode cannot leave this test quietly asserting the wrong
	# range.
	_t.expect_in_range(bare.menu.selected_mode(), ModeMenu.MODES[0],
		ModeMenu.MODES[ModeMenu.MODES.size() - 1],
		"the cursor starts inside the mode list")

	# UP and DOWN move one cursor over the whole list, and both wrap.
	var start_index := bare.menu.selected_mode()
	bare.menu.handle_action(InputActions.ACTION_MENU_UP)
	_t.expect_ne(bare.menu.selected_mode(), start_index, "UP changes the highlighted mode")
	bare.menu.handle_action(InputActions.ACTION_MENU_DOWN)
	_t.expect_eq(bare.menu.selected_mode(), start_index, "DOWN comes back to where it was")
	for i in 12:
		bare.menu.handle_action(InputActions.ACTION_MENU_DOWN)
	_t.expect_in_range(bare.menu.selected_mode(), ModeMenu.MODES[0],
		ModeMenu.MODES[ModeMenu.MODES.size() - 1],
		"the mode cursor wraps instead of running off the end")
	_t.expect_in_range(bare.menu.selected_skill(), SkillProfile.Level.EASY,
		SkillProfile.Level.UNFAIR, "the skill cursor stays inside its list too")

	# The skill list is reachable by walking past the last mode, and the
	# highlighted row is the one the cursor is on.
	# The skill rows sit after the last mode on the same cursor. Stepping to the
	# top of the mode list and then down by exactly the number of modes has to
	# land on the first skill, and one step back up has to return to the last
	# mode -- which is the only way to reach the skills without a second key,
	# so it is worth proving exactly.
	# Walk up until the mode row is the marked one, which is a state the panel
	# itself reports: the test needs to know which of the two lists the cursor
	# is on, and the marker is where that is actually visible.
	for i in 32:
		if bare.menu.displayed_mode().contains(">"):
			break
		bare.menu.handle_action(InputActions.ACTION_MENU_UP)
	_t.expect_true(bare.menu.displayed_mode().contains(">"),
		"stepping up eventually comes back round to the modes")
	for i in ModeMenu.MODES.size() - 1 - bare.menu.selected_mode():
		bare.menu.handle_action(InputActions.ACTION_MENU_DOWN)
	_t.expect_eq(bare.menu.selected_mode(), ModeMenu.MODES[ModeMenu.MODES.size() - 1],
		"and can be walked to the last mode")
	bare.menu.handle_action(InputActions.ACTION_MENU_DOWN)
	_t.expect_eq(bare.menu.selected_skill(), ModeMenu.SKILLS[0],
		"stepping down past the last mode lands on the first skill")
	_t.expect_true(bare.menu.displayed_skill().contains(">"),
		"and the skill row is the one marked")
	_t.expect_false(bare.menu.displayed_mode().contains(">"),
		"while the mode row is not")
	bare.menu.handle_action(InputActions.ACTION_MENU_UP)
	_t.expect_eq(bare.menu.selected_mode(), ModeMenu.MODES[ModeMenu.MODES.size() - 1],
		"one step up from the skills returns to the last mode")
	_t.expect_true(bare.menu.displayed_mode().contains(">"),
		"and the mode row is marked again")
	_t.expect_false(bare.menu.displayed_skill().contains(">"),
		"the skill row is not marked while the mode row is")

	# Confirming through the game's real input routing puts the game on the
	# title card and takes the menu down.
	var event := InputEventAction.new()
	event.action = InputActions.ACTION_MENU_CONFIRM
	event.pressed = true
	bare._unhandled_input(event)
	_t.expect_eq(bare.state, Game.State.READY, "confirming a mode shows the title card")
	_t.expect_false(bare.menu.visible, "the menu gets out of the way once a mode is chosen")
	_t.expect_eq(bare.config.mode, bare.menu.selected_mode(),
		"the game is running the mode that was chosen")
	_t.expect_eq(bare.config.local_role, MatchConfig.local_role_for(bare.config.mode),
		"the confirmed mode also fixed which axis the local player owns")
	_t.complete()


# --- the co-pilot -----------------------------------------------------------

## A hand-built sensor set. An AI test that has to build a scene to describe a
## situation is an AI test that mostly tests the scene; this specifies the
## world completely, with no nodes at all.
func _sensors(y: float, vy: float, gap_y: float, gap_x: float,
		time_to_gap: float, wind := Vector2.ZERO, index: int = 0) -> BirdSensors:
	var s := BirdSensors.new()
	s.delta = STEP
	s.position = Vector2(0.0, y)
	s.velocity = Vector2(0.0, vy)
	s.target_gap = Vector2(gap_x, gap_y)
	s.gap_size = GameConfig.GAP_START
	s.time_to_gap = time_to_gap
	s.target_index = index
	s.wind = wind
	return s

## Falling away from a gap the bird cannot reach by gliding. Doing nothing is
## the one schedule that is certainly fatal, so the brain has to pick something
## -- and it has to have picked it by scoring, not by reflex.
func _test_copilot_acts_when_falling_short() -> void:
	var brain := CoPilotBrain.new()
	brain.configure(MatchConfig.Role.FLAP, SkillProfile.Level.UNFAIR, SEED)
	var acted := 0
	for i in 30:
		var intent := brain.decide(
			_sensors(5.0, -6.0, 10.0, 0.0, 0.9, Vector2.ZERO, 0))
		if intent.consume_flap() or brain.flap_in >= 0.0:
			acted += 1
	_t.expect_gt(float(acted), 0.0, "the co-pilot acts to climb a gap it is falling away from")
	_t.expect_gt(float(brain.last_utility.size()), 6.0,
		"the co-pilot scored a full table of candidate schedules")
	_t.expect_eq(brain.last_utility.size(), brain.last_candidates.size(),
		"every scored candidate has a label the overlay can show")
	_t.complete()

## It has to commit early enough to still be climbing on arrival, and a
## commitment has to be a real scheduled time that the brain then honours --
## not a wish, and not a reflex. A flap scheduled for after the bird reaches
## the gap is a post-mortem rather than a plan.
func _test_copilot_schedules_a_flap() -> void:
	var brain := CoPilotBrain.new()
	brain.configure(MatchConfig.Role.FLAP, SkillProfile.Level.UNFAIR, SEED)
	# High in the band and falling fast, with only a fifth of a second left.
	# Flapping now would carry the bird straight through the top of the gap,
	# and not flapping at all would drop it through the bottom, so the only
	# survivable schedule is a small one timed a few frames from now. This is
	# the case that separates a brain which *plans when* from one which only
	# ever reacts.
	# A metre above the gap and falling at eight metres a second, half a
	# second out. Not flapping drops it clean through the bottom of the gap;
	# flapping now throws it straight out through the top. Only a small
	# impulse timed a tenth of a second from now lands it in the middle, which
	# is the case that separates a brain which *plans when* from one that only
	# ever reacts -- and it has to clear the flap cost as well, so the margin
	# between the two extremes is what the scenario is really testing.
	var intent := brain.decide(_sensors(8.0, -8.0, 7.0, 0.0, 0.5, Vector2.ZERO, 0))
	_t.expect_gt(brain.flap_in, 0.0,
		"the co-pilot scheduled a flap rather than firing at once (aim=%.2f state=%s u=%s)" % [
			brain.aim.y, CoPilotBrain.state_name(brain.state), str(brain.last_utility)])
	_t.expect_le(brain.flap_in, 0.5, "the scheduled flap lands before the bird reaches the gap")
	_t.expect_false(intent.consume_flap(), "a scheduled flap is not also fired on the same tick")

	# The commitment is honoured: stepping forward, the bird is handed the
	# flap at the time the brain said, and not a frame later than it said.
	var announced := brain.flap_in
	var fired_at := -1.0
	for i in 120:
		var step_intent := brain.decide(_sensors(8.0, -8.0, 7.0, 0.0, 0.5, Vector2.ZERO, 0))
		if step_intent.consume_flap():
			fired_at = float(i) * STEP
			break
	_t.expect_ge(fired_at, 0.0, "the scheduled flap actually arrives")
	_t.expect_le(fired_at, announced + STEP, "it arrives no later than the brain promised")
	_t.complete()

## A downward shove has to change the arithmetic. If the best schedule still
## beat "never flap" with a hard wind pushing the bird into the floor, then
## the wind is not reaching the simulation the brain scores against.
func _test_copilot_beats_doing_nothing() -> void:
	var brain := CoPilotBrain.new()
	brain.configure(MatchConfig.Role.FLAP, SkillProfile.Level.UNFAIR, SEED)
	brain.decide(_sensors(6.0, 0.0, 9.0, 0.0, 0.8, Vector2(0.0, -6.0), 0))
	var best := 0
	for i in brain.last_utility.size():
		if brain.last_utility[i] > brain.last_utility[best]:
			best = i
	var do_nothing := brain.last_utility.size() - 1
	_t.expect_lt(best, do_nothing, "against a downward wind the co-pilot picks a flap")
	_t.expect_gt(brain.last_utility[best], brain.last_utility[do_nothing],
		"the schedule it chose genuinely outscores never flapping")

	# And the wind has to be visible in the scores, not just accepted.
	var calm := CoPilotBrain.new()
	calm.configure(MatchConfig.Role.FLAP, SkillProfile.Level.UNFAIR, SEED)
	calm.decide(_sensors(6.0, 0.0, 9.0, 0.0, 0.8, Vector2.ZERO, 0))
	_t.expect_gt(calm.last_utility[do_nothing], brain.last_utility[do_nothing],
		"the same schedule scores better in still air than in a downward wind")
	_t.complete()

## PANIC has to mean something specific: the gap is out of reach and the only
## survivable action is the immediate one. A gap the bird can still glide to
## must never be a panic, or the state is decoration.
func _test_copilot_panics_when_far_below() -> void:
	var brain := CoPilotBrain.new()
	brain.configure(MatchConfig.Role.FLAP, SkillProfile.Level.UNFAIR, SEED)
	# A bird already falling at nine metres a second, with the gap one and a
	# half metres above it and only a fifth of a second away. Flapping now
	# arrives inside the clear band; every scheduled alternative arrives
	# further from the gap centre, because the impulse is the same and the
	# later it lands the less of the climb is left. The immediate flap is the
	# only survivable action, which is what PANIC has to mean.
	var intent := brain.decide(_sensors(5.0, -9.0, 6.5, 0.0, 0.3, Vector2.ZERO, 0))
	_t.expect_true(intent.consume_flap(),
		"the co-pilot flaps immediately against an unreachable gap (state=%s aim=%.2f table=%s)" % [
			CoPilotBrain.state_name(brain.state), brain.aim.y, str(brain.last_utility)])
	_t.expect_eq(brain.state, CoPilotBrain.State.PANIC,
		"flapping at once against a far gap is PANIC, not CLOSE")

	# The mirror case: a gap three metres *below* a bird at rest, which the
	# bird reaches by doing nothing at all. A state that fires on "the gap is
	# not where I am" is decoration, not a decision.
	var calm := CoPilotBrain.new()
	calm.configure(MatchConfig.Role.FLAP, SkillProfile.Level.UNFAIR, SEED)
	calm.decide(_sensors(8.0, 0.0, 5.0, 0.0, 0.6, Vector2.ZERO, 0))
	_t.expect_eq(calm.state, CoPilotBrain.State.CRUISE,
		"a gap the bird reaches by gliding is not a panic")
	_t.expect_ne(calm.state, CoPilotBrain.State.PANIC,
		"PANIC is reserved for a gap that is out of reach")
	_t.complete()

## EASY has real aim noise and real flap jitter, so this is a test of the
## seeded generator and not of two brains that happen to agree. Without a
## seed every AI assertion in this file would be a coin toss.
func _test_copilot_is_reproducible() -> void:
	var runs: Array[String] = []
	for attempt in 2:
		var brain := CoPilotBrain.new()
		brain.configure(MatchConfig.Role.FLAP, SkillProfile.Level.EASY, SEED)
		var trace := ""
		for i in 200:
			var s := _sensors(6.0, -3.0, 9.0, 1.0, 0.8, Vector2.ZERO, 0)
			s.elapsed = float(i) * STEP
			var intent := brain.decide(s)
			trace += "%d:%.4f:%.4f;" % [
				int(intent.flap), brain.flap_in,
				float(CoPilotBrain.state_name(brain.state).length())]
		runs.append(trace)
	_t.expect_eq(runs[0], runs[1],
		"two brains on one seed and one input stream make identical decisions")

	var other := CoPilotBrain.new()
	other.configure(MatchConfig.Role.FLAP, SkillProfile.Level.EASY, SEED + 1)
	other.decide(_sensors(6.0, -3.0, 9.0, 1.0, 0.8, Vector2.ZERO, 0))
	_t.expect_true(other.profile.aim_noise > 0.0,
		"EASY really does draw its aim error from its own generator")
	_t.complete()

## Aiming is not the same as chasing, and the test has to reproduce the problem
## the co-pilot actually has. That is not "reach a fixed point and stop": it
## is a target that jumps sideways by a couple of metres every pipe spacing
## and never sits still. So the scenario below advances the goal by a legal
## step -- bounded by ObstaclePlan.max_gap_center_x_delta, the same bound the
## generator obeys -- at the real cadence, and asks whether the bird keeps up
## without reversing direction on every frame.
##
## The assertion is on the error *at the moment each pipe is reached*, because
## that is the instant that matters: a bird that is briefly two metres out
## between pipes is tracking, and a bird that is two metres out when the pipe
## arrives is dead.
func _test_copilot_steers_onto_the_gap() -> void:
	var brain := CoPilotBrain.new()
	brain.configure(MatchConfig.Role.STEER, SkillProfile.Level.NORMAL, SEED)
	var model := FlightModel.new()
	model.position_y = GameConfig.START_Y
	# A goal three metres to the right, which is a legal single step between
	# two pipes, so the bird has to cross most of half the lane in one pipe
	# spacing. This is the hard case for the axis: the error is larger than the
	# clear half-width, so the bird starts outside the slab entirely and has to
	# commit rather than merely tidy up.
	var goal := 3.0
	_t.expect_gt(goal, AiUtility.lateral_half(),
		"the starting error is genuinely outside the pipe's slab")
	_t.expect_le(goal, ObstaclePlan.max_gap_center_x_delta(0) + 0.001,
		"and it is a step the generator is allowed to produce in one go")

	var flips := 0
	var last_sign := 0
	var first_crossing := -1
	for i in 120:
		var s := _sensors(model.position_y, model.velocity_y,
			GameConfig.START_Y, goal, 1.0, Vector2.ZERO, 0)
		s.position.x = model.position_x
		s.velocity.x = model.velocity_x
		var intent := brain.decide(s)
		if first_crossing < 0 and absf(model.position_x - goal) < AiUtility.lateral_half():
			first_crossing = i
		model.set_steer(intent.steer)
		model.step(STEP)

		var sign_now := 0
		if absf(intent.steer) > 0.1:
			sign_now = 1 if intent.steer > 0.0 else -1
		if sign_now != 0:
			if last_sign != 0 and sign_now != last_sign:
				flips += 1
			last_sign = sign_now

	_t.expect_ge(first_crossing, 0,
		"the co-pilot brings the bird inside the pipe's slab at all")
	_t.expect_lt(first_crossing, 60,
		"and it does so within a second, not eventually")
	_t.expect_lt(absf(model.position_x - goal), AiUtility.lateral_half(),
		"the co-pilot converges on the gap's lateral centre rather than "
		+ "overshooting past it")
	_t.expect_le(float(flips), 3.0,
		"the co-pilot aims rather than oscillating: a pilot that reverses every "
		+ "frame spends the run accelerating and none of it travelling")
	_t.expect_eq(brain.last_utility.size(), 5, "the steer axis scored five candidates")
	_t.complete()

# --- project and scene ------------------------------------------------------

func _test_project_configuration_loads() -> void:
	_t.expect_eq(ProjectSettings.get_setting("application/config/name"), "Flappy 3D",
		"project name is configured")
	_t.expect_eq(ProjectSettings.get_setting("application/run/main_scene"), MAIN_SCENE,
		"main scene is configured")
	_t.expect_gt(GameConfig.GRAVITY, 0.0, "gravity is positive")
	_t.expect_gt(GameConfig.FLAP_IMPULSE, 0.0, "flap impulse is positive")
	_t.complete()

func _test_main_scene_loads() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	_t.expect_ne(packed, null, "main scene resource loads")
	if packed == null:
		_t.complete()
		return
	var game := packed.instantiate()
	_t.expect_true(game is Game, "main scene root is a Game")
	game.free()
	_t.complete()

func _test_main_scene_contains_nodes() -> void:
	var game := _new_game()
	for node_name in ["Player", "ObstacleSpawner", "Ground", "UI", "Sfx", "Sun",
			"WorldEnvironment", "ModeMenuLayer", "AIOverlay", "TargetMarker"]:
		_t.expect_ne(game.get_node_or_null(node_name), null, "scene contains %s" % node_name)
	_t.expect_ne(game.get_node_or_null("ModeMenuLayer/ModeMenu"), null,
		"the title menu is in the scene")
	_t.complete()

## Audio cannot be heard in a headless run, but the clips still have to be
## present, imported and attached, or a build could ship mute and every other
## test would still pass. Playback itself is exercised by the windowed and
## exported runs, which use a real audio driver.
func _test_sound_effects_are_wired_up() -> void:
	var game := _new_game()
	var sfx: Node = game.get_node("Sfx")
	_t.expect_eq(sfx.player_count(), 4, "all four sound effects are wired up")
	_t.expect_true(sfx.all_clips_loaded(), "every sound clip resolved and imported")
	for clip in ["Flap", "Hit", "Score", "GameOver"]:
		var player := sfx.get_node_or_null(clip) as AudioStreamPlayer
		_t.expect_ne(player, null, "%s player exists" % clip)
		if player != null:
			_t.expect_ne(player.stream, null, "%s has a clip attached" % clip)
	_t.complete()

func _test_input_actions_registered() -> void:
	for action in InputActions.all_actions():
		_t.expect_true(InputMap.has_action(action), "%s action exists" % action)
		_t.expect_gt(float(InputMap.action_get_events(action).size()), 0.0,
			"%s has key bindings" % action)
	_t.expect_gt(float(InputMap.action_get_events(&"flap").size()), 0.0,
		"flap has key bindings")
	# register_actions must be safe to call again without duplicating bindings.
	var before := InputMap.action_get_events(&"flap").size()
	InputActions.register_actions()
	_t.expect_eq(InputMap.action_get_events(&"flap").size(), before, "re-registering does not duplicate bindings")
	_t.complete()

## Drives the game through a real input event rather than by calling flap().
## Every other test pokes the API directly, so without this the whole path
## from a key press, through the InputMap binding, into the state machine and
## on to the bird would be untested.
func _test_flap_input_path() -> void:
	var game := _new_game()
	_t.expect_eq(game.state, Game.State.READY, "the run begins on the title card")

	# The same event the engine would deliver for any bound flap key.
	_press(game, &"flap")
	_t.expect_eq(game.state, Game.State.PLAYING, "a flap press starts the run")
	_t.expect_eq(game.player.flight.flap_count, 0, "starting the run does not also flap")

	_press(game, &"flap")
	# The press is queued, not applied: an intent only becomes a flap inside a
	# fixed step, which is what gives the AI and a remote peer the same
	# opportunity to act as a human press.
	_t.expect_eq(game.player.flight.flap_count, 0, "a press is queued, not applied mid-step")
	game.advance(STEP)
	_t.expect_eq(game.player.flight.flap_count, 1, "a flap press during play flaps the bird")
	_t.expect_almost_eq(game.player.flight.velocity_y,
		GameConfig.FLAP_IMPULSE - GameConfig.GRAVITY * STEP, 0.001,
		"the bird leaves the step with the flap impulse, less the one step of gravity")

	# Dying by flying into the floor, then a flap press must restart.
	game.player.teleport(Vector3(0.0, GameConfig.FLOOR_Y + 0.05, 0.0), -5.0)
	for i in 30:
		game.advance(STEP)
	_t.expect_eq(game.state, Game.State.GAME_OVER, "the run ended")
	# Clear the post-death input lock the way waiting would.
	for i in 60:
		game.advance(STEP)
	_press(game, &"flap")
	_t.expect_eq(game.state, Game.State.PLAYING, "a flap press after a crash restarts the run")
	_t.expect_eq(game.score, 0, "restarting clears the score")
	_t.complete()

## Feeds a synthesised action press through the game's real input handler.
func _press(game: Game, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	game._unhandled_input(event)

# --- player -----------------------------------------------------------------

func _test_player_spawns_in_first_person() -> void:
	var game := _new_game()
	var player := game.player
	_t.expect_almost_eq(player.position.y, GameConfig.START_Y, 0.001, "spawns at the start height")
	_t.expect_almost_eq(player.position.z, 0.0, 0.001, "spawns at the start distance")
	_t.expect_almost_eq(player.position.x, 0.0, 0.001, "spawns on the flight axis")
	_t.expect_almost_eq(player.flight.velocity_y, 0.0, 0.001, "spawns with no vertical speed")
	_t.expect_eq(player.flight.flap_count, 0, "spawns with no flaps")
	_t.expect_ne(player.get_node_or_null("Camera3D"), null, "carries a first-person camera")
	_t.expect_ne(player.get_node_or_null("WingLeft"), null, "shows a left wing")
	_t.expect_ne(player.get_node_or_null("WingRight"), null, "shows a right wing")
	_t.complete()

func _test_flap_applies_upward_impulse() -> void:
	var flight := FlightModel.new()
	flight.reset(GameConfig.START_Y)
	flight.flap()
	_t.expect_almost_eq(flight.velocity_y, GameConfig.FLAP_IMPULSE, 0.001,
		"a flap sets upward velocity to the flap impulse")
	_t.expect_eq(flight.flap_count, 1, "a flap is counted")

	# The same thing, through the live game, must reach the same model.
	var game := _new_game()
	game.start()
	game.flap()
	game.advance(STEP)
	_t.expect_almost_eq(game.player.flight.velocity_y,
		GameConfig.FLAP_IMPULSE - GameConfig.GRAVITY * STEP, 0.001,
		"a flap in the live game sets the same impulse")
	_t.complete()

func _test_flapping_makes_the_bird_climb() -> void:
	var flight := FlightModel.new()
	flight.reset(GameConfig.START_Y)
	var before := flight.position_y
	flight.flap()
	for i in 10:
		flight.step(STEP)
	_t.expect_gt(flight.position_y, before, "the bird climbs after a flap")
	_t.complete()

func _test_gravity_pulls_down_every_step() -> void:
	var flight := FlightModel.new()
	flight.reset(GameConfig.START_Y)
	var previous := flight.velocity_y
	for i in 30:
		flight.step(STEP)
		_t.expect_lt(flight.velocity_y, previous, "velocity must fall on step %d" % i)
		previous = flight.velocity_y
	_t.expect_lt(flight.position_y, GameConfig.START_Y, "the bird descends under gravity alone")

	# Free fall in the live game, with gravity in full effect.
	var game := _new_game()
	game.start()
	var start_height := game.player.position.y
	for i in 20:
		game.advance(STEP)
	_t.expect_lt(game.player.position.y, start_height, "the live bird falls with no input")
	_t.complete()

func _test_fall_speed_is_clamped() -> void:
	var flight := FlightModel.new()
	flight.reset(GameConfig.START_Y)
	for i in 600:
		flight.step(STEP)
	_t.expect_almost_eq(flight.velocity_y, GameConfig.MAX_FALL_SPEED, 0.001,
		"a long fall stops accelerating at the clamp")
	_t.complete()

# --- obstacles --------------------------------------------------------------

func _test_obstacles_spawn_on_reset() -> void:
	var game := _new_game()
	var spawner := game.spawner
	_t.expect_gt(float(spawner.obstacle_count()), 0.0, "pipes exist immediately after reset")
	var first := spawner.next_obstacle()
	_t.expect_ne(first, null, "a next obstacle is available")
	if first != null:
		_t.expect_almost_eq(first.position.z, -GameConfig.SPAWN_DISTANCE, 0.001,
			"the first pipe spawns exactly at the spawn distance ahead")
		_t.expect_almost_eq(first.position.x, first.gap_center_x, 0.001,
			"the pipe stands where the plan put its gap")
	_t.expect_ge(float(spawner.obstacle_count()), GameConfig.CORRIDOR_PIPES + 1.0,
		"the corridor is populated, not just a single pipe")
	_t.expect_eq(spawner.plan.generated_count, spawner.obstacle_count(),
		"the plan produced a description for every spawned pipe")

	# A course whose pipes all sat on the flight axis would make steering a
	# centring problem rather than a navigation one, which is the failure the
	# lateral offset exists to prevent. So the corridor has to actually
	# contain pipes the bird cannot reach without moving sideways.
	var off_axis := 0
	for obstacle in spawner.obstacles:
		if absf(obstacle.gap_center_x) > 0.05:
			off_axis += 1
	_t.expect_gt(float(off_axis), 0.0, "the corridor requires steering, not just centring")
	_t.complete()

func _test_spawned_gaps_are_valid() -> void:
	var game := _new_game()
	_t.expect_gt(float(game.spawner.obstacle_count()), 0.0, "there are pipes to validate")
	var bounds := ObstaclePlan.gap_center_bounds(0)
	for obstacle in game.spawner.obstacles:
		_t.expect_gt(obstacle.gap_size, 2.0 * GameConfig.PLAYER_RADIUS,
			"pipe %d gap is wider than the bird" % obstacle.index)
		_t.expect_ge(obstacle.gap_size, GameConfig.GAP_MIN - 0.001,
			"pipe %d gap is no tighter than the configured minimum" % obstacle.index)
		_t.expect_le(obstacle.gap_size, GameConfig.GAP_START + 0.001,
			"pipe %d gap is no wider than the configured start" % obstacle.index)
		_t.expect_ge(obstacle.gap_bottom_y(), GameConfig.FLOOR_Y + GameConfig.PIPE_RADIUS - 0.001,
			"pipe %d lower pipe stands clear of the floor" % obstacle.index)
		_t.expect_le(obstacle.gap_top_y(), GameConfig.CEILING_Y - GameConfig.PIPE_RADIUS + 0.001,
			"pipe %d upper pipe hangs clear of the ceiling" % obstacle.index)
		_t.expect_in_range(obstacle.gap_center_y, bounds.x, bounds.y,
			"pipe %d gap centre is inside its legal band" % obstacle.index)
		_t.expect_in_range(obstacle.gap_center_x, ObstaclePlan.gap_x_bounds().x,
			ObstaclePlan.gap_x_bounds().y, "pipe %d gap centre is inside the lane" % obstacle.index)
		_t.expect_false(obstacle.scored, "pipe %d starts unscored" % obstacle.index)
	_t.complete()

## Locks in the pipe's collision shape. A pipe is a flat-ended cylinder, so
## the drawn gap is exactly the open gap: the bird must be safe anywhere
## between the two pipe ends and fatal immediately outside them. Treating the
## ends as spherical caps would shrink the usable gap by twice the pipe radius
## and make the game unfair while still looking correct.
func _test_pipe_collision_matches_drawn_gap() -> void:
	var game := _new_game()
	for obstacle in game.spawner.obstacles:
		var pipe_z := obstacle.position.z
		# Level with the pipe's own centre, which is no longer the flight axis.
		var centre := Vector3(obstacle.position.x, obstacle.gap_center_y, pipe_z)
		_t.expect_false(obstacle.overlaps(centre, GameConfig.PLAYER_RADIUS),
			"pipe %d: the middle of the drawn gap is safe" % obstacle.index)
		_t.expect_true(obstacle.overlaps(
				Vector3(obstacle.position.x, obstacle.gap_bottom_y() - 0.05, pipe_z), GameConfig.PLAYER_RADIUS),
			"pipe %d: just below the gap is solid" % obstacle.index)
		_t.expect_true(obstacle.overlaps(
				Vector3(obstacle.position.x, obstacle.gap_top_y() + 0.05, pipe_z), GameConfig.PLAYER_RADIUS),
			"pipe %d: just above the gap is solid" % obstacle.index)

		# Level with the safe band but far from the pipe in depth: no hit.
		_t.expect_false(obstacle.overlaps(
				Vector3(0.0, obstacle.gap_center_y, pipe_z + GameConfig.PIPE_DEPTH), GameConfig.PLAYER_RADIUS),
			"pipe %d: clear of the pipe in depth is safe" % obstacle.index)
		# Same height, off to the side beyond the pipe wall: no hit.
		_t.expect_false(obstacle.overlaps(
				Vector3(obstacle.position.x + GameConfig.PIPE_RADIUS + 1.0,
					obstacle.gap_center_y, pipe_z), GameConfig.PLAYER_RADIUS),
			"pipe %d: clear of the pipe sideways is safe" % obstacle.index)

	# The tightest gap the game ever generates must leave a usable band.
	_t.expect_gt(GameConfig.GAP_MIN - 2.0 * GameConfig.PLAYER_RADIUS, 1.0,
		"even the tightest gap leaves more than a metre of usable clearance")
	_t.complete()

func _test_obstacle_generation_is_reproducible() -> void:
	var first := ObstaclePlan.new()
	first.reset(SEED)
	var second := ObstaclePlan.new()
	second.reset(SEED)
	var other := ObstaclePlan.new()
	other.reset(SEED + 1)
	var differences := 0
	for i in 25:
		var a := first.next_obstacle(0)
		var b := second.next_obstacle(0)
		var c := other.next_obstacle(0)
		_t.expect_almost_eq(a["gap_center_y"], b["gap_center_y"], 0.0,
			"the same seed must reproduce pipe %d exactly" % i)
		_t.expect_eq(a["index"], b["index"], "indices must match at pipe %d" % i)
		_t.expect_almost_eq(a["gap_size"], b["gap_size"], 0.0, "gap sizes match at pipe %d" % i)
		if not is_equal_approx(a["gap_center_y"], c["gap_center_y"]):
			differences += 1
	_t.expect_gt(float(differences), 0.0, "a different seed produces a different course")
	_t.complete()

func _test_consecutive_gaps_stay_reachable() -> void:
	for score in [0, 5, 15, 30, 80]:
		var plan := ObstaclePlan.new()
		plan.reset(SEED + score)
		var reach := ObstaclePlan.max_gap_center_delta(score)
		_t.expect_gt(reach, 0.5, "score %d still allows a climbable step" % score)
		var previous: float = plan.gap_center
		for i in 60:
			var pipe := plan.next_obstacle(score)
			var gap_center: float = pipe["gap_center_y"]
			_t.expect_le(absf(gap_center - previous), reach + 0.001,
				"score %d pipe %d is within one climb of the last" % [score, i])
			previous = gap_center
	_t.complete()

# --- difficulty -------------------------------------------------------------

func _test_difficulty_increases_with_score() -> void:
	var midpoint := GameConfig.SCORE_FOR_MAX_DIFFICULTY / 2
	_t.expect_lt(Difficulty.gap_size(midpoint), Difficulty.gap_size(0), "gaps tighten as the score rises")
	_t.expect_lt(Difficulty.gap_size(GameConfig.SCORE_FOR_MAX_DIFFICULTY), Difficulty.gap_size(midpoint),
		"gaps keep tightening toward the ceiling")
	_t.expect_gt(Difficulty.forward_speed(midpoint), Difficulty.forward_speed(0), "the bird speeds up")
	_t.expect_gt(Difficulty.forward_speed(GameConfig.SCORE_FOR_MAX_DIFFICULTY), Difficulty.forward_speed(midpoint),
		"the bird keeps speeding up toward the ceiling")
	_t.complete()

func _test_difficulty_is_clamped() -> void:
	var far := GameConfig.SCORE_FOR_MAX_DIFFICULTY * 10
	_t.expect_almost_eq(Difficulty.gap_size(far), GameConfig.GAP_MIN, 0.001, "gap clamps at the minimum")
	_t.expect_almost_eq(Difficulty.forward_speed(far), GameConfig.FORWARD_SPEED_MAX, 0.001,
		"speed clamps at the maximum")
	_t.expect_almost_eq(Difficulty.gap_size(0), GameConfig.GAP_START, 0.001, "gap starts at its opening value")
	_t.expect_almost_eq(Difficulty.forward_speed(0), GameConfig.FORWARD_SPEED_START, 0.001,
		"speed starts at its opening value")

	# The tighter gap must also narrow the reachability window the generator
	# is allowed to use, or late-game courses would be unfair.
	_t.expect_lt(ObstaclePlan.max_gap_center_delta(GameConfig.SCORE_FOR_MAX_DIFFICULTY),
		ObstaclePlan.max_gap_center_delta(0), "late courses are constrained more tightly")
	_t.complete()

# --- collision --------------------------------------------------------------

func _test_collision_with_pipe_ends_run() -> void:
	var game := _new_game()
	game.start()
	var obstacle := game.spawner.next_obstacle()
	# Aim into solid pipe: below the gap, level with the pipe's mid-plane.
	var strike_y := maxf(GameConfig.FLOOR_Y + 0.4, obstacle.gap_bottom_y() - 1.0)
	game.player.teleport(Vector3(obstacle.position.x, strike_y, obstacle.position.z))
	game.advance(STEP)
	_t.expect_eq(game.state, Game.State.GAME_OVER, "hitting a pipe must end the run")
	_t.expect_eq(game.game_over_reason(), "HIT A PIPE", "the pipe is reported as the cause")
	_t.complete()

func _test_clear_gap_is_safe() -> void:
	var game := _new_game()
	game.start()
	var obstacle := game.spawner.next_obstacle()
	game.player.teleport(Vector3(obstacle.position.x, obstacle.gap_center_y, obstacle.position.z + 1.0))
	for i in 6:
		game.advance(STEP)
	_t.expect_eq(game.state, Game.State.PLAYING, "flying through the gap must be safe")
	_t.expect_ge(game.player.position.y, obstacle.clearance_bottom_y(),
		"the bird stayed above the lower pipe")
	_t.expect_le(game.player.position.y, obstacle.clearance_top_y(),
		"the bird stayed below the upper pipe")
	_t.complete()

func _test_floor_ends_run() -> void:
	var game := _new_game()
	game.start()
	game.player.teleport(Vector3(0.0, GameConfig.FLOOR_Y + 0.05, 0.0), -5.0)
	for i in 30:
		game.advance(STEP)
	_t.expect_eq(game.state, Game.State.GAME_OVER, "falling past the floor must end the run")
	_t.expect_eq(game.game_over_reason(), "GROUNDED", "the floor is reported as the cause")
	_t.complete()

func _test_ceiling_ends_run() -> void:
	var game := _new_game()
	game.start()
	game.player.teleport(Vector3(0.0, GameConfig.CEILING_Y - 0.05, 0.0), 8.0)
	for i in 10:
		game.advance(STEP)
	_t.expect_eq(game.state, Game.State.GAME_OVER, "rising past the ceiling must end the run")
	_t.expect_eq(game.game_over_reason(), "OVER THE SKY", "the ceiling is reported as the cause")
	_t.complete()

# --- scoring and restart ----------------------------------------------------

func _test_score_increases_once_per_pipe() -> void:
	var game := _new_game()
	var passed: Array[int] = []
	game.spawner.pipe_passed.connect(func(index: int) -> void: passed.append(index))
	game.start()
	for i in 600:
		_autopilot(game)
		game.advance(STEP)

	_t.expect_eq(game.state, Game.State.PLAYING,
		"a piloted run survives the opening course (died: %s at z=%.1f y=%.2f)" % [
			game.game_over_reason(), game.player.position.z, game.player.position.y])
	_t.expect_ge(float(game.score), 3.0, "passing pipes raises the score (got %d)" % game.score)
	_t.expect_eq(game.score, passed.size(), "the score equals the number of pipes passed")

	var unique := {}
	for index in passed:
		unique[index] = true
	_t.expect_eq(unique.size(), passed.size(), "no pipe is ever scored twice")

	# Passed pipes are culled once they fall well behind, so the live set is a
	# subset of everything passed. What must hold is that no pipe behind the
	# bird is left unmarked, and that some have in fact been freed.
	var behind := 0
	var behind_and_scored := 0
	for obstacle in game.spawner.obstacles:
		if obstacle.position.z > game.player.position.z:
			behind += 1
			if obstacle.scored:
				behind_and_scored += 1
	_t.expect_eq(behind_and_scored, behind, "every pipe behind the bird is marked as passed")
	_t.expect_gt(float(game.score), float(behind), "passed pipes are culled once they are far behind")

	# Difficulty must reach the live bird, not just the pure curve.
	_t.expect_almost_eq(game.player.forward_speed, Difficulty.forward_speed(game.score), 0.001,
		"the live bird flies at the speed the curve prescribes for its score")
	_t.complete()

## The score the player is shown must be the score the simulation holds.
## A label that stops updating while the model carries on scoring is invisible
## to every other test here, because they all read the model directly.
func _test_hud_matches_simulation() -> void:
	var game := _new_game()
	_t.expect_true(game.ui.title_visible(), "the title card is shown before the run")
	_t.expect_false(game.ui.score_visible(), "the score is hidden on the title card")

	game.start()
	_t.expect_false(game.ui.title_visible(), "the title card is hidden once flying")
	_t.expect_true(game.ui.score_visible(), "the score is shown once flying")
	_t.expect_eq(game.ui.displayed_score(), "0", "the score starts at zero")

	for i in 600:
		_autopilot(game)
		game.advance(STEP)
	_t.expect_gt(float(game.score), 0.0, "the piloted run scored something")
	_t.expect_eq(game.ui.displayed_score(), str(game.score),
		"the HUD score tracks the simulation score")

	# Dying must swap the HUD over to the game-over card.
	game._game_over("TEST")
	_t.expect_true(game.ui.game_over_visible(), "the game-over card appears on death")
	_t.complete()

func _test_restart_resets_state() -> void:
	var game := _new_game()
	game.start()
	var pipe := game.spawner.next_obstacle()
	game.player.teleport(Vector3(pipe.position.x, GameConfig.FLOOR_Y + 0.05, pipe.position.z), -5.0)
	for i in 30:
		game.advance(STEP)
	_t.expect_eq(game.state, Game.State.GAME_OVER, "the setup run really did end")

	var final_score := game.score
	_t.expect_eq(game.best_score, final_score, "the best score records the finished run")

	game.restart()
	_t.expect_eq(game.state, Game.State.PLAYING, "restart resumes play immediately")
	_t.expect_eq(game.score, 0, "restart clears the score")
	_t.expect_almost_eq(game.player.position.y, GameConfig.START_Y, 0.001, "restart returns the bird to its start height")
	_t.expect_almost_eq(game.player.position.z, 0.0, 0.001, "restart returns the bird to its start distance")
	_t.expect_eq(game.player.flight.flap_count, 0, "restart clears the flap counter")
	_t.expect_almost_eq(game.player.flight.velocity_y, 0.0, 0.001, "restart clears vertical speed")
	_t.expect_almost_eq(game.player.forward_speed, GameConfig.FORWARD_SPEED_START, 0.001,
		"restart returns the bird to its starting speed")
	_t.expect_gt(float(game.spawner.obstacle_count()), 0.0, "restart refills the corridor")
	_t.expect_almost_eq(game.spawner.next_obstacle().position.z, -GameConfig.SPAWN_DISTANCE, 0.001,
		"restart puts the first pipe back at the spawn distance")
	_t.complete()

func _test_restart_rebuilds_same_course() -> void:
	var game := _new_game(SEED)
	game.start()
	var before: Array[float] = []
	for obstacle in game.spawner.obstacles:
		before.append(obstacle.gap_center_y)
	game.restart()
	var after: Array[float] = []
	for obstacle in game.spawner.obstacles:
		after.append(obstacle.gap_center_y)
	_t.expect_eq(after.size(), before.size(), "the same number of pipes after restart")
	for i in mini(before.size(), after.size()):
		_t.expect_almost_eq(after[i], before[i], 0.0, "pipe %d is identical after restart" % i)
	_t.complete()

func _test_pipes_behind_are_culled() -> void:
	var game := _new_game()
	game.start()
	# Teleport steadily down the corridor while staying inside the nearest gap.
	# This test is about pipe bookkeeping, not about flying, so the pilot is
	# removed entirely. The step is smaller than the pipe spacing so the bird
	# can never be teleported out of one pipe's depth range and straight into
	# the next one's, which would be a collision rather than a clean pass.
	for i in 600:
		var altitude := GameConfig.GAP_CENTER_DEFAULT
		var closest: Obstacle = null
		for obstacle in game.spawner.obstacles:
			if closest == null or absf(obstacle.position.z - game.player.position.z) \
					< absf(closest.position.z - game.player.position.z):
				closest = obstacle
		var lane := game.player.position.x
		if closest != null:
			altitude = closest.gap_center_y
			lane = closest.position.x
		game.player.teleport(Vector3(lane, altitude, -float(i) * 0.5))
		game.advance(STEP)

	_t.expect_eq(game.state, Game.State.PLAYING,
		"the teleport run stays alive (died: %s)" % game.game_over_reason())
	var alive := game.spawner.obstacle_count()
	var ever_made := game.spawner.plan.generated_count
	_t.expect_gt(float(ever_made), float(alive),
		"pipes are being freed: %d were generated but only %d are alive" % [ever_made, alive])
	_t.expect_le(float(alive), 16.0, "the live pipe count stays bounded instead of growing without limit")
	_t.expect_gt(float(alive), 0.0, "pipes keep being spawned ahead")
	_t.complete()

func _test_bird_frozen_before_start() -> void:
	var game := _new_game()
	_t.expect_eq(game.state, Game.State.READY, "the game opens on the title card")
	game.flap()
	_t.expect_eq(game.player.flight.flap_count, 0, "a flap is ignored before the run starts")
	for i in 60:
		game.advance(STEP)
	_t.expect_almost_eq(game.player.position.y, GameConfig.START_Y, 0.001,
		"the bird does not fall before the run starts")
	_t.expect_almost_eq(game.player.position.z, 0.0, 0.001,
		"the bird does not drift before the run starts")

	# Starting must hand control over.
	game.start()
	_t.expect_eq(game.state, Game.State.PLAYING, "start moves the game into play")
	for i in 30:
		game.advance(STEP)
	_t.expect_lt(game.player.position.y, GameConfig.START_Y, "the bird falls once the run starts")
	_t.complete()

# --- fixtures ---------------------------------------------------------------

## Builds a real Game from the real main scene, on a known seed.
func _new_game(seed_value: int = SEED) -> Game:
	var packed := load(MAIN_SCENE) as PackedScene
	var game := packed.instantiate() as Game
	add_child(game)
	game.fixed_seed = seed_value
	# A mode has to exist before the game can be on the title card at all, so
	# the fixture chooses the same one a default launch would.
	game.apply_mode(MatchConfig.Mode.SOLO)
	_spawned.append(game)
	return game

## A deliberately plain pilot that keeps the bird near the centre of the next
## gap on both axes. Test scaffolding only: the bird is never the subject
## under test in the tests that use it, they are about scoring and
## bookkeeping. The real pilot is CoPilotBrain, and it drives the game through
## the same intent path a human's keystroke does.
func _autopilot(game: Game) -> void:
	if game.state != Game.State.PLAYING:
		return
	var flight := game.player.flight
	var target := flight.position_y
	var target_x := flight.position_x
	# Aim at the pipe the bird is level with, and only switch to the next one
	# once the bird is clear of the current one. Switching on the mid-plane
	# alone starts a climb toward a higher pipe while the bird is still inside
	# the slab of the one it just passed, and a climb that begins too early
	# clips the lip behind it -- the bird is 0.45 m in radius, so being half a
	# metre under a gap's ceiling is a collision. Holding the target until the
	# slab is behind is also exactly what the real CoPilotBrain has to do,
	# which is why BirdSensors carries both a target gap and the next one.
	var obstacle: Obstacle = null
	for candidate in game.spawner.obstacles:
		# The window is symmetric and far shorter than the pipe spacing, so at
		# most one pipe can be inside it: the one the bird is level with. The
		# threshold is that pipe's collision reach rather than its drawn depth,
		# because a bird can still touch a slab it has geometrically cleared by
		# its own radius -- and that is the collision this pilot must not be
		# aiming at. No direction test is needed: the bird flies toward -z, so
		# a "is it ahead of me" test here would skip exactly the pipe the bird
		# is inside.
		if absf(candidate.position.z - game.player.position.z) \
				<= GameConfig.PIPE_DEPTH * 0.5 + GameConfig.PLAYER_RADIUS:
			obstacle = candidate
			break
	if obstacle == null:
		obstacle = game.spawner.next_obstacle()
	if obstacle != null:
		target = obstacle.gap_center_y
		target_x = obstacle.gap_center_x
	# Flap only while sinking and only while below the gap, which produces a
	# steady climb-and-glide rather than a buzzing hover.
	if flight.velocity_y < 0.0 and flight.position_y < target:
		game.flap()
	# Proportional-derivative steer toward the gap's lateral centre: the
	# position term pulls, the velocity term brakes, and the bird's own drag
	# and speed clamp keep the result from ringing. Pure proportional steering
	# lags far enough behind a three-metre step to clip the pipe it is aiming
	# at, which is exactly what this scaffolding must not do.
	var lateral_error := target_x - flight.position_x
	flight.set_steer(clampf(lateral_error * 2.5 - flight.velocity_x * 0.6, -1.0, 1.0))

## Frees the games built for the tests. free() rather than queue_free(): this
## runs outside the frame loop, so a deferred delete would never be processed
## before the tree is torn down, and ObjectDB would report the leak.
func _cleanup() -> void:
	for game in _spawned:
		if is_instance_valid(game):
			var sfx := game.get_node_or_null("Sfx")
			if sfx != null and sfx.has_method("stop_all"):
				sfx.stop_all()
			game.free()

func _report() -> void:
	for result in _t.results():
		if result["passed"]:
			print("[PASS] %s" % result["name"])
		else:
			print("[FAIL] %s" % result["name"])
			for message in result["failures"]:
				print("       %s" % message)
			if result["incomplete"]:
				print("       test did not run to completion (a runtime error aborted it)")
	print("---")
	print("Tests: %d passed, %d failed, %d total" % [
		_t.passed_count(), _t.failed_count(), _t.results().size()])


# --- M0: lateral course, lateral flight, the mode table ---------------------

## The whole online design rests on this one property: a course is a pure
## function of a single integer. If two peers generate the same forty pipes
## from the same seed without exchanging anything, then no pipe ever has to
## cross the network and the two peers cannot disagree about the level.
func _test_course_syncs_from_seed_alone() -> void:
	var host_plan := ObstaclePlan.new()
	var client_plan := ObstaclePlan.new()
	host_plan.reset(SEED)
	client_plan.reset(SEED)
	for i in 40:
		var host_pipe := host_plan.next_obstacle(0)
		var client_pipe := client_plan.next_obstacle(0)
		_t.expect_almost_eq(host_pipe["gap_center_x"], client_pipe["gap_center_x"], 0.0,
			"the peers disagree on the sideways centre of pipe %d" % i)
		_t.expect_almost_eq(host_pipe["gap_center_y"], client_pipe["gap_center_y"], 0.0,
			"the peers disagree on the height of pipe %d" % i)
		_t.expect_almost_eq(host_pipe["gap_size"], client_pipe["gap_size"], 0.0,
			"the peers disagree on the width of pipe %d" % i)
	_t.expect_eq(host_plan.generated_count, 40, "forty pipes were generated from the seed alone")
	_t.complete()

## Every generated course has to be flyable sideways as well as vertically.
## Two things have to hold: gap centres stay inside the lane, and no pipe asks
## for a sideways jump the bird could not make in the time between two pipes.
## A generator that breaks either can emit a course that is impossible, for
## reasons the player would have no way to see coming.
func _test_lateral_layout_is_reachable() -> void:
	var bounds := ObstaclePlan.gap_x_bounds()
	_t.expect_gt(bounds.y, 0.0, "the lane is wider than a single point")
	_t.expect_gt(float(bounds.y - bounds.x), GameConfig.MAX_GAP_CENTER_X_DELTA,
		"the lane is wide enough for a legal sideways step")
	for score in [0, 5, 15, 30, 80]:
		var plan := ObstaclePlan.new()
		plan.reset(SEED + score)
		var reach := ObstaclePlan.max_gap_center_x_delta(score)
		_t.expect_gt(reach, 0.5, "score %d still allows a steerable step" % score)
		var previous: float = plan.gap_center_x
		for i in 60:
			var pipe := plan.next_obstacle(score)
			var centre: float = pipe["gap_center_x"]
			_t.expect_in_range(centre, bounds.x, bounds.y,
				"score %d pipe %d gap centre is inside the lane" % [score, i])
			_t.expect_le(absf(centre - previous), reach + 0.001,
				"score %d pipe %d is within one steer of the last" % [score, i])
			previous = centre
	_t.complete()

## The steer axis has to be real physics rather than a nudge. Accelerating,
## being bounded, decaying when released, and being walled in by the lane are
## four separate failure modes, so they are asserted separately -- and the
## clamp is checked at the settled value, which is the only assertion that
## proves the clamp is what bounds the bird instead of the drag.
func _test_lateral_flight_is_bounded() -> void:
	var flight := FlightModel.new()
	flight.reset(GameConfig.START_Y)
	flight.set_steer(1.0)
	for i in 10:
		flight.step(STEP)
	_t.expect_gt(flight.position_x, 0.0, "steering right moves the bird right")
	_t.expect_gt(flight.velocity_x, 0.0, "the bird is still moving right")

	for i in 600:
		flight.step(STEP)
	_t.expect_almost_eq(flight.velocity_x, GameConfig.LATERAL_MAX_SPEED, 0.001,
		"a long hold settles at the maximum sideways speed, so the clamp is what bounds it")

	var speed_at_release := flight.velocity_x
	flight.set_steer(0.0)
	for i in 12:
		flight.step(STEP)
	_t.expect_lt(flight.velocity_x, speed_at_release, "releasing the steer bleeds off sideways speed")
	_t.expect_gt(flight.velocity_x, 0.0, "the bird coasts rather than stopping dead")

	# Steering must not touch the flap axis at all: two players, two axes.
	var steered := FlightModel.new()
	var level := FlightModel.new()
	steered.reset(GameConfig.START_Y)
	level.reset(GameConfig.START_Y)
	steered.set_steer(-1.0)
	for i in 120:
		steered.step(STEP)
		level.step(STEP)
	_t.expect_almost_eq(steered.position_y, level.position_y, 0.0,
		"steering leaves the flap axis bit-identical")

	# The lane is a hard wall in the live game, not just in the model -- so
	# this drives the real key, in a mode that actually has a steer axis,
	# because the game overwrites the model's steer demand from the intent
	# every step and a value poked straight into the model would be discarded.
	var game := _new_game()
	game.apply_mode(MatchConfig.Mode.LOCAL_2P)
	game.start()
	Input.action_press(InputActions.ACTION_STEER_RIGHT)
	for i in 600:
		game.advance(STEP)
		# The height is restored every frame so the run cannot end before the
		# bird reaches the wall: this test is about the lane clamp, not about
		# falling. Only the vertical state is touched, so the sideways drift
		# is entirely the physics under test.
		game.player.flight.position_y = GameConfig.START_Y
		game.player.flight.velocity_y = 0.0
	Input.action_release(InputActions.ACTION_STEER_RIGHT)
	_t.expect_almost_eq(game.player.position.x, GameConfig.LANE_HALF_WIDTH, 0.001,
		"the bird is held at the lane wall instead of leaving the lane")
	_t.expect_almost_eq(game.player.flight.position_x, game.player.position.x, 0.0,
		"the transform and the model never disagree about where the bird is")
	_t.expect_le(game.player.flight.velocity_x, 0.001,
		"the bird stops pushing into the wall rather than grinding along it")
	_t.complete()

## The mode table is the entire multi-human design in six rows, so it is
## asserted row by row instead of being described in a comment. Each mode
## gives each axis to exactly one source, and SOLO has to be honest about not
## having a steer axis rather than quietly inventing one nothing reads.
func _test_control_map_table() -> void:
	_t.expect_eq(ControlMap.source_for(MatchConfig.Mode.SOLO, MatchConfig.Role.FLAP),
		ControlMap.Source.LOCAL, "SOLO flaps from the keyboard")
	_t.expect_false(ControlMap.has_axis(MatchConfig.Mode.SOLO, MatchConfig.Role.STEER),
	"SOLO has no steer axis at all")
	_t.expect_eq(ControlMap.source_for(MatchConfig.Mode.LOCAL_2P, MatchConfig.Role.FLAP),
		ControlMap.Source.LOCAL, "LOCAL 2P flaps from player one")
	_t.expect_eq(ControlMap.source_for(MatchConfig.Mode.LOCAL_2P, MatchConfig.Role.STEER),
		ControlMap.Source.LOCAL, "LOCAL 2P steers from player two")
	_t.expect_eq(ControlMap.source_for(MatchConfig.Mode.AI_HUMAN_FLAP, MatchConfig.Role.FLAP),
		ControlMap.Source.LOCAL, "in AI_HUMAN_FLAP the human keeps the flap axis")
	_t.expect_eq(ControlMap.source_for(MatchConfig.Mode.AI_HUMAN_FLAP, MatchConfig.Role.STEER),
		ControlMap.Source.AI, "in AI_HUMAN_FLAP the AI takes the steer axis")
	_t.expect_eq(ControlMap.source_for(MatchConfig.Mode.AI_HUMAN_STEER, MatchConfig.Role.FLAP),
		ControlMap.Source.AI, "in AI_HUMAN_STEER the AI takes the flap axis")
	_t.expect_eq(ControlMap.source_for(MatchConfig.Mode.AI_HUMAN_STEER, MatchConfig.Role.STEER),
		ControlMap.Source.LOCAL, "in AI_HUMAN_STEER the human keeps the steer axis")
	_t.expect_eq(ControlMap.source_for(MatchConfig.Mode.HOST, MatchConfig.Role.FLAP),
		ControlMap.Source.LOCAL, "the host flaps locally")
	_t.expect_eq(ControlMap.source_for(MatchConfig.Mode.HOST, MatchConfig.Role.STEER),
		ControlMap.Source.REMOTE, "the host's steer comes off the wire")
	_t.expect_eq(ControlMap.source_for(MatchConfig.Mode.CLIENT, MatchConfig.Role.FLAP),
		ControlMap.Source.REMOTE, "the client's flap comes off the wire")
	_t.expect_eq(ControlMap.source_for(MatchConfig.Mode.CLIENT, MatchConfig.Role.STEER),
		ControlMap.Source.LOCAL, "the client steers locally")

	_t.expect_eq(MatchConfig.local_role_for(MatchConfig.Mode.HOST), MatchConfig.Role.FLAP,
		"the host owns the flap axis")
	_t.expect_eq(MatchConfig.local_role_for(MatchConfig.Mode.CLIENT), MatchConfig.Role.STEER,
		"the client owns the steer axis")
	_t.expect_eq(MatchConfig.local_role_for(MatchConfig.Mode.AI_HUMAN_STEER), MatchConfig.Role.STEER,
		"AI_HUMAN_STEER leaves the steer axis with the human")
	_t.expect_eq(MatchConfig.local_role_for(MatchConfig.Mode.AI_HUMAN_FLAP), MatchConfig.Role.FLAP,
		"AI_HUMAN_FLAP leaves the flap axis with the human")
	_t.complete()

## The title menu and the command line are two doors into one configuration,
## so the flags have to select exactly what the table says -- including when
## the engine's own arguments are mixed in, which is what a real launch does.
func _test_match_config_from_args() -> void:
	var host := MatchConfig.from_args(PackedStringArray(["--mode=host", "--port=27100"]))
	_t.expect_eq(host.mode, MatchConfig.Mode.HOST, "--mode=host selects the host")
	_t.expect_eq(host.local_role, MatchConfig.Role.FLAP, "the host owns the flap axis")
	_t.expect_eq(host.remote_role, MatchConfig.Role.STEER, "the client's axis is the steer axis")
	_t.expect_eq(host.port, 27100, "--port is honoured")
	_t.expect_true(host.networked, "the host knows it is online")

	var client := MatchConfig.from_args(PackedStringArray(["--mode=client"]))
	_t.expect_eq(client.mode, MatchConfig.Mode.CLIENT, "--mode=client selects the client")
	_t.expect_eq(client.local_role, MatchConfig.Role.STEER, "the client owns the steer axis")
	_t.expect_eq(client.remote_role, MatchConfig.Role.FLAP, "the host's axis is the flap axis")
	_t.expect_eq(client.address, Protocol.LOOPBACK_ADDRESS,
		"the client defaults to the loopback address")

	# --human names the axis the HUMAN holds, so the AI gets the other one.
	var ai_steer := MatchConfig.from_args(
		PackedStringArray(["--mode=ai", "--human=steer", "--skill=unfair"]))
	_t.expect_eq(ai_steer.mode, MatchConfig.Mode.AI_HUMAN_STEER,
		"--human=steer leaves the flap axis to the AI")
	_t.expect_eq(ai_steer.skill, SkillProfile.Level.UNFAIR, "--skill is honoured")

	var ai_flap := MatchConfig.from_args(PackedStringArray(["--mode=ai", "--human=flap"]))
	_t.expect_eq(ai_flap.mode, MatchConfig.Mode.AI_HUMAN_FLAP,
		"--human=flap leaves the steer axis to the AI")
	_t.expect_eq(ai_flap.skill, SkillProfile.Level.NORMAL, "the skill defaults to NORMAL")

	var local := MatchConfig.from_args(PackedStringArray(["--mode=local2p"]))
	_t.expect_eq(local.mode, MatchConfig.Mode.LOCAL_2P, "--mode=local2p selects keyboard co-op")
	_t.expect_false(local.networked, "local co-op is not an online match")

	var flipped := MatchConfig.from_args(
		PackedStringArray(["--mode=ai", "--human=steer", "--human=flap"]))
	_t.expect_eq(flipped.mode, MatchConfig.Mode.AI_HUMAN_FLAP,
		"a later --human overrides an earlier --mode")

	# A real launch passes the engine's own flags through the same parser.
	var noisy := MatchConfig.from_args(
		PackedStringArray(["--headless", "--quit-after", "60", "--autoplay"]))
	_t.expect_eq(noisy.mode, MatchConfig.Mode.SOLO, "unrelated flags leave the game in solo")
	_t.complete()

## A harder level has to be a strictly better set of numbers driving the same
## brain, not a second implementation -- and the noise source has to be
## seeded, because an unseeded brain would make every AI test in this file
## flaky rather than wrong.
func _test_skill_profile_levels() -> void:
	var levels: Array[SkillProfile] = []
	for level_id in [SkillProfile.Level.EASY, SkillProfile.Level.NORMAL,
			SkillProfile.Level.HARD, SkillProfile.Level.UNFAIR]:
		var profile := SkillProfile.new()
		profile.configure(level_id, SEED)
		levels.append(profile)
	_t.expect_len(levels.size(), 4, "there are four skill levels")

	for i in range(1, levels.size()):
		var easier := levels[i - 1]
		var harder := levels[i]
		var easier_name := SkillProfile.level_name(easier.level)
		var harder_name := SkillProfile.level_name(harder.level)
		_t.expect_le(harder.reaction_delay, easier.reaction_delay,
			"%s reacts at least as fast as %s" % [harder_name, easier_name])
		_t.expect_le(harder.aim_noise, easier.aim_noise,
			"%s aims at least as accurately as %s" % [harder_name, easier_name])
		_t.expect_le(harder.flap_timing_error, easier.flap_timing_error,
			"%s times its flaps at least as precisely as %s" % [harder_name, easier_name])
		_t.expect_le(harder.panic_threshold, easier.panic_threshold,
			"%s gives up on a smooth line at least as late as %s" % [harder_name, easier_name])
		_t.expect_ge(harder.aggression, easier.aggression,
			"%s commits at least as hard as %s" % [harder_name, easier_name])

	# The aim error is specified as a fraction of the tightest clear band the
	# difficulty curve ever produces, so that is what gets asserted. A fixed
	# literal here would be a test of the number rather than of the rule, and
	# the rule is the thing that keeps every level flyable.
	var tightest_band := GameConfig.GAP_MIN * 0.5 - GameConfig.PLAYER_RADIUS
	_t.expect_gt(levels[0].aim_noise, tightest_band * 0.15,
		"EASY's aim error is a serious fraction of the tightest band")
	_t.expect_lt(levels[1].aim_noise, tightest_band * 0.10,
		"NORMAL's aim error leaves the co-pilot room to hit a tight gap")
	_t.expect_lt(levels[3].aim_noise, tightest_band * 0.05,
		"UNFAIR's aim error is almost nothing next to the band it has to hit")
	_t.expect_gt(levels[0].aim_noise / maxf(levels[3].aim_noise, 0.0001), 5.0,
		"the ladder spans a factor of five in aim error, not a rounding difference")
	# Strictly decreasing, so no two levels are the same pilot twice.
	for i in range(1, levels.size()):
		_t.expect_lt(levels[i].aim_noise, levels[i - 1].aim_noise,
			"%s aims more accurately than %s" % [
				SkillProfile.level_name(levels[i].level),
				SkillProfile.level_name(levels[i - 1].level)])
	_t.expect_almost_eq(levels[0].aggression, 0.20, 0.001, "EASY holds back")
	_t.expect_almost_eq(levels[3].aggression, 1.00, 0.001, "UNFAIR never holds back")

	var first := SkillProfile.new()
	first.configure(SkillProfile.Level.NORMAL, SEED)
	var same := SkillProfile.new()
	same.configure(SkillProfile.Level.NORMAL, SEED)
	var identical := true
	for i in 50:
		if not is_equal_approx(first.aim_error(), same.aim_error()):
			identical = false
	_t.expect_true(identical, "two profiles on the same seed draw identical noise")

	var other := SkillProfile.new()
	other.configure(SkillProfile.Level.NORMAL, SEED + 1)
	var differs := false
	for i in 50:
		if not is_equal_approx(first.aim_error(), other.aim_error()):
			differs = true
	_t.expect_true(differs, "a different seed draws different noise")

	# A typo in a skill name must not stop the game from starting.
	_t.expect_eq(SkillProfile.level_from_name("nonsense"), SkillProfile.Level.NORMAL,
		"an unknown skill name falls back to NORMAL")
	_t.expect_eq(SkillProfile.level_from_name("UNFAIR"), SkillProfile.Level.UNFAIR,
		"skill names are case-insensitive")
	_t.complete()
