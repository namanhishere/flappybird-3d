extends Node3D
class_name Ground

## The scrolling ground.
##
## A single long slab that follows the bird, plus a line of lighter stripes
## that recycle from behind to in front. The stripes are the main cue that
## tells the player how fast they are moving, which a first-person camera
## otherwise struggles to convey on a featureless plane.

var _slab: MeshInstance3D
var _stripes: Array[MeshInstance3D] = []

func _ready() -> void:
	_build()
	reset()

func _build() -> void:
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(220.0, 1.0, GameConfig.GROUND_SLAB_LENGTH)
	_slab = MeshInstance3D.new()
	_slab.name = "Slab"
	_slab.mesh = slab_mesh
	_slab.material_override = Materials.ground()
	add_child(_slab)

	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(16.0, 0.06, GameConfig.GROUND_STRIPE_LENGTH)
	var stripe_material := Materials.ground_stripe()
	for i in GameConfig.GROUND_STRIPE_COUNT:
		var stripe := MeshInstance3D.new()
		stripe.name = "Stripe%02d" % i
		stripe.mesh = stripe_mesh
		stripe.material_override = stripe_material
		add_child(stripe)
		_stripes.append(stripe)

## Lays the ground out ahead of the bird at the given position.
func reset(player_z: float = 0.0) -> void:
	# Offset by a half slab so the slab is centred on the bird.
	_slab.position = Vector3(0.0, GameConfig.FLOOR_Y - 0.5, player_z - GameConfig.GROUND_SLAB_LENGTH * 0.5)
	for i in _stripes.size():
		_stripes[i].position = Vector3(
			0.0,
			GameConfig.FLOOR_Y + 0.03,
			player_z - i * GameConfig.GROUND_STRIPE_SPACING
		)

## Keeps the ground centred on the bird and recycles stripes from behind to
## in front, so the surface is always covered and always moving.
func advance(player_z: float) -> void:
	_slab.position.z = player_z - GameConfig.GROUND_SLAB_LENGTH * 0.5
	var run_length := GameConfig.GROUND_STRIPE_SPACING * _stripes.size()
	for stripe in _stripes:
		if stripe.position.z - player_z > GameConfig.GROUND_STRIPE_SPACING:
			stripe.position.z -= run_length
