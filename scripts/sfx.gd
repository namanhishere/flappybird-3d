extends Node

## Sound effects.
##
## The four clips are generated procedurally by tools/gen_audio.py -- simple
## synthesised tones, committed as ordinary .wav files -- so the game ships
## with audio without carrying any third-party asset or licence.

const CLIP_FLAP := "res://assets/audio/flap.wav"
const CLIP_HIT := "res://assets/audio/hit.wav"
const CLIP_SCORE := "res://assets/audio/score.wav"
const CLIP_GAME_OVER := "res://assets/audio/game_over.wav"

var _players: Dictionary[StringName, AudioStreamPlayer] = {}
var _missing_clips: Array[String] = []

func _ready() -> void:
	for clip: String in [CLIP_FLAP, CLIP_HIT, CLIP_SCORE, CLIP_GAME_OVER]:
		var player := AudioStreamPlayer.new()
		player.name = clip.get_file().get_basename().to_pascal_case()
		player.stream = _load_clip(clip)
		player.bus = &"Master"
		add_child(player)
		_players[player.name] = player

## A missing clip is reported once and then ignored, so a build without the
## audio folder still runs silently instead of spamming errors every frame.
func _load_clip(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		if not _missing_clips.has(path):
			_missing_clips.append(path)
			push_warning("Sound clip not found, running without it: %s" % path)
		return null
	return load(path) as AudioStream

## True when every clip resolved, which the test suite asserts so audio cannot
## silently disappear from a build.
func all_clips_loaded() -> bool:
	return _missing_clips.is_empty()

## Number of clips wired up, for the test suite.
func player_count() -> int:
	return _players.size()

## True when there is a real device to play through.
##
## Godot's headless mode selects a "Dummy" audio driver. It never mixes what it
## is given, so every play() would allocate a playback object that nothing ever
## claims and the run would finish littered with leaked objects. Skipping
## playback is also simply the right behaviour for a machine with no sound
## card. The clips are still loaded and validated either way, and playback is
## exercised for real by `make run` and by the exported binary, which both use
## an actual audio driver.
static func has_audio_output() -> bool:
	return AudioServer.get_driver_name() != "Dummy"

func _play(clip_name: StringName, volume_db: float = 0.0) -> void:
	if not has_audio_output():
		return
	if not _players.has(clip_name):
		return
	var player: AudioStreamPlayer = _players[clip_name]
	if player.stream == null:
		return
	player.volume_db = volume_db
	player.play()

func play_flap() -> void:
	_play(&"Flap")

func play_hit() -> void:
	_play(&"Hit")

func play_score() -> void:
	_play(&"Score")

func play_game_over() -> void:
	_play(&"GameOver")

## Releases every clip: stops the playback *and* drops the stream.
##
## Stopping alone is not enough. A player that has been stopped still holds its
## `AudioStreamWAV` on the `stream` property, and a clip still referenced when
## the resource cache is cleared is what Godot reports as "1 resources still in
## use at exit". Dropping the stream is what actually lets go of it.
func stop_all() -> void:
	for player in _players.values():
		if not is_instance_valid(player):
			continue
		player.stop()
		player.stream = null

## Releases every playback on the way out.
##
## A clip still sounding when the process quits keeps its `AudioStreamWAV`
## referenced, and Godot reports that as a resource still in use at exit -- which
## this project's error gate then fails the build on. It was latent rather than
## absent: the old autoplay pilot flapped rarely and the smoke run was short, so
## the window in which the process exited with a flap sounding was narrow. An AI
## that flaps constantly widened it until roughly one run in three failed.
##
## Done here rather than from the game, because this node is what holds the
## playbacks and it has no guarantee about when its parent is told the process
## is ending. All three hooks are covered because the order in which a quitting
## scene tree delivers them is not something to depend on.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_EXIT_TREE, NOTIFICATION_PREDELETE:
			stop_all()
