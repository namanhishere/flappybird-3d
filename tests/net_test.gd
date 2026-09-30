extends Node

## The online suite: a host and a client, in one process, through the real
## replication path.
##
## Both peers are real Game nodes built from the real scene, and the messages
## between them go through MultiplayerLink's real handlers -- the same ones the
## RPC bodies call. What is missing is only the socket, which is what makes it
## run in three seconds and fail with a number rather than a timeout. A
## separate smoke test opens a real loopback connection to prove the socket
## path too; between them, neither the authority rules nor the replication are
## taken on trust.
##
##     make net-test

const MAIN_SCENE := "res://scenes/main.tscn"
const STEP := 1.0 / 60.0
const SEED := 20260927
## How close the client's altitude has to be to the host's, in metres, once
## the run has settled. The client is a frame or two behind by construction --
## it reconciles towards twenty snapshots a second -- so this is a tolerance,
## not an equality.
const POSITION_TOLERANCE := 0.6

var _t := TestFramework.new()
var _games: Array[Game] = []

func _ready() -> void:
	InputActions.register_actions()
	for test: Array in _suite():
		_t.begin(test[0])
		(test[1] as Callable).call()
		_t.finish()
	_report()
	_cleanup()
	await get_tree().process_frame
	get_tree().quit(0 if _t.failed_count() == 0 else 1)

func _suite() -> Array:
	return [
		["a host and a client agree on the course from one seed", _test_seed_sync],
		["the client's steer reaches the host and moves the bird", _test_steer_reaches_host],
		["the client converges on the host's bird", _test_client_converges],
		["the client's score never runs ahead of the host's", _test_score_never_ahead],
		["a peer sending the axis it does not own changes nothing", _test_axis_ownership_over_the_wire],
		["the 20 Hz snapshot budget is paced by the wall clock", _test_snapshot_budget_is_wall_clock],
	]

# --- the individual checks --------------------------------------------------

## The course is a pure function of one integer, so agreeing on the seed is
## agreeing on every pipe. Nothing else about the level is ever sent.
func _test_seed_sync() -> void:
	var host := _peer(MatchConfig.Mode.HOST)
	var client := _peer(MatchConfig.Mode.CLIENT)
	# A client that has been told the seed rebuilds the corridor from it.
	client._on_match_received(SEED, MatchConfig.Role.FLAP, MatchConfig.Role.STEER,
		SkillProfile.Level.NORMAL)
	_t.expect_eq(client.course_seed, host.course_seed,
		"both peers are flying the same course")
	_t.expect_gt(client.spawner.obstacle_count(), 0, "the client has a corridor")
	_t.expect_eq(client.spawner.obstacle_count(), host.spawner.obstacle_count(),
		"with the same number of pipes")
	var compared := 0
	for i in mini(client.spawner.obstacles.size(), host.spawner.obstacles.size()):
		_t.expect_almost_eq(client.spawner.obstacles[i].gap_center_y,
			host.spawner.obstacles[i].gap_center_y, 0.0,
			"pipe %d is at the same height on both peers" % i)
		_t.expect_almost_eq(client.spawner.obstacles[i].position.x,
			host.spawner.obstacles[i].position.x, 0.0,
			"pipe %d is at the same lateral offset on both peers" % i)
		compared += 1
	_t.expect_gt(float(compared), 3.0, "and it compared a real number of pipes")
	_t.complete()

## The client's steer arrives, is accepted, and actually moves the bird. This is
## the one message a client can send that has a visible effect, so it is the one
## that has to be proven to work end to end.
func _test_steer_reaches_host() -> void:
	var host := _peer(MatchConfig.Mode.HOST)
	host.start()
	_t.expect_eq(ControlMap.source_for(MatchConfig.Mode.HOST, MatchConfig.Role.STEER),
		ControlMap.Source.REMOTE, "on a host the steer comes off the wire")

	host.link.receive_steer(1.0)
	_t.expect_almost_eq(host._remote_steer, 1.0, 0.001,
		"a steer message becomes the host's held steer")
	var before := host.player.flight.position_x
	for i in 30:
		host.advance(STEP)
	_t.expect_gt(host.player.flight.position_x, before,
		"and thirty steps of it move the bird sideways")

	# A value outside the axis is clamped on arrival, not on use.
	host.link.receive_steer(9.0)
	_t.expect_almost_eq(host._remote_steer, 1.0, 0.001,
		"a steer beyond the axis is clamped to it")
	host.link.receive_steer(NAN)
	_t.expect_almost_eq(host._remote_steer, 0.0, 0.001,
		"and a non-finite steer is refused outright")
	_t.complete()

## After a run, the client's bird is where the host says it is.
##
## Not equal -- the client is between snapshots by construction, and the whole
## point of reconciling is that the error decays rather than snapping. What
## must hold is that the error is small and shrinking, and that a client which
## has drifted absurdly far is snapped rather than eased.
func _test_client_converges() -> void:
	var host := _peer(MatchConfig.Mode.HOST)
	var client := _peer(MatchConfig.Mode.CLIENT)
	host.start()
	client.start()
	# The host flies itself, with the same CoPilotBrain the game ships, rather
	# than a hand-written stand-in. A second, weaker pilot living in the test
	# suite is a second thing to be wrong about, and the real one is right here.
	host.autopilot = true
	for i in 240:
		host.link.receive_steer(0.3)
		host.advance(STEP)
		if i % 3 == 0:
			client.link.receive_snapshot(host.snapshot_payload())
		client.advance(STEP)

	_t.expect_eq(client.state, host.state,
		"the client shows whatever the host says, including a game over")
	var error := absf(client.player.flight.position_y - host.player.flight.position_y)
	# The client is never exactly level with the host: it glides towards twenty
	# snapshots a second with a time constant, so at steady state it trails by
	# roughly the host's vertical speed times that constant. Asserting a
	# constant would be asserting a number the physics chooses, so the bound is
	# derived from it -- and the point being made is "tracking", not "equal".
	var host_fall := absf(host.player.flight.velocity_y)
	var allowed := maxf(POSITION_TOLERANCE, host_fall * GameConfig.RECONCILE_TIME * 2.0)
	_t.expect_lt(error, allowed,
		("the client's altitude tracks the host's (off by %.3fm, allowed %.3fm "
			+ "at %.1fm/s falling)") % [error, allowed, host_fall])
	_t.expect_le(client.score, host.score, "and its score is the host's, not more")

	# Push the client a long way out and check it snaps rather than easing: past
	# a certain distance the two are not slightly out of step, they are
	# describing different flights.
	client.player.flight.position_y += GameConfig.RECONCILE_SNAP_DISTANCE + 1.0
	client.link.receive_snapshot(host.snapshot_payload())
	client.advance(STEP)
	_t.expect_lt(absf(client.player.flight.position_y - host.player.flight.position_y),
		GameConfig.RECONCILE_SNAP_DISTANCE,
		"a client that has lost the plot is put back rather than eased back")
	_t.complete()

## A client that scored before the host told it to would be showing a score
## the host does not believe. Reconciliation takes the host's number outright,
## so the invariant is that a client is never ahead.
func _test_score_never_ahead() -> void:
	var host := _peer(MatchConfig.Mode.HOST)
	var client := _peer(MatchConfig.Mode.CLIENT)
	host.start()
	client.start()
	# Put the client deliberately ahead, as a bug elsewhere would.
	client.score = 7
	host.score = 2
	client.link.receive_snapshot(host.snapshot_payload())
	_t.expect_le(client.score, host.score,
		"a client showing more than the host is pulled back to the host's score")

	var ahead := false
	host.autopilot = true
	for i in 240:
		host.link.receive_steer(0.2)
		host.advance(STEP)
		if i % 3 == 0:
			client.link.receive_snapshot(host.snapshot_payload())
		client.advance(STEP)
		if client.score > host.score:
			ahead = true
	_t.expect_false(ahead, "and over a whole run the client's score is never ahead")
	_t.expect_eq(client.score, host.score,
		"ending level with the host's score")
	_t.complete()

## The authority rule, proven over the wire rather than only in the unit test:
## a peer assigned the steer axis that sends a flap is ignored entirely. Not
## slowed, not corrected -- the bird does not move at all.
func _test_axis_ownership_over_the_wire() -> void:
	var host := _peer(MatchConfig.Mode.HOST)
	host.start()
	_t.expect_eq(host.remote_authority.role, MatchConfig.Role.STEER,
		"the remote peer was assigned the steer axis")
	_t.expect_false(host.remote_authority.owns(MatchConfig.Role.FLAP),
		"so it does not own the flap axis")

	var before := host.player.flight.flap_count
	for i in 10:
		host.link.receive_flap()
	_t.expect_eq(host.player.flight.flap_count, before,
		"ten flap messages from a steer peer move the bird not at all")

	# And the flap a host *does* accept still works, so the rule is not simply
	# refusing everything.
	host.remote_authority.configure(MatchConfig.Role.FLAP)
	host.link.receive_flap()
	host.advance(STEP)
	_t.expect_eq(host.player.flight.flap_count, before + 1,
		"a flap from a peer that does own the axis is applied")
	_t.complete()

## The snapshot budget is paced by the wall clock, and both halves of that
## matter.
##
## Paced in real time, a host spends its whole budget: about twenty snapshots a
## second, no more. Paced by the simulation clock it would flood instead, which
## is what a host with vsync off, or a headless one, actually does -- it
## simulates faster than real time and turns twenty simulated snapshots a
## second into eighty real ones. Snapshots are a network concern, so they are
## paced by the network clock.
##
## The first half of this test is the anti-flood property and is deliberately
## brutal: a thousand simulation frames in a fraction of a second must publish
## almost nothing.
func _test_snapshot_budget_is_wall_clock() -> void:
	var host := _peer(MatchConfig.Mode.HOST)
	host.autopilot = true
	host.start()

	for i in 1000:
		host.advance(STEP)
	var wall_ms := float(Time.get_ticks_msec())
	var allowed := wall_ms / 1000.0 / Protocol.snapshot_interval() + 1.0
	_t.expect_le(float(host.snapshots_published), allowed,
		"a host that outran real time published %d snapshots, more than the %.1f "
		% [host.snapshots_published, allowed]
		+ "its wall clock allowed")
	_t.expect_lt(float(host.snapshots_published), 50.0,
		"and nowhere near a hundred frames' worth of them")

	# Now spend a real second and check the rate itself. The *increment* over
	# that second is what matters: the burst above already spent part of the
	# budget, and a total would charge the paced second for it.
	var before := host.snapshots_published
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 1000:
		host.advance(STEP)
	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	var published := host.snapshots_published - before
	var expected := int(seconds / Protocol.snapshot_interval())
	_t.expect_le(absf(float(published) - float(expected)), 3.0,
		"in %.2f real seconds the host published %d snapshots, against %d at %d Hz" % [
			seconds, published, expected, Protocol.SNAPSHOT_HZ])
	_t.complete()

# --- fixtures ---------------------------------------------------------------

func _peer(mode: int) -> Game:
	var packed := load(MAIN_SCENE) as PackedScene
	var game := packed.instantiate() as Game
	add_child(game)
	game.fixed_seed = SEED
	game.apply_mode(mode)
	_games.append(game)
	return game

func _cleanup() -> void:
	for game in _games:
		if is_instance_valid(game):
			var sfx := game.get_node_or_null("Sfx")
			if sfx != null and sfx.has_method("stop_all"):
				sfx.stop_all()
			game.free()
	_games.clear()

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
	print("Online tests: %d passed, %d failed, %d total" % [
		_t.passed_count(), _t.failed_count(), _t.results().size()])
