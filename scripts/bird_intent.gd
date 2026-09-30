class_name BirdIntent
extends RefCounted

## The single control message every source in the game produces.
##
## A human keypress, an AI brain and a remote peer all end up as one of these.
## There is exactly one place in the codebase that mutates the bird and it
## takes a BirdIntent, which is what makes all six modes testable headlessly:
## no keyboard, no window, and for the two online modes no sockets either.
##
## Both axes travel in one object, but they stay separate fields on purpose.
## Merging them into a single "control" would make it impossible to tell which
## player asked for what, which is the whole subject of this game.

## A flap was requested this tick. Edge-triggered: see consume_flap().
var flap: bool = false
## Steer demand in -1..1. Stored unclamped, because clamping is the
## Authority's job -- a peer that sends 9.0 must be visibly clamped, not
## silently corrected before it was ever validated.
var steer: float = 0.0

func request_flap() -> void:
	flap = true

func set_steer(value: float) -> void:
	steer = value

## True exactly once per flap request, and clears the request as it reads it.
##
## This is what makes an intent edge-triggered. Holding a key down cannot
## produce a stream of impulses, and a packet that arrives twice cannot
## replay an impulse the bird already spent.
func consume_flap() -> bool:
	if not flap:
		return false
	flap = false
	return true

func clear() -> void:
	flap = false
	steer = 0.0

## A detached copy. The client-side predictor runs the flight model forward
## against a held intent, so it must not be able to mutate the live one.
func copy() -> BirdIntent:
	var clone := BirdIntent.new()
	clone.flap = flap
	clone.steer = steer
	return clone
