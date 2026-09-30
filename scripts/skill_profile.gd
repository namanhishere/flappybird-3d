class_name SkillProfile
extends RefCounted

## How good an AI brain is, expressed as a set of numbers rather than as a
## second implementation.
##
## Every level drives the same CoPilotBrain and the same HunterBrain. The
## levels differ only in reaction delay, aim noise, flap timing error, how
## early the co-pilot abandons a smooth line, and how eagerly the hunter
## commits. That is what makes a skill level a parameter rather than a fork.
##
## Noise is drawn from an owned, seeded RandomNumberGenerator, so a headless
## run at a given level and seed reproduces exactly -- which is the only
## reason an AI test can assert anything at all.

enum Level {EASY, NORMAL, HARD, UNFAIR}

## Seconds the brain keeps acting on a previous tick's sensors. Non-zero means
## the brain's view of the world is deliberately stale.
var reaction_delay: float = 0.0
## Standard deviation, in metres, of the aim error added to the target.
var aim_noise: float = 0.0
## Standard deviation, in seconds, of the jitter on a scheduled flap.
var flap_timing_error: float = 0.0
## How far below the target, in metres, the co-pilot still believes it has
## time to glide before it gives up and flaps immediately.
var panic_threshold: float = 0.0
## 0..1, how readily the hunter commits to a pass instead of orbiting.
var aggression: float = 0.0

var level: int = Level.NORMAL

var _rng := RandomNumberGenerator.new()

## The per-level numbers, as a pure table indexed by Level.
##
## `aim_noise` is a fraction of the tightest clear band the difficulty curve
## ever produces: GAP_MIN / 2 - PLAYER_RADIUS, about 0.95 m of half-width.
## UNFAIR is three per cent of the band it has to hit and EASY is nearly a
## third, so the ladder spans a factor of ten and a weak co-pilot visibly
## clips the lip in the late game while a strong one does not.
##
## The band is the right yardstick because it is the only thing that decides
## whether an aim error matters: an error of a third of a metre is nothing in
## an opening five-metre gap and fatal in a closing 2.8-metre one. Scaling the
## noise against anything else -- a fixed feel for it, or the opening gap --
## produces levels that are either indistinguishable or unflyable, and the
## benchmark in tests/bench.gd is what caught that.
const PARAMS := [
	{"reaction_delay": 0.22, "aim_noise": 0.20, "flap_timing_error": 0.040, \
		"panic_threshold": 3.20, "aggression": 0.20},
	{"reaction_delay": 0.11, "aim_noise": 0.070, "flap_timing_error": 0.016, \
		"panic_threshold": 2.00, "aggression": 0.45},
	{"reaction_delay": 0.04, "aim_noise": 0.050, "flap_timing_error": 0.010, \
		"panic_threshold": 1.20, "aggression": 0.75},
	{"reaction_delay": 0.00, "aim_noise": 0.028, "flap_timing_error": 0.000, \
		"panic_threshold": 0.60, "aggression": 1.00},
]

func _init() -> void:
	configure(Level.NORMAL, 0)

## Loads a level and reseeds the noise source. Called on spawn, on restart and
## by every test that wants a reproducible run.
func configure(level_id: int, seed_value: int = 0) -> void:
	level = clampi(level_id, 0, PARAMS.size() - 1)
	var row: Dictionary = PARAMS[level]
	reaction_delay = float(row["reaction_delay"])
	aim_noise = float(row["aim_noise"])
	flap_timing_error = float(row["flap_timing_error"])
	panic_threshold = float(row["panic_threshold"])
	aggression = float(row["aggression"])
	_rng.seed = seed_value

## Gaussian aim error in metres. Zero at a zero-noise level, so EASY is not
## merely unlucky -- it is genuinely worse at aiming.
func aim_error() -> float:
	return 0.0 if aim_noise <= 0.0 else _rng.randfn(0.0, aim_noise)

## Gaussian jitter on a scheduled flap time, in seconds.
func flap_timing_jitter() -> float:
	return 0.0 if flap_timing_error <= 0.0 else _rng.randfn(0.0, flap_timing_error)

## A uniform draw from this profile's own generator, for the hunter's
## approach jitter. Same source, so one seed reproduces a whole match.
func randf() -> float:
	return _rng.randf()

static func level_name(level_id: int) -> String:
	match clampi(level_id, 0, PARAMS.size() - 1):
		Level.EASY: return "EASY"
		Level.NORMAL: return "NORMAL"
		Level.HARD: return "HARD"
		_: return "UNFAIR"

## Parses the --skill flag. An unrecognised name falls back to NORMAL rather
## than failing a launch over a typo.
static func level_from_name(name_value: String) -> int:
	match name_value.to_lower():
		"easy": return Level.EASY
		"hard": return Level.HARD
		"unfair": return Level.UNFAIR
		_: return Level.NORMAL
