extends Node

## Registers the game's input actions at runtime.
##
## Autoloaded so the actions exist before any scene or test touches them.
## Doing this in code rather than in project.godot keeps the bindings readable
## and version-controllable, and lets the headless test runner assert them.
##
## The menu keys deliberately overlap the flight keys: W is both `flap` and
## `menu_up`. That is safe because Game routes input to the menu only while
## the game is in its MENU state, and to the bird only while it is flying. Two
## bindings on one key are a problem only if both are read at once.

const ACTION_FLAP := &"flap"
const ACTION_STEER_LEFT := &"steer_left"
const ACTION_STEER_RIGHT := &"steer_right"
const ACTION_RESTART := &"restart"
const ACTION_MENU_UP := &"menu_up"
const ACTION_MENU_DOWN := &"menu_down"
const ACTION_MENU_CONFIRM := &"menu_confirm"
const ACTION_TOGGLE_OVERLAY := &"toggle_overlay"
const ACTION_CYCLE_AI_VIEW := &"cycle_ai_view"

func _enter_tree() -> void:
	register_actions()

## Idempotent: safe to call again from a test.
static func register_actions() -> void:
	_add_action(ACTION_FLAP, [
		KEY_SPACE, KEY_W, KEY_UP, KEY_ENTER,
	], [MOUSE_BUTTON_LEFT])
	_add_action(ACTION_STEER_LEFT, [KEY_A, KEY_LEFT], [])
	_add_action(ACTION_STEER_RIGHT, [KEY_D, KEY_RIGHT], [])
	_add_action(ACTION_RESTART, [KEY_R], [])
	_add_action(ACTION_MENU_UP, [KEY_W, KEY_UP], [])
	_add_action(ACTION_MENU_DOWN, [KEY_S, KEY_DOWN], [])
	_add_action(ACTION_MENU_CONFIRM, [KEY_SPACE, KEY_ENTER], [])
	_add_action(ACTION_TOGGLE_OVERLAY, [KEY_F1], [])
	_add_action(ACTION_CYCLE_AI_VIEW, [KEY_TAB], [])

## Every action the game defines, so a test can assert the whole set is
## registered rather than spot-checking the one it happens to use.
static func all_actions() -> Array:
	return [
		ACTION_FLAP, ACTION_STEER_LEFT, ACTION_STEER_RIGHT, ACTION_RESTART,
		ACTION_MENU_UP, ACTION_MENU_DOWN, ACTION_MENU_CONFIRM,
		ACTION_TOGGLE_OVERLAY, ACTION_CYCLE_AI_VIEW,
	]

## Only the actions the title menu reads. Kept apart from all_actions() so the
## game's menu routing does not have to walk the flight bindings to find out
## whether a key was a menu key.
const MENU_ACTIONS := [ACTION_MENU_UP, ACTION_MENU_DOWN, ACTION_MENU_CONFIRM]

static func menu_actions() -> Array:
	return MENU_ACTIONS

static func _add_action(action: StringName, keys: Array, buttons: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	# Rebuild the bindings so a second call does not double them up.
	InputMap.action_erase_events(action)
	for keycode in keys:
		var key := InputEventKey.new()
		key.physical_keycode = keycode
		InputMap.action_add_event(action, key)
	for button_index in buttons:
		var click := InputEventMouseButton.new()
		click.button_index = button_index
		InputMap.action_add_event(action, click)
