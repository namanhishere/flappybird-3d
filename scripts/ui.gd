extends CanvasLayer
class_name GameUI

## All on-screen text: the title card, the live score, the lives, the roles,
## and the game-over card.
##
## Laid out with containers rather than hand-computed offsets, so the blocks
## space themselves out and cannot overlap when the text changes length.
##
## The role line is the one piece of new information here that earns its place:
## a two-player match looks identical to a one-player match from the outside,
## and the single most useful thing a viewer can be told is which of the two
## people currently has the flap and which has the steer.

const INK := Color(1.0, 1.0, 1.0)
const SHADOW := Color(0.05, 0.08, 0.12)
const SCRIM := Color(0.05, 0.08, 0.12, 0.45)
const WARN := Color(1.0, 0.45, 0.35)

var _score_label: Label
var _title_label: Label
var _hint_label: Label
var _best_label: Label
var _mode_label: Label
var _lives_label: Label
var _warning_label: Label
var _game_over_card: Control
var _game_over_title: Label
var _game_over_score: Label
var _game_over_best: Label
var _game_over_hint: Label

func _ready() -> void:
	layer = 10
	_build()

func _build() -> void:
	var root := Control.new()
	root.name = "UIRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Never eat input: the game reads flap presses through _unhandled_input.
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_score_label = _make_label("0", 68)
	var score_slot := Control.new()
	score_slot.name = "ScoreSlot"
	score_slot.set_anchors_preset(Control.PRESET_TOP_WIDE)
	score_slot.offset_top = 12.0
	score_slot.offset_bottom = 96.0
	score_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_slot.add_child(_score_label)
	root.add_child(score_slot)

	# A second band under the score: the roles on the left, the lives on the
	# right. Both are read at a glance and neither is worth a whole card.
	var status := HBoxContainer.new()
	status.name = "StatusSlot"
	status.set_anchors_preset(Control.PRESET_TOP_WIDE)
	status.offset_top = 96.0
	status.offset_bottom = 132.0
	status.add_theme_constant_override("separation", 16)
	status.alignment = BoxContainer.ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status)

	_mode_label = _make_label("", 20)
	_lives_label = _make_label("", 20)
	_warning_label = _make_label("", 20)
	_warning_label.add_theme_color_override("font_color", WARN)
	for label in [_mode_label, _lives_label, _warning_label]:
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status.add_child(label)

	# set_anchors_and_offsets_preset, not set_anchors_preset: the latter keeps
	# the current rect and would leave the score pinned to the top left.
	_score_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title_card := _build_title_card()
	root.add_child(title_card)

	_game_over_card = _build_game_over_card()
	root.add_child(_game_over_card)

func _build_title_card() -> Control:
	var column := VBoxContainer.new()
	column.name = "TitleCard"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_title_label = _make_label("FLAPPY 3D", 72)
	_hint_label = _make_label("Press SPACE, click, or W to flap", 26)
	_best_label = _make_label("", 22)
	column.add_child(_title_label)
	column.add_child(_hint_label)
	column.add_child(_best_label)
	return column

func _build_game_over_card() -> Control:
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var column := VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_game_over_title = _make_label("GAME OVER", 64)
	_game_over_score = _make_label("", 34)
	_game_over_best = _make_label("", 24)
	_game_over_hint = _make_label("Press SPACE, click, or R to fly again", 24)
	for label in [_game_over_title, _game_over_score, _game_over_best, _game_over_hint]:
		column.add_child(label)

	center.add_child(column)
	scrim.add_child(center)
	return scrim

func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_outline_color", SHADOW)
	# A fixed, modest outline: scaling it with the font size swallows the
	# counter of a large glyph like "0" and turns it into a dark blob.
	label.add_theme_constant_override("outline_size", 6)
	return label

## Single entry point the game calls whenever score, lives, state or roles
## change, so the HUD can never drift out of sync with the simulation.
func refresh(state: int, score: int, best: int, lives: int,
		mode_line: String, reason: String = "", warning: String = "") -> void:
	var playing := state == Game.State.PLAYING
	var over := state == Game.State.GAME_OVER
	var on_title := state == Game.State.READY

	_score_label.get_parent().visible = playing or over
	_score_label.text = str(score)

	var status := _mode_label.get_parent()
	status.visible = playing or over
	_mode_label.text = mode_line
	_lives_label.text = "LIVES %d" % lives
	_warning_label.text = warning

	var title_card := _title_label.get_parent()
	title_card.visible = on_title
	_best_label.text = "Best: %d" % best if best > 0 else ""

	_game_over_card.visible = over
	if over:
		_game_over_title.text = reason if reason != "" else "GAME OVER"
		_game_over_score.text = "Score: %d" % score
		_game_over_best.text = "Best: %d" % maxi(best, score)

# --- read-only view of the HUD ----------------------------------------------
#
# Exists purely so the test suite can assert that what the player sees matches
# what the simulation holds. A stale label is invisible to every other test,
# because every other test reads the model directly.

func displayed_score() -> String:
	return _score_label.text

func displayed_lives() -> String:
	return _lives_label.text

func displayed_mode() -> String:
	return _mode_label.text

func displayed_warning() -> String:
	return _warning_label.text

func score_visible() -> bool:
	return _score_label.get_parent().visible

func status_visible() -> bool:
	return _mode_label.get_parent().visible

func title_visible() -> bool:
	return _title_label.get_parent().visible

func game_over_visible() -> bool:
	return _game_over_card.visible
