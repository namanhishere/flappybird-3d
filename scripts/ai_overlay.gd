class_name AIOverlay
extends CanvasLayer

## The explainability overlay: what the AI is thinking, and the numbers it
## thought it with.
##
## This is the demo's centrepiece, and it is a readout rather than a
## description. Every value on screen is read from the brain that just made
## the decision -- its state, its target, its whole utility table, and its own
## one-line summary -- so the claim on screen cannot drift from the decision
## off screen. The test suite asserts exactly that, which is what stops this
## from being decoration.
##
## It is refreshed by explicit `refresh()` calls and never from `_process`.
## An overlay that re-rendered itself every frame would show a decision the
## brain had not made yet, and it would be untestable.

enum View {COPILOT_FLAP, COPILOT_STEER, HUNTER}

const INK := Color(1.0, 1.0, 1.0)
const DIM := Color(0.78, 0.84, 0.90)
const BEST := Color(1.0, 0.84, 0.35)
const SHADOW := Color(0.05, 0.08, 0.12, 0.9)

var _view: int = View.COPILOT_FLAP
var _state_label: Label
var _summary_label: Label
var _target_label: Label
var _table_label: Label
var _root: Control

## The brain currently on display, handed over by the game on each refresh, so
## the overlay never reaches into the game to find it.
var brain: CoPilotBrain = null

func _ready() -> void:
	layer = 15
	_build()
	visible = false

func _build() -> void:
	_root = Control.new()
	_root.name = "OverlayRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Never eat input: the game reads its own keys through _unhandled_input.
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var panel := ColorRect.new()
	panel.name = "Panel"
	panel.color = SHADOW
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -430.0
	panel.offset_top = 140.0
	panel.offset_right = -12.0
	panel.offset_bottom = 660.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 12.0
	column.offset_right = -12.0
	column.offset_top = 10.0
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)

	_state_label = _make_label("", 26, BEST)
	_summary_label = _make_label("", 18, INK)
	_target_label = _make_label("", 16, DIM)
	_table_label = _make_label("", 12, DIM)
	for label: Label in [_state_label, _summary_label, _target_label, _table_label]:
		column.add_child(label)

func _make_label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12))
	label.add_theme_constant_override("outline_size", 4)
	return label

## Shows or hides the overlay, and returns the new visibility so a caller that
## wants to print it does not have to ask twice.
func toggle() -> bool:
	visible = not visible
	return visible

## Moves to the next brain worth looking at, wrapping. The hunter is skipped
## while there is no drone, so TAB never lands on an empty panel.
func cycle_view(has_hunter: bool = false) -> int:
	var order := [View.COPILOT_FLAP, View.COPILOT_STEER]
	if has_hunter:
		order.append(View.HUNTER)
	_view = order[(order.find(_view) + 1) % order.size()]
	return _view

func current_view() -> int:
	return _view

## Redraws from the brain that just decided. This is the only thing that
## changes the text, and the game calls it once per step rather than a frame
## callback doing it.
func refresh(source: CoPilotBrain) -> void:
	brain = source
	if source == null or not visible:
		return
	_state_label.text = "%s   [%s]" % [
		CoPilotBrain.state_name(source.state), view_name()]
	_summary_label.text = source.describe()
	_target_label.text = "aim x %+.2fm  y %+.2fm     flap in %s" % [
		source.aim.x, source.aim.y,
		"-" if source.flap_in < 0.0 else "%.2fs" % source.flap_in]
	_table_label.text = _utility_table()

## The candidate table, with the chosen candidate marked. This is the whole
## point of the panel: the decision is auditable, not asserted.
func _utility_table() -> String:
	if brain == null or brain.last_utility.is_empty():
		return "no candidates scored yet"
	# The brain's own choice, not a recomputed argmax. Recomputing is how the
	# panel came to disagree with the bird: the brain breaks ties towards the
	# last candidate, this loop broke them towards the first, and on a run where
	# "never flap" and "flap now" scored identically the panel highlighted a row
	# the bird was never going to fly.
	var best := brain.best_index
	# Every candidate is shown. The point of the panel is that the decision is
	# auditable, and a table that silently drops the tail can hide the very row
	# the brain chose -- which a first version did, marking a winner that was
	# not on screen.
	var lines: Array[String] = []
	for i in brain.last_utility.size():
		lines.append("%s %-14s %8.2f" % [
			">" if i == best else " ",
			candidate_name(i, brain.last_candidates.size()),
			brain.last_utility[i]])
	return "candidate           utility\n" + "\n".join(lines)

func candidate_name(index: int, count: int) -> String:
	if brain.axis == MatchConfig.Role.STEER:
		return "steer %+.1f" % brain.last_candidates[index]
	if index >= count - 1:
		return "never flap"
	return "flap in %.2fs" % brain.last_candidates[index]

func view_name() -> String:
	match _view:
		View.COPILOT_FLAP: return "co-pilot: flap"
		View.COPILOT_STEER: return "co-pilot: steer"
		View.HUNTER: return "hunter"
	return "?"

# --- read-only view, so a test can assert the panel is a real readout --------

func displayed_state() -> String:
	return _state_label.text

func displayed_summary() -> String:
	return _summary_label.text

func displayed_target() -> String:
	return _target_label.text

func displayed_table() -> String:
	return _table_label.text

## The candidate the panel is highlighting, recovered from its own text, so a
## test compares what is on screen rather than what the brain happens to hold.
func displayed_best_candidate() -> String:
	for line in _table_label.text.split("\n"):
		if line.begins_with("> "):
			return line.substr(2).strip_edges().split(" ")[0]
	return ""
