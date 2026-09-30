extends Node3D
class_name Player

## The player's bird, seen from the inside: this node carries the camera, so
## the player flies the viewpoint forward and the two wings are all that is
## visible of the bird itself.
##
## All vertical physics lives in FlightModel. This node is the presentation
## layer that copies the model onto a transform and draws the wings, which
## keeps the mechanic testable without a scene tree.

var flight := FlightModel.new()
var forward_speed: float = GameConfig.FORWARD_SPEED_START

var _camera: Camera3D
var _wing_left: MeshInstance3D
var _wing_right: MeshInstance3D
var _wing_timer: float = 0.0

func _ready() -> void:
	_build_view()
	reset()

## Builds the first-person rig: camera plus two wings in the lower corners of
## the view so the player can still read their own altitude and flap timing.
func _build_view() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 78.0
	_camera.near = 0.05
	_camera.far = 400.0
	_camera.position = Vector3(0.0, 0.12, 0.35)
	add_child(_camera)

	# Placed low, wide and well forward so the wings read as the bird's own
	# wings in the bottom corners of the view. Any closer and a wing fills the
	# screen as a flat plank instead of reading as part of the bird.
	_wing_left = _build_wing("WingLeft", Vector3(0.60, -0.40, -0.40))
	_wing_right = _build_wing("WingRight", Vector3(-0.60, -0.40, -0.40))

func _build_wing(wing_name: String, at: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.32, 0.05, 0.18)
	var wing := MeshInstance3D.new()
	wing.name = wing_name
	wing.mesh = mesh
	wing.material_override = Materials.wing()
	wing.position = at
	# Mirror the rotation so a single flap angle drives both wings.
	wing.rotation.y = 0.0 if wing_name == "WingLeft" else PI
	add_child(wing)
	return wing

## Places the bird at an exact position, keeping the flight model in sync so
## the next step integrates from the new state rather than snapping back.
## Used by the headless tests to set up collision scenarios, and by any debug
## tooling that needs to place the bird directly.
func teleport(to: Vector3, vertical_velocity: float = 0.0) -> void:
	position = to
	flight.position_y = to.y
	flight.position_x = to.x
	flight.velocity_y = vertical_velocity

## Returns the bird to its spawn state at the given height.
func reset(start_y: float = GameConfig.START_Y) -> void:
	flight.reset(start_y)
	forward_speed = GameConfig.FORWARD_SPEED_START
	position = Vector3(0.0, start_y, 0.0)
	_wing_timer = 0.0
	_apply_wings(0.0)

## One flap. Exposed so the game loop and the tests share a single entry point.
func flap() -> void:
	flight.flap()
	_wing_timer = GameConfig.WING_FLAP_DURATION

## Advances the bird one fixed step. Public so the headless tests can drive
## the game deterministically without depending on the physics loop.
func advance(delta: float) -> void:
	flight.step(delta)
	position.y = flight.position_y
	position.x = _clamp_to_lane(flight.position_x)
	flight.position_x = position.x
	position.z -= forward_speed * delta

## Keeps the bird inside the lane, and stops it grinding along the wall.
##
## The clamp lives here rather than in FlightModel because the lane is a
## property of the world the node inhabits, not of the bird's physics, and
## because a predictor running the model forward has to be able to leave the
## lane and come back. The model is written back so the transform and the
## model can never disagree about where the bird is.
func _clamp_to_lane(x: float) -> float:
	var limit := GameConfig.LANE_HALF_WIDTH
	if x > limit:
		flight.velocity_x = minf(flight.velocity_x, 0.0)
		return limit
	if x < -limit:
		flight.velocity_x = maxf(flight.velocity_x, 0.0)
		return -limit
	return x

## Presentation-only animation, driven by the render loop so that a paused
## simulation still shows the wings settling.
func _process(delta: float) -> void:
	if _wing_timer > 0.0:
		_wing_timer = maxf(_wing_timer - delta, 0.0)
	var ratio := 1.0 - (_wing_timer / GameConfig.WING_FLAP_DURATION)
	_apply_wings(sin(ratio * PI) * -0.95)
	_apply_camera_lean()

## Sweeps the wings up and back down over the flap duration.
func _apply_wings(angle: float) -> void:
	_wing_left.rotation.x = angle
	_wing_right.rotation.x = -angle

## Tips the view slightly with vertical speed: free motion feedback that makes
## falling feel fast without affecting the collision geometry.
func _apply_camera_lean() -> void:
	if _camera == null:
		return
	var lean := clampf(flight.velocity_y * 0.028, -0.42, 0.42)
	_camera.rotation.x = lean
	_camera.rotation.z = clampf(-flight.velocity_y * 0.010, -0.12, 0.12)

## Height of the gap the bird must thread, for HUD and test use.
func is_out_of_bounds() -> bool:
	return flight.is_below_floor() or flight.is_above_ceiling()
