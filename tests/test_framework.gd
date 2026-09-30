class_name TestFramework
extends RefCounted

## A minimal assertion recorder for the headless test runner.
##
## Deliberately dependency-free: the project's automated validation must work
## from a clean clone with nothing but the pinned Godot binary. This collects
## failures per test and lets the runner print one PASS/FAIL line each.
##
## Every test must call complete() when it reaches its end. A GDScript runtime
## error aborts the function without raising anything catchable, so a missing
## complete() is how a half-executed test gets reported as a failure instead
## of silently passing.

var _current: String = ""
var _completed: bool = false
var _failures: Array[String] = []
var _results: Array[Dictionary] = []

func begin(test_name: String) -> void:
	_current = test_name
	_completed = false
	_failures.clear()

## Marks the test as having run to completion.
func complete() -> void:
	_completed = true

## Records the outcome of the test that is currently running.
func finish() -> void:
	_results.append({
		"name": _current,
		"passed": _failures.is_empty() and _completed,
		"failures": _failures.duplicate(),
		"incomplete": not _completed,
	})

func results() -> Array[Dictionary]:
	return _results

func passed_count() -> int:
	var total := 0
	for result in _results:
		if result["passed"]:
			total += 1
	return total

func failed_count() -> int:
	return _results.size() - passed_count()

func fail(message: String) -> void:
	_failures.append(message)

# --- assertions -------------------------------------------------------------

func expect_true(condition: bool, message: String) -> void:
	if not condition:
		fail(message)

func expect_false(condition: bool, message: String) -> void:
	if condition:
		fail(message)

func expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		fail("%s (expected %s, got %s)" % [message, str(expected), str(actual)])

func expect_ne(actual: Variant, unexpected: Variant, message: String) -> void:
	if actual == unexpected:
		fail("%s (should not be %s)" % [message, str(unexpected)])

func expect_gt(actual: float, bound: float, message: String) -> void:
	if not actual > bound:
		fail("%s (expected > %s, got %s)" % [message, str(bound), str(actual)])

func expect_ge(actual: float, bound: float, message: String) -> void:
	if not actual >= bound:
		fail("%s (expected >= %s, got %s)" % [message, str(bound), str(actual)])

func expect_lt(actual: float, bound: float, message: String) -> void:
	if not actual < bound:
		fail("%s (expected < %s, got %s)" % [message, str(bound), str(actual)])

func expect_le(actual: float, bound: float, message: String) -> void:
	if not actual <= bound:
		fail("%s (expected <= %s, got %s)" % [message, str(bound), str(actual)])

func expect_almost_eq(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		fail("%s (expected %s +/- %s, got %s)" % [message, str(expected), str(tolerance), str(actual)])

func expect_in_range(value: float, lowest: float, highest: float, message: String) -> void:
	if value < lowest or value > highest:
		fail("%s (expected %s..%s, got %s)" % [message, str(lowest), str(highest), str(value)])

## Per-component-tolerant vector comparison, for the pairs of positions and
## velocities the flight model works in. A pair is the natural way to state
## "the bird arrived roughly there"; two separate scalar assertions would let
## a test pass while the thing it was describing did not.
func expect_vec_almost_eq(actual: Vector2, expected: Vector2, tolerance: float, message: String) -> void:
	if actual.distance_to(expected) > tolerance:
		fail("%s (expected %s +/- %s, got %s)" % [message, str(expected), str(tolerance), str(actual)])

## Exact collection size, so a test can state "five candidate flap schedules"
## as an expectation rather than as an index that merely happens to be in
## range. A shrinking utility table is a real failure that a bounds check
## would not catch.
func expect_len(actual: int, expected: int, message: String) -> void:
	if actual != expected:
		fail("%s (expected %d items, got %d)" % [message, expected, actual])
