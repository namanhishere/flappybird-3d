class_name Materials
extends RefCounted

## The game's colour palette, and factory methods for the materials built
## from it. Every mesh in the game gets its material from here, which is what
## makes the result read as one coherent low-poly style rather than a pile of
## unrelated default-grey boxes.

const SKY_TOP := Color(0.29, 0.55, 0.82)
const SKY_HORIZON := Color(0.72, 0.87, 0.95)
const FOG := Color(0.72, 0.87, 0.95)
const GROUND := Color(0.33, 0.60, 0.29)
const GROUND_STRIPE := Color(0.42, 0.68, 0.33)
const PIPE := Color(0.16, 0.55, 0.36)
const PIPE_CAP := Color(0.10, 0.40, 0.26)
const WING := Color(0.96, 0.73, 0.27)
const WING_TIP := Color(0.85, 0.55, 0.18)
const SUN := Color(1.0, 0.96, 0.87)

static func _lit(color: Color, roughness := 0.85) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	return material

static func pipe() -> StandardMaterial3D:
	return _lit(PIPE, 0.6)

static func pipe_cap() -> StandardMaterial3D:
	return _lit(PIPE_CAP, 0.5)

static func wing() -> StandardMaterial3D:
	return _lit(WING, 0.75)

static func ground() -> StandardMaterial3D:
	return _lit(GROUND, 1.0)

static func ground_stripe() -> StandardMaterial3D:
	return _lit(GROUND_STRIPE, 1.0)

## The overlay's crosshair, and the ribbon showing the path the co-pilot
## believes it will take. Both unshaded on purpose: they are annotations on the
## world rather than objects in it, and they have to stay legible against a
## bright sky as well as against a dark pipe.
static func target() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.45, 0.30)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

## The hunter drone, in a colour that appears nowhere else, so a player can
## find it against a green corridor without reading the HUD.
static func hunter() -> StandardMaterial3D:
	return _lit(Color(0.82, 0.20, 0.24), 0.4)

static func hunter_rotor() -> StandardMaterial3D:
	return _lit(Color(0.95, 0.85, 0.35), 0.3)

static func predicted_path() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.84, 0.35, 0.85)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Drawn from inside the ribbon's own plane, so it has to be visible from
	# both sides.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
