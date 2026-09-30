extends Control
class_name ModeMenu

## The title menu: pick a mode and a skill, confirm, fly.
##
## Built in code with containers, matching the convention in ui.gd, because a
## hand-written .tscn full of font-size and outline overrides is a large
## unreadable blob whose failure mode is a confusing parse error.
##
## The menu owns no game state. It emits the choice and lets Game apply it, so
## there is exactly one place that turns a mode into a running game.

signal mode_confirmed(mode: int, skill: int)

## The modes on offer. The two online ones are listed because the network
## layer now exists to serve them; they are kept last so the keyboard modes --
## which need no second process and no second terminal -- are the ones a
## single click away.
const MODES := [
	MatchConfig.Mode.SOLO,
	MatchConfig.Mode.LOCAL_2P,
	MatchConfig.Mode.AI_HUMAN_FLAP,
	MatchConfig.Mode.AI_HUMAN_STEER,
	MatchConfig.Mode.HOST,
	MatchConfig.Mode.CLIENT,
]

const SKILLS := [
	SkillProfile.Level.EASY,
	SkillProfile.Level.NORMAL,
	SkillProfile.Level.HARD,
	SkillProfile.Level.UNFAIR,
]

## One line of explanation per mode, indexed with MODES.
const HINTS := [
	"One player. You flap. The pipes still move sideways.",
	"Two players, one bird. P1 flaps, P2 steers. One keyboard.",
	"You flap, the AI steers. F1 shows the decision it made.",
	"The AI flaps, you steer. F1 shows the decision it made.",
	"Host an online match on this machine. The other player steers.",
	"Join a host on this machine. The other player flaps.",
]

enum Region {MODE, SKILL}

## Two lists, one highlighted row, and a cursor that steps from the bottom of
## the modes to the top of the skills and back.
##
## A single cursor over a flattened list was the first attempt and it was
## worse: with two keys and no region marker, "down from the last mode" and
## "up from the first skill" became the same motion from the player's side and
## opposite from the code's, and the wrap points landed somewhere neither the
## player nor the test could predict. Naming the two regions costs one enum and
## makes the whole menu something you can reason about in one reading.
var _region: int = Region.MODE
var _mode_index: int = 1
var _skill_index: int = 1

var _mode_label: Label
var _hint_label: Label
var _skill_label: Label
var _footer: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func _build() -> void:
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(0.05, 0.08, 0.12, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.add_child(center)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(column)

	var title := _make_label("FLAPPY 3D", 64)
	_mode_label = _make_label("", 32)
	_hint_label = _make_label("", 20)
	_skill_label = _make_label("", 24)
	_footer = _make_label(
		"UP / DOWN to choose, SPACE to start, ESC to quit", 18)
	for label in [title, _mode_label, _hint_label, _skill_label, _footer]:
		column.add_child(label)
	_refresh()

## Handles one action press. Returns true when the menu consumed it, so Game
## knows not to read the same key as a flap.
func handle_action(action: StringName) -> bool:
	match action:
		InputActions.ACTION_MENU_UP:
			_move(-1)
		InputActions.ACTION_MENU_DOWN:
			_move(1)
		InputActions.ACTION_MENU_CONFIRM:
			mode_confirmed.emit(MODES[_mode_index], SKILLS[_skill_index])
		_:
			return false
	return true

func _move(direction: int) -> void:
	if _region == Region.MODE:
		var next := _mode_index + direction
		if next < 0:
			next = MODES.size() - 1
		elif next >= MODES.size():
			# Down off the end of the modes reaches the skills.
			_region = Region.SKILL
			_skill_index = 0
		else:
			_mode_index = next
	else:
		var next_skill := _skill_index + direction
		if next_skill < 0:
			# Up out of the skills returns to the last mode.
			_region = Region.MODE
			_mode_index = MODES.size() - 1
		else:
			_skill_index = clampi(next_skill, 0, SKILLS.size() - 1)
	# One exit, so no branch above can forget to redraw. A cursor that moves
	# without refreshing leaves the panel describing a row that is no longer
	# highlighted, and everything reading the panel -- a test or a player --
	# is then looking at a fiction.
	_refresh()

func _refresh() -> void:
	var mode_row := _region == Region.MODE
	var skill_row := _region == Region.SKILL
	_mode_label.text = "MODE   %s %s" % [
		">" if mode_row else " ", MatchConfig.mode_name(MODES[_mode_index])]
	_skill_label.text = "SKILL  %s %s" % [
		">" if skill_row else " ", SkillProfile.level_name(SKILLS[_skill_index])]
	_hint_label.text = HINTS[_mode_index]

func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.12))
	label.add_theme_constant_override("outline_size", 6)
	return label

# --- read-only view, so a test can assert the menu says what it means --------

func selected_mode() -> int:
	return MODES[_mode_index]

func selected_skill() -> int:
	return SKILLS[_skill_index]

func displayed_mode() -> String:
	return _mode_label.text

func displayed_skill() -> String:
	return _skill_label.text

func displayed_hint() -> String:
	return _hint_label.text
