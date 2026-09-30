extends Node3D
class_name TargetMarker

## A crosshair on the gap the co-pilot is aiming at, and a ribbon along the
## path it currently believes it will fly.
##
## Like the overlay, this is rebuilt only from an explicit `refresh()` call and
## never on its own. The ribbon is drawn from the very trajectory the brain
## scored, so the line in the air and the number on the panel are the same
## decision rather than two drawings of it.

## Half the length of each arm of the crosshair, in metres.
const ARM := 1.1
## How thick the arms are.
const THICK := 0.12
## Half the width of the ribbon, in metres.
const RIBBON_HALF := 0.07
const RIBBON_COLOR := Color(1.0, 0.84, 0.35, 0.85)

var _crosshair: Node3D
var _ribbon: MeshInstance3D
var _ribbon_mesh: ImmediateMesh

func _ready() -> void:
	_build()

func _build() -> void:
	_crosshair = Node3D.new()
	_crosshair.name = "Crosshair"
	# Two thin boxes, not one: a single box is a dash, and a dash sitting on the
	# gap reads as a fragment of scenery rather than as a mark.
	var horizontal := MeshInstance3D.new()
	horizontal.name = "Horizontal"
	horizontal.mesh = _arm_mesh(Vector3(ARM * 2.0, THICK, THICK))
	var vertical := MeshInstance3D.new()
	vertical.name = "Vertical"
	vertical.mesh = _arm_mesh(Vector3(THICK, ARM * 2.0, THICK))
	for arm: MeshInstance3D in [horizontal, vertical]:
		arm.material_override = Materials.target()
		_crosshair.add_child(arm)
	add_child(_crosshair)

	_ribbon_mesh = ImmediateMesh.new()
	_ribbon = MeshInstance3D.new()
	_ribbon.name = "Ribbon"
	_ribbon.mesh = _ribbon_mesh
	_ribbon.material_override = Materials.predicted_path()
	add_child(_ribbon)
	# The surface is left unbuilt rather than begun-and-ended empty: Godot
	# errors on closing a surface that has no vertices, and there is nothing to
	# draw until the first prediction anyway.

## Points the crosshair at a point in the bird's plane and redraws the ribbon
## along `path`, which is a list of (x, y) pairs at the bird's current depth.
func refresh(aim: Vector2, bird_z: float, path: Array[Vector2], visible_now: bool) -> void:
	_crosshair.visible = visible_now
	_ribbon.visible = visible_now
	if not visible_now:
		return
	_crosshair.position = Vector3(aim.x, aim.y, bird_z)
	_draw_ribbon(path, bird_z)

## The ribbon, as a triangle strip.
##
## Godot's line primitives are a pixel wide on most drivers, which from the
## first-person view this game is played from is not a ribbon at all. So each
## sample becomes two vertices offset either side of the path's direction,
## which reads as a ribbon from anywhere along it.
func _draw_ribbon(path: Array[Vector2], bird_z: float) -> void:
	_ribbon_mesh.clear_surfaces()
	if path.size() < 2:
		return
	_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	_ribbon_mesh.surface_set_color(RIBBON_COLOR)
	for i in path.size():
		var point := path[i]
		var before := path[maxi(i - 1, 0)]
		var after := path[mini(i + 1, path.size() - 1)]
		var tangent := after - before
		if tangent.length_squared() < 0.000001:
			tangent = Vector2.UP
		tangent = tangent.normalized()
		var side := Vector2(-tangent.y, tangent.x) * RIBBON_HALF
		_ribbon_mesh.surface_set_color(RIBBON_COLOR)
		_ribbon_mesh.surface_add_vertex(
			Vector3(point.x - side.x, point.y - side.y, bird_z))
		_ribbon_mesh.surface_set_color(RIBBON_COLOR)
		_ribbon_mesh.surface_add_vertex(
			Vector3(point.x + side.x, point.y + side.y, bird_z))
	_ribbon_mesh.surface_end()

## One arm of the crosshair.
func _arm_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

# --- read-only view, so a test can assert the marker tracks the brain -------

func crosshair_position() -> Vector3:
	return _crosshair.position

func marker_visible() -> bool:
	return _crosshair.visible

## Vertices in the ribbon's surface. Two per sample, so a predicted path of
## N points is 2N.
##
## Read off the arrays rather than through a surface query: ImmediateMesh has
## no per-surface length accessor, and `get_surface_count()` alone cannot say
## how much was drawn.
func ribbon_vertex_count() -> int:
	if _ribbon_mesh.get_surface_count() == 0:
		return 0
	var arrays := _ribbon_mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return 0
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
