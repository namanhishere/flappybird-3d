class_name Difficulty
extends RefCounted

## The difficulty curve, expressed as pure functions of the current score.
##
## Keeping it separate from the spawner means the curve can be asserted
## directly in a test, and means the game gets harder as a single, visible
## rule rather than as side effects scattered across spawn code.

## Vertical size of the gap a pipe must offer at the given score.
## Shrinks linearly from GAP_START down to GAP_MIN over
## SCORE_FOR_MAX_DIFFICULTY points, then holds at the minimum.
static func gap_size(score: int) -> float:
	var t := _progress(score)
	return lerpf(GameConfig.GAP_START, GameConfig.GAP_MIN, t)

## Forward speed of the bird at the given score.
## Rises linearly from FORWARD_SPEED_START to FORWARD_SPEED_MAX, then holds.
static func forward_speed(score: int) -> float:
	var t := _progress(score)
	return lerpf(GameConfig.FORWARD_SPEED_START, GameConfig.FORWARD_SPEED_MAX, t)

## Normalised 0..1 difficulty ramp shared by both curves so they stay in step.
static func _progress(score: int) -> float:
	return clampf(float(score) / float(GameConfig.SCORE_FOR_MAX_DIFFICULTY), 0.0, 1.0)
