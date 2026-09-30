class_name MatchConfig
extends RefCounted

## Everything a peer needs to know about the match it is about to play, in one
## value object parsed from the command line or built by the title menu.
##
## Two peers of an online match are handed the same seed and the same mode and
## therefore build a byte-identical course from it. That is why no pipe is ever
## sent across the network: the seed is the whole level.

enum Mode {SOLO, LOCAL_2P, AI_HUMAN_FLAP, AI_HUMAN_STEER, HOST, CLIENT}

## Which control axis a peer owns. There is exactly one of these per player,
## and a peer that sends anything for the axis it does not own is ignored, so
## the two players can never fight over the same control.
enum Role {FLAP, STEER}

var mode: int = Mode.SOLO
## The axis this peer drives from its own keyboard.
var local_role: int = Role.FLAP
## The axis the other peer drives. On a host that is the client's steer.
var remote_role: int = Role.STEER
## One integer. Every peer builds an identical course from it.
var seed_value: int = 0
var port: int = Protocol.DEFAULT_PORT
var address: String = Protocol.LOOPBACK_ADDRESS
var skill: int = SkillProfile.Level.NORMAL
## True when the match has a second process on the other end.
var networked: bool = false

## True when this mode is one of the two online ones.
static func is_networked(mode_id: int) -> bool:
	return mode_id == Mode.HOST or mode_id == Mode.CLIENT

## The axis the local player drives in a given mode. The co-op modes are named
## after whoever is NOT holding the keyboard, so this is the inverse of the
## mode name in every case except the two local modes, where it is the flap.
static func local_role_for(mode_id: int) -> int:
	match mode_id:
		Mode.AI_HUMAN_STEER, Mode.CLIENT:
			return Role.STEER
		_:
			return Role.FLAP

## The other axis, for the peer on the other end.
static func other_role(role_id: int) -> int:
	return Role.STEER if role_id == Role.FLAP else Role.FLAP

## Applies a mode and the roles that follow from it.
func set_mode(mode_id: int) -> void:
	mode = mode_id
	local_role = local_role_for(mode_id)
	remote_role = other_role(local_role)
	networked = is_networked(mode_id)

static func mode_name(mode_id: int) -> String:
	match mode_id:
		Mode.SOLO: return "SOLO"
		Mode.LOCAL_2P: return "LOCAL 2P"
		Mode.AI_HUMAN_FLAP: return "AI STEERS"
		Mode.AI_HUMAN_STEER: return "AI FLAPS"
		Mode.HOST: return "HOST (you flap)"
		Mode.CLIENT: return "CLIENT (you steer)"
	return "?"

static func role_name(role_id: int) -> String:
	return Protocol.role_name(role_id)

## Parses the arguments after the engine's `--` separator.
##
## Accepts the same flags the Makefile's demo targets pass, so a run started
## from a terminal and a run started from the title menu reach the identical
## configuration by two routes:
##
##     -- --mode=local2p
##     -- --mode=ai --human=steer --skill=hard
##     -- --mode=host --port=27015
##     -- --mode=client --address=127.0.0.1
static func from_args(args: PackedStringArray) -> MatchConfig:
	var config := MatchConfig.new()
	# `--human` names the axis the human owns, and defaults to the flap axis.
	var human_axis := Role.FLAP
	var mode_given := false
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var key := body.get_slice("=", 0)
		var value := body.get_slice("=", 1) if body.contains("=") else ""
		match key:
			"mode":
				mode_given = true
				_apply_mode(config, value, human_axis)
			"human":
				human_axis = Role.STEER if value == "steer" else Role.FLAP
				if mode_given:
					# A later --human overrides an earlier --mode, so the
					# co-op direction always follows the last flag on the line.
					config.set_mode(_co_op_mode(human_axis))
			"skill":
				config.skill = SkillProfile.level_from_name(value)
			"port":
				config.port = int(value)
			"address":
				config.address = value
			"seed":
				config.seed_value = int(value)
	return config

## The co-op mode in which the human holds `axis` and the AI holds the other.
static func _co_op_mode(axis: int) -> int:
	return Mode.AI_HUMAN_STEER if axis == Role.STEER else Mode.AI_HUMAN_FLAP

static func _apply_mode(config: MatchConfig, name_value: String, human_axis: int) -> void:
	match name_value.to_lower():
		"local2p", "local_2p", "coop":
			config.set_mode(Mode.LOCAL_2P)
		"ai":
			config.set_mode(_co_op_mode(human_axis))
		"host":
			config.set_mode(Mode.HOST)
		"client":
			config.set_mode(Mode.CLIENT)
		_:
			config.set_mode(Mode.SOLO)
