extends Node3D
class_name Obstacle

## One pipe pair: a bottom pipe rising from the floor and a top pipe hanging
## from the ceiling, leaving a gap the bird must fly through.
##
## Collision is an explicit geometric test in code rather than a physics-server
## Area3D. For a game with one moving circle against a handful of flat-ended
## cylinders this is exact, costs nothing, and -- unlike the physics server --
## gives the headless tests a collision answer without having to step the
## physics world.
##
## The test below is circle-versus-rectangle because that is the true
## cross-section of a cylinder cut perpendicular to its axis. Treating the
## ends as spherical caps would make each pipe 1.3 m fatter than it is drawn
## and the bird would die on gaps that look wide enough to clear.

## Index in the generated sequence, stable for the life of the pipe.
var index: int = -1
var gap_center_y: float = GameConfig.GAP_CENTER_DEFAULT
var gap_size: float = GameConfig.GAP_START
## Sideways centre of the gap. The pipe pair sits at this x, so collision is
## resolved against the pipe's own centre rather than the flight axis.
var gap_center_x: float = 0.0
## Set once the bird has flown past this pipe, so it scores exactly once.
var scored: bool = false

var _lower_span: Vector2
var _upper_span: Vector2

func _ready() -> void:
	_compute_spans()
	_build_meshes()

## Applies a description produced by ObstaclePlan. Must be called before the
## node enters the tree, because _ready sizes the meshes from these values.
func configure(description: Dictionary) -> void:
	index = int(description.get("index", -1))
	gap_center_y = float(description.get("gap_center_y", GameConfig.GAP_CENTER_DEFAULT))
	gap_center_x = float(description.get("gap_center_x", 0.0))
	gap_size = float(description.get("gap_size", GameConfig.GAP_START))
	scored = false

## The open vertical band the bird has to pass through.
func gap_bottom_y() -> float:
	return gap_center_y - gap_size * 0.5

func gap_top_y() -> float:
	return gap_center_y + gap_size * 0.5

## The band that is actually safe for the bird's centre, once the pipe walls
## and the bird's own radius are taken out of the drawn gap.
func clearance_bottom_y() -> float:
	return gap_bottom_y() + GameConfig.PLAYER_RADIUS

func clearance_top_y() -> float:
	return gap_top_y() - GameConfig.PLAYER_RADIUS

func _compute_spans() -> void:
	# Each span is the y range the solid pipe occupies, in world space.
	_lower_span = Vector2(GameConfig.FLOOR_Y, gap_bottom_y())
	_upper_span = Vector2(gap_top_y(), GameConfig.CEILING_Y)

func _build_meshes() -> void:
	_add_pipe("LowerPipe", _lower_span)
	_add_pipe("UpperPipe", _upper_span)

## Builds one pipe as a box.
##
## A box rather than a cylinder, because the collision test above is a
## circle-versus-rectangle: it treats the pipe as a slab of half-width
## PIPE_RADIUS and depth PIPE_DEPTH. Drawing a box means what the player sees
## is exactly what they collide with, and unlike a zero-thickness cylinder a
## box has real depth, so the pipe reads as a solid slab as it goes past.
func _add_pipe(node_name: String, span: Vector2) -> void:
	var height := span.y - span.x
	if height <= 0.0:
		return
	var body := BoxMesh.new()
	body.size = Vector3(GameConfig.PIPE_RADIUS * 2.0, height, GameConfig.PIPE_DEPTH)
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = body
	mesh.material_override = Materials.pipe()
	mesh.position = Vector3(0.0, span.x + height * 0.5, 0.0)
	add_child(mesh)
	# The wider lip at the free end, on both pipes: the detail that makes an
	# obstacle read as a flappy pipe rather than a plain grey box.
	_add_cap("%sCap" % node_name, span, 1.0 if node_name == "LowerPipe" else -1.0)

## `direction` is +1 for the pipe rising from the floor and -1 for the pipe
## hanging from the ceiling, so the lip always sits on the solid side of the
## gap and never appears to intrude into the space the bird flies through.
func _add_cap(node_name: String, span: Vector2, direction: float) -> void:
	var cap_height := GameConfig.PIPE_DEPTH * 0.8
	var cap := BoxMesh.new()
	cap.size = Vector3(
		GameConfig.PIPE_RADIUS * 2.0 * 1.35,
		cap_height,
		GameConfig.PIPE_DEPTH * 1.5)
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = cap
	mesh.material_override = Materials.pipe_cap()
	var mouth := span.y if direction > 0.0 else span.x
	mesh.position = Vector3(0.0, mouth - direction * cap_height * 0.5, 0.0)
	add_child(mesh)

## True when a sphere of `radius` at `point` would be inside either pipe.
## Tests call this directly, so collision is verifiable without a physics step.
func overlaps(point: Vector3, radius: float) -> bool:
	# Depth check first: the bird must actually be level with the pipe.
	if absf(point.z - position.z) > GameConfig.PIPE_DEPTH * 0.5 + radius:
		return false
	# Relative to the pipe's own centre: the pipe is no longer on the flight
	# axis, so probing in world x would measure the offset twice.
	var probe := Vector2(point.x - position.x, point.y)
	return _circle_hits_rect(probe, radius, _lower_span) \
		or _circle_hits_rect(probe, radius, _upper_span)

## Exact circle-versus-rectangle overlap against one pipe's cross-section,
## which spans PIPE_RADIUS either side of the pipe's own centre over the given
## y run. The caller passes a probe already relative to that centre.
static func _circle_hits_rect(probe: Vector2, radius: float, span: Vector2) -> bool:
	var nearest := Vector2(
		clampf(probe.x, -GameConfig.PIPE_RADIUS, GameConfig.PIPE_RADIUS),
		clampf(probe.y, span.x, span.y))
	return probe.distance_to(nearest) <= radius

## True once the bird's centre has travelled beyond the pipe's mid-plane.
func is_passed_by(player_z: float) -> bool:
	return position.z > player_z

## Draws or stops drawing the pipe's meshes.
##
## A pipe the bird has flown through has to stop being drawn, even though it
## is still alive for another twenty metres of culling. The camera sits just
## behind the bird's own centre, inside a slab that is 1.5 metres deep, so
## while the bird is level with a pipe the camera is inside it too -- and the
## view fills with the inside of a green box. The bird is *past* it and cannot
## collide with it, so the collision is right and only the drawing is wrong.
func set_drawn(should_draw: bool) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = should_draw
