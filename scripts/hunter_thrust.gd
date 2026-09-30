class_name HunterThrust
extends RefCounted

## One hunter decision: where to push, and whether this step is the pass that
## actually tries to catch the bird.
##
## Its own file because GDScript allows one global class per script, and
## because it is a genuinely separate thing from the brain: a test can build a
## thrust and assert on it without constructing a brain at all.

## Acceleration to apply this step, in m/s^2.
var thrust := Vector3.ZERO
## True when the drone is committing to a pass through the bird rather than
## holding station. The game colours the HUD from it, so a player can see the
## moment before the hit rather than only finding out afterwards.
var dive: bool = false

static func make(acceleration: Vector3, is_dive: bool) -> HunterThrust:
	var result := HunterThrust.new()
	result.thrust = acceleration
	result.dive = is_dive
	return result
