class_name ControlMap
extends RefCounted

## Which source drives each control axis, as one pure table.
##
## Every mode in the game is a row here. A human keypress, an AI brain and a
## remote peer all produce the same BirdIntent, so the mode system never leaks
## into the flight model: the only thing that differs between "one player" and
## "two players sharing one bird" is which source is allowed to fill each axis
## in. Nothing else in the codebase has to know what mode the game is in.
##
## Each axis has exactly one source. There is no mode in which both players can
## reach the same control, which is the whole point of the design.

enum Source {LOCAL, AI, REMOTE}

## True when the mode gives this axis to anybody at all. SOLO is a single-axis
## game: there is no steer axis, so nothing ever reads one.
static func has_axis(mode: int, axis: int) -> bool:
	if axis == MatchConfig.Role.STEER:
		return mode != MatchConfig.Mode.SOLO
	return true

## The source that fills `axis` in `mode`.
static func source_for(mode: int, axis: int) -> Source:
	match mode:
		MatchConfig.Mode.SOLO:
			return Source.LOCAL
		MatchConfig.Mode.LOCAL_2P:
			return Source.LOCAL
		MatchConfig.Mode.AI_HUMAN_FLAP:
			# The human flaps, the AI steers.
			return Source.AI if axis == MatchConfig.Role.STEER else Source.LOCAL
		MatchConfig.Mode.AI_HUMAN_STEER:
			# The AI flaps, the human steers.
			return Source.AI if axis == MatchConfig.Role.FLAP else Source.LOCAL
		MatchConfig.Mode.HOST:
			# The host player flaps; the steer comes off the wire.
			return Source.REMOTE if axis == MatchConfig.Role.STEER else Source.LOCAL
		MatchConfig.Mode.CLIENT:
			# The host's flaps arrive over the wire; this peer steers.
			return Source.REMOTE if axis == MatchConfig.Role.FLAP else Source.LOCAL
	return Source.LOCAL

## True when this source is a human at a keyboard on this process.
static func is_local(source: int) -> bool:
	return source == Source.LOCAL

static func source_name(source: int) -> String:
	match source:
		Source.LOCAL: return "LOCAL"
		Source.AI: return "AI"
		Source.REMOTE: return "REMOTE"
	return "?"
