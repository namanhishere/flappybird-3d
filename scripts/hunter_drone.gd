extends Node3D
class_name HunterDrone

## The hunter drone: the node that owns the model, the brain and the mesh, and
## is the only thing in the project that writes a force into the bird.
##
## The wind matters more than the collision. A touch costs a life, but the wake
## is what the game is actually about: the flapper is fighting a vertical
## shove and the steerer a lateral drift, on different clocks, and neither can
## fix the other's axis. Contact is the punctuation; the wake is the sentence.

var model := HunterModel.new()
var brain := HunterBrain.new()

## Seconds since the drone last touched the bird, which the brain uses to stay
## out of the way afterwards and the game uses to enforce invulnerability.
var since_contact: float = 999.0
## True while the drone is committed to a pass, so the HUD can warn the player.
var diving: bool = false

var _body: MeshInstance3D
var _rotor: MeshInstance3D
var _rotor_speed: float = 0.0

func _ready() -> void:
	_build()

func _build() -> void:
	_body = MeshInstance3D.new()
	_body.name = "Body"
	var hull := SphereMesh.new()
	hull.radius = GameConfig.HUNTER_VISUAL_RADIUS
	hull.height = GameConfig.HUNTER_VISUAL_RADIUS * 2.0
	hull.radial_segments = 10
	hull.rings = 6
	_body.mesh = hull
	_body.material_override = Materials.hunter()
	add_child(_body)

	_rotor = MeshInstance3D.new()
	_rotor.name = "Rotor"
	var blade := TorusMesh.new()
	blade.inner_radius = GameConfig.HUNTER_VISUAL_RADIUS * 0.9
	blade.outer_radius = GameConfig.HUNTER_VISUAL_RADIUS * 1.6
	blade.rings = 12
	blade.ring_segments = 6
	_rotor.mesh = blade
	_rotor.material_override = Materials.hunter_rotor()
	_rotor.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(_rotor)

## Puts the drone back where the run started, and forgets everything.
func reset(at: Vector3, level: int, seed_value: int) -> void:
	model.reset(at)
	brain.configure(level, seed_value)
	since_contact = 999.0
	diving = false
	position = at
	visible = true

## One fixed step: decide, thrust, move, and note whether this was a pass.
##
## The drone's depth is slaved to the bird's, offset ahead of it. It has to be
## slaved: the bird flies forward at eleven to nineteen metres a second and the
## drone tops out at nine, so a drone that had to win a race in z would fall
## behind in the first second and the entire hunter would be a no-op. The
## offset is what makes it visible -- see GameConfig.HUNTER_DEPTH_OFFSET.
func advance(delta: float, s: HunterSensors) -> void:
	var decision := brain.decide(s)
	model.step(delta, decision.thrust)
	model.position.z = s.bird_position.z + GameConfig.HUNTER_DEPTH_OFFSET
	diving = decision.dive
	since_contact += delta
	position = model.position
	_spin(delta)

## Called by the game the moment the drone touches the bird, so the brain
## starts its retreat and the invulnerability clock begins.
func note_contact() -> void:
	since_contact = 0.0

## The force the drone's wake writes into the bird at a point, in m/s^2.
##
## Zero outside the wake radius, which is the property that makes the drone a
## pressure rather than a constant nuisance. Inside, the push is away from the
## drone and falls off linearly to nothing at the edge -- linearly, not
## quadratically, so the boundary of the wake is a place the player can feel
## and learn to stay out of.
func wind_at(point: Vector2) -> Vector2:
	var centre := Vector2(model.position.x, model.position.y)
	var offset := point - centre
	var distance := offset.length()
	if distance >= GameConfig.HUNTER_FORCE_RADIUS:
		return Vector2.ZERO
	var away := Vector2(0.0, 1.0)
	if distance > 0.001:
		away = offset / distance
	var falloff := 1.0 - distance / GameConfig.HUNTER_FORCE_RADIUS
	return away * GameConfig.HUNTER_FORCE * falloff

## The spin is presentation only, and is driven from advance() rather than
## _process so a headless run and a windowed run show the same thing.
func _spin(delta: float) -> void:
	_rotor_speed += delta * 22.0
	_rotor.rotation.y = _rotor_speed
	# Bank into the turn, which is the cheapest way to make a sphere read as a
	# machine that is going somewhere.
	_body.rotation.z = clampf(-model.velocity.x * 0.06, -0.5, 0.5)
	_body.rotation.x = clampf(model.velocity.y * 0.04, -0.4, 0.4)

# --- read-only view, so a test can assert what the drone did ----------------

func brain_state() -> int:
	return brain.state

func lead_point_now() -> Vector3:
	return brain.lead
