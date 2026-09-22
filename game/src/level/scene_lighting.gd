@tool
class_name SceneLighting
extends Node3D

## Builds and aims the scene's directional lights from named angles.
##
## **Why this exists instead of lights placed in the scene file.** Light direction
## was originally hand-written as a 3×3 basis in the `.tscn`. Getting that matrix
## wrong is silent: the scene still renders, it just renders lit from somewhere
## other than intended. It happened — an attempt to move the key light to the
## front produced a matrix that lit almost nothing, and every up-facing surface in
## the level went black while the unshaded backdrop stayed bright. Diagnosing it
## cost several full render cycles because the failure looks like a material bug,
## a shadow bug, or a tone-mapping bug long before it looks like a typo in a
## matrix.
##
## Pitch and yaw in degrees cannot fail that way, and they are also the terms
## lighting is actually reasoned about in.
##
## Convention: a light at pitch 0, yaw 0 points along −Z, i.e. away from the
## camera and into the scene, illuminating the camera-facing surfaces.
##   - **pitch** tips the light downward (negative = from above).
##   - **yaw** swings it around the vertical axis (positive = from the right).

@export_group("Key light")
## Warm sun. Front-and-above so both the walking surfaces and the camera-facing
## front faces of decks are lit — a purely top-down or back-lit key leaves the
## front faces black, and those faces are how deck *thickness* reads.
## Steep enough that walking surfaces are clearly brighter than the vertical
## faces below them. That difference is what makes a deck read as a surface with
## thickness rather than a flat band.
@export var key_pitch: float = -58.0:
	set(value):
		key_pitch = value
		_rebuild()
@export var key_yaw: float = 30.0:
	set(value):
		key_yaw = value
		_rebuild()
@export var key_color: Color = Color(1.0, 0.86, 0.68):
	set(value):
		key_color = value
		_rebuild()
@export var key_energy: float = 1.1:
	set(value):
		key_energy = value
		_rebuild()
@export var key_shadows: bool = true:
	set(value):
		key_shadows = value
		_rebuild()

@export_group("Rim light")
## Cool counter-light from behind, at a shallow angle. Its job is silhouette
## separation: it catches the top and back edges of the runner so the figure
## never merges into whatever is behind it.
@export var rim_pitch: float = -18.0:
	set(value):
		rim_pitch = value
		_rebuild()
@export var rim_yaw: float = 205.0:
	set(value):
		rim_yaw = value
		_rebuild()
@export var rim_color: Color = Color(0.46, 0.6, 0.95):
	set(value):
		rim_color = value
		_rebuild()
@export var rim_energy: float = 0.7:
	set(value):
		rim_energy = value
		_rebuild()

@export_group("Shadows")
@export var shadow_max_distance: float = 80.0:
	set(value):
		shadow_max_distance = value
		_rebuild()
@export var shadow_bias: float = 0.03:
	set(value):
		shadow_bias = value
		_rebuild()
@export var shadow_normal_bias: float = 1.2:
	set(value):
		shadow_normal_bias = value
		_rebuild()

var _key: DirectionalLight3D
var _rim: DirectionalLight3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return

	_key = _ensure_light("KeyLight", _key)
	_key.light_color = key_color
	_key.light_energy = key_energy
	_key.light_angular_distance = 1.5
	_key.shadow_enabled = key_shadows
	_key.shadow_bias = shadow_bias
	_key.shadow_normal_bias = shadow_normal_bias
	# Light the scene but do not draw a sun disc in the sky. A hard specular blob
	# sitting in the upper corner of a stylised dusk skyline reads as a rendering
	# artefact, and it competes with the runner for attention.
	_key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_key.directional_shadow_max_distance = shadow_max_distance
	_key.directional_shadow_blend_splits = true
	_aim(_key, key_pitch, key_yaw)

	_rim = _ensure_light("RimLight", _rim)
	_rim.light_color = rim_color
	_rim.light_energy = rim_energy
	_rim.shadow_enabled = false
	_rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	# Specular only would be ideal for a pure rim, but the compatibility renderer
	# handles the diffuse term more predictably, so keep it simple and low-energy.
	_aim(_rim, rim_pitch, rim_yaw)


func _ensure_light(light_name: String, cached: DirectionalLight3D) -> DirectionalLight3D:
	if cached != null and cached.is_inside_tree():
		return cached
	var existing := get_node_or_null(light_name) as DirectionalLight3D
	if existing != null:
		return existing
	var light := DirectionalLight3D.new()
	light.name = light_name
	add_child(light)
	return light


## Points a light using pitch/yaw degrees. Rotation order is applied explicitly
## (yaw then pitch) rather than relying on the node's Euler order, so the result
## does not change if that default ever does.
func _aim(light: DirectionalLight3D, pitch_degrees: float, yaw_degrees: float) -> void:
	var basis := Basis.IDENTITY
	basis = basis.rotated(Vector3.UP, deg_to_rad(yaw_degrees))
	basis = basis.rotated(basis.x, deg_to_rad(pitch_degrees))
	light.transform = Transform3D(basis, Vector3(0.0, 40.0, 0.0))


## The unit vector the key light travels along. Exposed so effects that need to
## agree with the lighting (ground shadow blobs, dust) can ask instead of
## hard-coding a direction.
func key_direction() -> Vector3:
	return -_key.global_transform.basis.z if _key != null else Vector3.DOWN
