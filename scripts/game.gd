extends Node3D
class_name Game

## The game controller: owns the state machine, the order in which the pieces
## advance each step, and the single place a BirdIntent becomes bird motion.
##
## The simulation is driven by advance(delta), a plain method with an exact
## delta. _physics_process simply forwards to it, but tests call advance()
## directly, which is what makes every gameplay assertion deterministic and
## independent of frame timing -- and, because the only input is a BirdIntent,
## independent of a keyboard, a window and a socket.

enum State { MENU, READY, PLAYING, GAME_OVER }

signal state_changed(state: int)
signal score_changed(score: int)
signal lives_changed(lives: int)

## Set to a value >= 0 to make the course reproducible. Left at -1 the game
## picks a fresh seed each run, which is what you want when playing.
@export var fixed_seed: int = -1
## Drives both axes from the AI whatever the mode says.
##
## This is what `--autoplay` sets: a game that can be smoke-tested for real in
## a rendered window with nobody at the keyboard. It overrides the source
## table rather than being a row in it, because "no human at all" is the
## absence of a co-op mode rather than a seventh one.
@export var autopilot: bool = false
## Open with the F1 panel already showing. See _read_launch_arguments.
@export var overlay_on_start: bool = false

var state: int = State.MENU
var score: int = 0
var best_score: int = 0
var lives: int = GameConfig.LIVES
var course_seed: int = 0

var config := MatchConfig.new()
## Validates the *remote* peer's messages. A host is the authority and does
## not need to police itself; the one peer whose input cannot be trusted is
## the one on the other end of the socket, so that is the one Authority is for.
var remote_authority := Authority.new()
var local_input := LocalInput.new()
## One brain per axis, indexed by MatchConfig.Role. A co-op mode consults only
## the brain for the axis nobody local owns; --autoplay consults both.
var brains: Array[CoPilotBrain] = [CoPilotBrain.new(), CoPilotBrain.new()]

@onready var player: Player = $Player
@onready var spawner: ObstacleSpawner = $ObstacleSpawner
@onready var ground: Ground = $Ground
@onready var ui: GameUI = $UI
@onready var sfx: Node = $Sfx
@onready var menu: ModeMenu = $ModeMenuLayer/ModeMenu
@onready var overlay: AIOverlay = $AIOverlay
@onready var marker: TargetMarker = $TargetMarker
@onready var hunter: HunterDrone = $HunterDrone
@onready var link: MultiplayerLink = $NetLink

var _input_lock: float = 0.0
var _death_reason: String = ""
var _elapsed: float = 0.0
var _mode_chosen: bool = false
## Seconds left of the post-catch grace period.
var _invulnerable: float = 0.0
## The remote peer's last *accepted* steer. It is validated the moment it
## arrives and then simply held, because steer is continuous state: the newest
## accepted reading replaces the last one and a dropped packet costs a frame of
## smoothness and nothing else.
var _remote_steer: float = 0.0
## The host's altitude and its vertical speed, on a client. The client owns the
## steer and takes the flap axis whole, rather than predicting an impulse it
## was never sent; see _publish_or_reconcile.
var _host_altitude: float = 0.0
var _host_fall: float = 0.0
## Wall-clock time, in milliseconds, at which the next snapshot goes out.
##
## Paced by the wall clock and not by the simulation clock, and the distinction
## matters. A countdown driven by the frame delta never quite reaches its
## interval -- three frames of 1/60 is 0.049999999999999996, a hair under the
## 0.05 s a 20 Hz feed wants, so the host quietly publishes at 15 Hz. And a
## process that simulates faster than real time, which a window with vsync off
## or a headless run will happily do, turns its 20 simulated snapshots a second
## into eighty-odd real ones and floods the socket.
##
## Snapshots are a network concern, so they are paced by the network clock: one
## every 50 ms of actual time, whatever the simulation is doing.
var _next_snapshot_ms: int = 0
## How many snapshots this host has published. The wire log is the evidence
## that the course was never transmitted.
var snapshots_published: int = 0

func _ready() -> void:
	_read_launch_arguments()
	$Sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	menu.mode_confirmed.connect(_on_mode_confirmed)
	spawner.pipe_passed.connect(_on_pipe_passed)
	link.intent_received.connect(_on_intent_received)
	link.snapshot_received.connect(_on_snapshot_received)
	link.match_received.connect(_on_match_received)
	link.start_requested.connect(_on_start_requested)
	link.role_requested.connect(_on_role_requested)
	link.peer_joined.connect(_on_peer_joined)
	link.peer_left.connect(_on_peer_left)
	reset()
	if overlay_on_start:
		overlay.visible = true
		_refresh_ai_overlay()
	if autopilot and _mode_chosen:
		# A smoke run wants to be in the air immediately: no menu to confirm
		# through, because there is no human here to confirm anything.
		start()

## Quitting mid-flap used to leave the clip playing, and an AudioStreamWAV that
## is still referenced at exit is reported as a leak -- which the error gate then
## fails the build on. This was latent rather than absent: the old autoplay
## pilot flapped a few times a second and the run was short, so the window in
## which the process exited with a flap sounding was narrow. An AI that flaps
## constantly widened it into something that failed roughly one run in three.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE and what != NOTIFICATION_EXIT_TREE:
		return
	if sfx != null and sfx.has_method("stop_all"):
		sfx.stop_all()

## Quits after `--frames=N`, having stopped the audio a frame earlier.
##
## This exists instead of the engine's `--quit-after`, and the reason is a
## shutdown race. `--quit-after` tears the scene tree down on the same frame
## the last clip is still sounding, and an `AudioStreamWAV` still referenced
## when the resource cache is cleared is reported as "1 resources still in use
## at exit" -- which this project's error gate correctly treats as a failure.
## The window is narrow and it got much wider once an AI was flapping several
## times a second, at which point roughly one run in three failed for a reason
## that has nothing to do with the game.
##
## Owning the quit means the audio is stopped on one frame and the tree is torn
## down on the next, which is deterministic.
var _quit_after: int = 0
var _quit_frame: int = 0
## Whether the audio has already been stopped on the way out. Kept separate
## from the quit itself: one flag doing both jobs means the frame that stops
## the audio also marks the run finished, and the guard at the top of this
## function then returns before the quit is ever reached.
var _audio_stopped: bool = false

func _process(_delta: float) -> void:
	if _quit_after <= 0:
		return
	_quit_frame += 1
	# Three frames, not one. One looked sufficient when the host was cheap to
	# render and stopped being sufficient once the AI was on the flap axis and
	# the frame rate dropped: the audio server needs a frame or two to release
	# a finished playback, and a clip still referenced when the resource cache
	# is cleared is reported as a leak, which the error gate correctly fails.
	if _quit_frame >= _quit_after - 3 and not _audio_stopped:
		_audio_stopped = true
		if sfx != null:
			sfx.stop_all()
	if _quit_frame >= _quit_after:
		get_tree().quit()

## Reads one `--key=value` argument, returning a fallback when it is absent.
static func _argument(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback

# --- launch ------------------------------------------------------------------

## Reads the arguments after the engine's `--` separator.
##
## A launch that names no mode leaves the game on the menu, which is where a
## mode is chosen with a human present. A launch that names one skips the menu
## entirely, so `make demo-2p` and picking LOCAL 2P by hand reach the same
## configuration by two different routes.
func _read_launch_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	autopilot = args.has("--autoplay")
	_quit_after = int(_argument(args, "--frames=", "0"))
	# Headless, Godot runs frames as fast as the CPU allows, so a run that
	# claims to be twelve seconds can finish in one -- and a host and a client
	# doing that drift apart in real time, which is not a network test. This
	# caps the frame rate so simulated seconds are real seconds.
	if args.has("--realtime"):
		Engine.max_fps = 60
	# `--overlay` opens with the explainability panel already up. A human gets
	# it from F1, but a frame capture and a headless demo have no keyboard, and
	# an explainability feature nobody can photograph is an explainability
	# feature nobody will see.
	overlay_on_start = args.has("--overlay")
	var named := false
	for arg in args:
		if arg.begins_with("--mode="):
			named = true
			break
	config = MatchConfig.from_args(args)
	# `--autoplay` with no mode is a solo run with no human at the keyboard.
	# Requiring an explicit --mode here meant the smoke run sat on the title
	# card forever: it "passed" because nothing errored, while the game it was
	# supposed to be exercising never flew a single frame. A frame capture is
	# what caught it.
	_mode_chosen = named or autopilot
	if not named and autopilot:
		config.set_mode(MatchConfig.Mode.SOLO)
	_open_link()

## Opens the socket for the two online modes, and says so plainly if it cannot.
##
## Reported rather than swallowed: a host that silently failed to listen would
## look exactly like a host with nobody connecting, and the demo would be two
## windows and no bird between them.
func _open_link() -> void:
	var result := OK
	match config.mode:
		MatchConfig.Mode.HOST:
			result = link.host(config.port)
			if result == OK:
				print("NET host listening on port %d" % config.port)
		MatchConfig.Mode.CLIENT:
			result = link.join(config.address, config.port)
			if result == OK:
				print("NET client dialling %s:%d" % [config.address, config.port])
	if result != OK:
		push_error("could not open the network link: %s" % error_string(result))

# --- state machine -----------------------------------------------------------

## Chooses a mode and puts the game on the title card, ready to fly.
func apply_mode(mode: int, skill: int = SkillProfile.Level.NORMAL) -> void:
	config.set_mode(mode)
	config.skill = skill
	_mode_chosen = true
	reset()

## Returns everything to the start-of-run state.
func reset() -> void:
	score = 0
	lives = GameConfig.LIVES
	_input_lock = 0.0
	_elapsed = 0.0
	var chosen_seed := config.seed_value if config.seed_value != 0 else 0
	course_seed = fixed_seed if fixed_seed >= 0 else (chosen_seed if chosen_seed != 0 else randi())
	player.reset()
	spawner.reset(player.position.z, course_seed)
	ground.reset(player.position.z)
	remote_authority.configure(config.remote_role)
	# Both brains are seeded from the course seed, so a run is reproducible
	# from one number even when the AI is flying an axis.
	brains[MatchConfig.Role.FLAP].configure(MatchConfig.Role.FLAP, config.skill, course_seed)
	brains[MatchConfig.Role.STEER].configure(MatchConfig.Role.STEER, config.skill, course_seed)
	hunter.reset(Vector3(0.0, GameConfig.START_Y + 9.0, player.position.z - 12.0),
		config.skill, course_seed)
	_invulnerable = 0.0
	_remote_steer = 0.0
	_host_altitude = GameConfig.START_Y
	_host_fall = 0.0
	_next_snapshot_ms = 0
	snapshots_published = 0
	_set_state(State.READY if _mode_chosen else State.MENU)
	score_changed.emit(score)
	lives_changed.emit(lives)

## Leaves the title card and starts flying.
func start() -> void:
	if state == State.MENU and not (_mode_chosen and autopilot):
		return
	if state != State.READY and state != State.MENU:
		return
	_set_state(State.PLAYING)

## A full restart, without passing back through the title card.
func restart() -> void:
	reset()
	start()

## Queues a flap. Public so the headless tests can drive the bird without
## synthesising input events; a keystroke queues exactly the same request and
## the next fixed step applies it, so there is one path, not two.
func flap() -> void:
	if state != State.PLAYING:
		return
	local_input.queue_flap()

func _on_mode_confirmed(mode: int, skill: int) -> void:
	apply_mode(mode, skill)

# --- simulation --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	advance(delta)

## Advances the whole game by one step, and is the single place the simulation
## order is defined:
##
##   1. gather each axis's intent from whichever source owns that axis;
##   2. apply it -- the one place in the codebase the bird is mutated;
##   3. the hunter drone, if there is one, and the wind it writes;
##   4. the ground, the corridor, the score and the lives;
##   5. the four ways to lose.
func advance(delta: float) -> void:
	_input_lock = maxf(_input_lock - delta, 0.0)
	if state != State.PLAYING:
		# A host keeps reporting after the run has ended. The client has to be
		# told the run is over, and a channel that goes quiet at exactly the
		# moment it starts to matter is a channel nobody can trust: the client
		# would sit showing a score the host had already finished.
		_elapsed += delta
		_publish_or_reconcile(delta)
		return

	_apply_intent(_gather_intent(delta))
	_advance_hunter(delta)
	player.advance(delta)
	_refresh_ai_overlay()
	ground.advance(player.position.z)
	spawner.advance(player.position.z, score)
	# On a client the host decides whether the run is still on: it owns the
	# flap, so it owns the pipes too. The client shows what it is told.
	if config.mode == MatchConfig.Mode.CLIENT:
		_publish_or_reconcile(delta)
		return
	if _check_hunter_contact():
		_publish_or_reconcile(delta)
		return
	_publish_or_reconcile(delta)

	if player.flight.is_below_floor():
		_game_over("GROUNDED")
		return
	if player.flight.is_above_ceiling():
		_game_over("OVER THE SKY")
		return
	for obstacle in spawner.obstacles:
		if obstacle.overlaps(player.position, GameConfig.PLAYER_RADIUS):
			_game_over("HIT A PIPE")
			return

## One BirdIntent, assembled from whichever source owns each axis.
##
## The mode table decides the source and the source decides who gets to fill
## that half of the intent. No axis ever has two sources, so a mode cannot
## produce a shared control, and the two players' inputs cannot collide even
## in principle.
func _gather_intent(delta: float) -> BirdIntent:
	# The hunter is handed to the sensors as well as to its own brain, so the
	# co-pilot can see the drone coming rather than only feeling the shove.
	var sensors := BirdSensors.from_world(player, spawner, hunter, delta, _elapsed)
	_elapsed += delta
	var intent := BirdIntent.new()

	# The flap axis is an event, not a state: either a human queued a press
	# this tick, or the brain's scheduled flap came due.
	match _source_for(MatchConfig.Role.FLAP):
		ControlMap.Source.LOCAL:
			if local_input.take_flap():
				intent.request_flap()
		ControlMap.Source.AI:
			if brains[MatchConfig.Role.FLAP].decide(sensors).consume_flap():
				intent.request_flap()
		_:
			# REMOTE, on a client: the host owns the flap, and the client's
			# altitude is taken from the host's snapshots rather than simulated.
			# Predicting a control this peer does not hold would only mean
			# reconciling the prediction away again.
			pass

	# The steer axis is continuous state, so the latest reading simply
	# replaces the last one. A mode with no steer axis has nothing to read.
	if not ControlMap.has_axis(config.mode, MatchConfig.Role.STEER) and not autopilot:
		return intent
	match _source_for(MatchConfig.Role.STEER):
		ControlMap.Source.LOCAL:
			intent.set_steer(local_input.steer())
		ControlMap.Source.AI:
			intent.set_steer(brains[MatchConfig.Role.STEER].decide(sensors).steer)
		ControlMap.Source.REMOTE:
			# The remote peer's last accepted steer. It was validated the
			# moment it arrived, so it is simply held here: steer is continuous
			# state and the newest accepted reading replaces the last one.
			intent.set_steer(_remote_steer)
	return intent

## The one place in the codebase where an intent moves the bird.
##
## Steer is written unconditionally, because it is a level the axis rests at
## and the intent always carries the reading for whichever source owns it. A
## flap is consumed, so a request that was never applied cannot linger and
## fire a frame later.
func _apply_intent(intent: BirdIntent) -> void:
	player.flight.set_steer(intent.steer)
	if intent.consume_flap():
		player.flap()
		sfx.play_flap()

## The host publishes twenty snapshots a second; a client spends them.
##
## This is the whole of the network model, and it is deliberately asymmetric.
## Each control axis has exactly one owner -- in HOST the local player owns the
## flap and the remote peer owns the steer, in CLIENT the other way round -- so
## a client never has to predict a control it does not hold. It simulates its
## own axis exactly, and takes the other one from the host. Reconciling only the
## axis the client does not own is not a simplification; it is what the
## two-axis design buys, and it is why a 20 Hz feed is enough to look smooth.
func _publish_or_reconcile(delta: float) -> void:
	if config.mode == MatchConfig.Mode.HOST:
		# Wall clock, not simulation clock: see _next_snapshot_ms.
		var now_ms := Time.get_ticks_msec()
		if now_ms >= _next_snapshot_ms:
			_next_snapshot_ms = now_ms + int(Protocol.snapshot_interval() * 1000.0)
			link.send_snapshot(snapshot_payload())
			snapshots_published += 1
		return
	if config.mode != MatchConfig.Mode.CLIENT:
		return
	# The client owns the steer, so the altitude is entirely the host's to say:
	# both where the bird is and how fast it is moving vertically. Taking the
	# velocity as well as the position is the difference between correcting
	# toward the truth and correcting toward a bird that is still falling
	# under a gravity the client has no impulse to answer. A lerp that starts
	# from the client's own simulated altitude only removes a fraction of the
	# gap each step, so the error settles well above the lag it should.
	player.flight.velocity_y = _host_fall
	var target := _host_altitude
	# Beyond a certain distance the two are not slightly out of step, they are
	# describing different flights, and gliding would take time to arrive
	# somewhere wrong.
	if absf(target - player.flight.position_y) > GameConfig.RECONCILE_SNAP_DISTANCE:
		player.flight.position_y = target
		player.position.y = target
		return
	player.flight.position_y = lerpf(player.flight.position_y, target,
		clampf(delta / GameConfig.RECONCILE_TIME, 0.0, 1.0))
	player.position.y = player.flight.position_y

## The host's state, as it goes on the wire. Everything the client is told to
## believe, and nothing it is not.
func snapshot_payload() -> Array:
	var flight := player.flight
	var snapshot := BirdState.new()
	snapshot.set_values(Vector2(flight.position_x, flight.position_y),
		Vector2(flight.velocity_x, flight.velocity_y), score, lives, true, state)
	return snapshot.to_payload()

func _on_snapshot_received(payload: Array) -> void:
	var host := BirdState.from_payload(payload)
	_host_altitude = host.y
	_host_fall = host.vy
	# The host owns the truth, so the client takes it outright rather than
	# nudging towards it. A client whose score is ahead of the host's is a bug,
	# and the test suite asserts it cannot happen.
	score = mini(score, host.score)
	lives = host.lives
	if state != host.game_state:
		_set_state(host.game_state)

func _on_intent_received(flap: bool, steer: float) -> void:
	# Everything a peer says is filtered through the authority first. A peer
	# that sends the axis it does not own is dropped here, silently, and never
	# reaches the bird.
	if config.mode != MatchConfig.Mode.HOST:
		return
	if flap:
		if remote_authority.request_flap(_elapsed):
			local_input.queue_flap()
		return
	_remote_steer = remote_authority.request_steer(steer)

func _on_match_received(seed_value: int, host_role: int, client_role: int,
		skill: int) -> void:
	# The whole level, in one integer. Nothing else is ever sent.
	config.seed_value = seed_value
	config.local_role = client_role
	config.remote_role = host_role
	config.skill = skill
	_mode_chosen = true
	reset()
	# The match *is* the go-ahead: the host has told this client what it is
	# flying and which axis it owns, and there is nothing further to agree on.
	start()
	# The match *is* the go-ahead: the host has told this client what it is
	# flying and which axis it owns, and there is nothing further to agree on.
	start()

## A peer has gone. The host reports what it managed to send while it could,
## because a snapshot count is the only honest way to say how much of the
## twenty-a-second budget actually reached anybody.
func _on_peer_left(_peer_id: int) -> void:
	if config.mode == MatchConfig.Mode.HOST:
		print("NET host_published %d over %.1fs" % [
			snapshots_published, _elapsed])

## The handshake.
##
## A client says hello and claims an axis; the host answers with the course and
## either agrees to the claim or refuses it. Nothing is sent until the client
## has said hello, so a host that is listening with nobody connected is
## genuinely idle rather than quietly transmitting to an empty room.
func _on_peer_joined(peer_id: int) -> void:
	if config.mode != MatchConfig.Mode.CLIENT:
		return
	# Hello, and a claim on an axis. The host's answer is the match itself, so
	# there is nothing else to negotiate and nothing else to wait for.
	link.send_start_request(peer_id)
	link.send_role_request(config.local_role, peer_id)

func _on_start_requested(peer_id: int) -> void:
	if config.mode != MatchConfig.Mode.HOST:
		return
	# The host launches when someone turns up, not before: there is no run for
	# it to be publishing snapshots of, and an idle host should be genuinely
	# idle rather than transmitting a bird that nobody is flying.
	start()
	link.send_match(course_seed, config.local_role, config.remote_role,
		config.skill, peer_id)

## A peer that claims the axis the host already owns is refused, silently and
## without an error: the host has one flap and one steer, and there is no third
## player to give anything to.
func _on_role_requested(role: int, peer_id: int) -> void:
	if config.mode != MatchConfig.Mode.HOST:
		return
	if role == config.remote_role:
		return
	link.send_role_rejected(peer_id)

## The hunter drone, and the wake it writes into the bird.
##
## The force goes into FlightModel.external_accel rather than being applied
## here, for one reason that matters: the co-pilot reads that same field when it
## predicts the bird's future, so a shove the AI cannot see is a shove the AI
## will fly straight into. Writing it into the model means the AI's own
## simulation is pressed by exactly the same wind the bird is.
func _advance_hunter(delta: float) -> void:
	_invulnerable = maxf(_invulnerable - delta, 0.0)
	var sensors := HunterSensors.from_world(player, hunter, lives, score, delta, _elapsed)
	hunter.advance(delta, sensors)
	player.flight.external_accel = hunter.wind_at(
		Vector2(player.flight.position_x, player.flight.position_y))

## Contact costs exactly one life, then a forced retreat and a moment of
## invulnerability. Returns true when the run ended.
##
## Only a committed DIVE counts. While the drone is merely pressuring it orbits
## at PRESSURE_RADIUS, well outside the catch radius, and that proximity is
## pressure rather than a kill. This matters more than it looks: the co-pilot
## has no evasive behaviour, so a drone that could catch the bird merely by
## being nearby would take all three lives in the first three seconds of
## hunting and the whole "pressure" half of the design would be unreachable.
## A dive is a committed pass with a real chance of missing, and a miss is a
## normal outcome rather than a bug.
func _check_hunter_contact() -> bool:
	if _invulnerable > 0.0 or not hunter.diving:
		return false
	if not hunter.model.is_touching(player.position):
		return false
	lives -= 1
	hunter.note_contact()
	# The grace period is the bird's, and so is the retreat: the drone backing
	# off and the bird being untouchable are the same event seen from two sides.
	_invulnerable = GameConfig.HUNTER_INVULNERABILITY
	lives_changed.emit(lives)
	sfx.play_hit()
	if lives <= 0:
		_game_over("CAUGHT")
		return true
	_refresh_ui()
	return false

## The brain the overlay is currently pointed at.
func overlay_brain() -> CoPilotBrain:
	if overlay.current_view() == AIOverlay.View.COPILOT_STEER:
		return brains[MatchConfig.Role.STEER]
	return brains[MatchConfig.Role.FLAP]

## Redraws the overlay and the marker from the brain that just decided.
##
## Called once per step and only when the overlay is up, and never from a frame
## callback: the panel has to show the decision that was actually made this
## step, not a decision the brain has not taken yet.
func _refresh_ai_overlay() -> void:
	if not overlay.visible:
		return
	var shown := overlay_brain()
	overlay.refresh(shown)
	marker.refresh(shown.aim, player.position.z, shown.last_path, true)

## Which source fills an axis right now, including the --autoplay override.
func _source_for(axis: int) -> int:
	if autopilot:
		return ControlMap.Source.AI
	return ControlMap.source_for(config.mode, axis)

func _on_pipe_passed(_index: int) -> void:
	score += 1
	# The course tightens as the run goes on, and the bird speeds up with it.
	player.forward_speed = Difficulty.forward_speed(score)
	sfx.play_score()
	score_changed.emit(score)
	# The HUD is not driven by the signal, so it has to be told explicitly.
	# Without this the model scores correctly while the label stays at zero.
	_refresh_ui()

func _game_over(reason: String) -> void:
	if state != State.PLAYING:
		return
	best_score = maxi(best_score, score)
	_death_reason = reason
	_set_state(State.GAME_OVER)
	# A short lock so the press that killed the bird cannot restart it.
	_input_lock = 0.6
	sfx.play_hit()
	sfx.play_game_over()

# --- input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()
		return
	# While the menu is up every key belongs to the menu. That is what lets
	# the menu's UP and the bird's flap share a key without ever colliding.
	if state == State.MENU:
		for action in InputActions.menu_actions():
			if event.is_action_pressed(action) and menu.handle_action(action):
				get_viewport().set_input_as_handled()
				return
		return
	if event.is_action_pressed(InputActions.ACTION_RESTART) and state == State.PLAYING:
		restart()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.ACTION_TOGGLE_OVERLAY):
		overlay.toggle()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.ACTION_CYCLE_AI_VIEW):
		overlay.cycle_view(false)
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(InputActions.ACTION_FLAP):
		return
	match state:
		State.READY:
			start()
		State.PLAYING:
			flap()
		State.GAME_OVER:
			if _input_lock <= 0.0:
				restart()
	get_viewport().set_input_as_handled()

# --- plumbing ----------------------------------------------------------------

func _set_state(new_state: int) -> void:
	state = new_state
	state_changed.emit(new_state)
	menu.visible = new_state == State.MENU
	_refresh_ui()

func _refresh_ui() -> void:
	var reason := ""
	if state == State.GAME_OVER:
		reason = _death_reason
	ui.refresh(state, score, best_score, lives, _mode_line(), reason, _hunter_warning())

## Who is driving each axis, for the HUD. Written out rather than shown as a
## mode name, because "LOCAL 2P" does not tell a viewer which player has which
## key, and that is the single most useful thing to know while watching.
func _mode_line() -> String:
	var parts: Array[String] = []
	for axis_value: int in [MatchConfig.Role.FLAP, MatchConfig.Role.STEER]:
		if not ControlMap.has_axis(config.mode, axis_value) and not autopilot:
			parts.append("%s: --" % MatchConfig.role_name(axis_value))
			continue
		parts.append("%s: %s" % [
			MatchConfig.role_name(axis_value),
			ControlMap.source_name(_source_for(axis_value))])
	return "   ".join(parts)

## What the HUD says about the drone. The dive warning is the useful one: it is
## the half-second in which the player can still do something about it.
func _hunter_warning() -> String:
	if state != State.PLAYING:
		return ""
	if _invulnerable > 0.0:
		return "caught -- the drone is pulling off"
	if hunter.diving:
		return "HUNTER DIVING"
	return ""

func game_over_reason() -> String:
	return _death_reason

## The brain for one axis, so the overlay and the tests can read the AI's own
## state rather than a copy the game kept.
func brain_for(axis: int) -> CoPilotBrain:
	return brains[axis]
