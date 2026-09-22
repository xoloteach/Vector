class_name SkylineBackdrop
extends Node3D

## Procedural city depth behind the play plane.
##
## Purely visual — nothing here has collision, and nothing here may ever sit in
## front of the play plane. That rule is a gameplay rule, not an art rule: the
## fastest way to ruin a side-view parkour game is to let decoration compete
## with the surfaces the player has to read.
##
## Depth is sold with three cheap tricks rather than expensive rendering:
## layered parallax planes at increasing Z, monotonically darker-and-flatter
## values with distance (aerial perspective), and window grids that get denser
## and dimmer so the eye reads scale.

## --- The value ramp, and the mistake it corrects ----------------------------
##
## Distant geometry gets **lighter**, converging on the sky's haze colour.
##
## The first version did the opposite — each layer darker than the last — on the
## reasoning that dark equals distant. Against a bright dusk sky that inverts the
## composition: the furthest masses become the highest-contrast shapes on screen,
## read as foreground, and the near-black runner disappears into them. A critic
## pass on the first real screenshots flagged exactly that, and it was the single
## worst problem in the build.
##
## Real aerial perspective works the other way: intervening atmosphere washes
## distant objects *toward* the sky. Ramping that way puts the darkest values on
## the runner and the play geometry, where the player needs to look.
##
## Nearest layer's mass colour. Must stay clearly lighter than the character
## (~0.05 luminance) so the silhouette always separates from it.
const NEAR_MASS: Color = Color(0.125, 0.145, 0.205)
## Colour distant masses converge to. Tracks the sky horizon.
const HAZE: Color = Color(0.46, 0.44, 0.50)

## Each layer: Z distance, size ranges, spacing, and `depth` — its 0..1 position
## along the near→haze ramp.
const LAYERS: Array[Dictionary] = [
	{"z": -14.0, "h": Vector2(14.0, 30.0), "w": Vector2(7.0, 13.0), "gap": Vector2(3.0, 8.0), "depth": 0.16, "windows": true},
	{"z": -30.0, "h": Vector2(22.0, 46.0), "w": Vector2(10.0, 20.0), "gap": Vector2(4.0, 12.0), "depth": 0.40, "windows": true},
	{"z": -56.0, "h": Vector2(34.0, 66.0), "w": Vector2(16.0, 32.0), "gap": Vector2(6.0, 18.0), "depth": 0.66, "windows": false},
	{"z": -92.0, "h": Vector2(48.0, 88.0), "w": Vector2(26.0, 52.0), "gap": Vector2(8.0, 26.0), "depth": 0.88, "windows": false},
]

## Deterministic so the skyline is identical every run and every screenshot —
## visual regression comparison is impossible against a randomised backdrop.
const SEED: int = 20260922

@export var from_x: float = -80.0
@export var to_x: float = 320.0
## Base Y the buildings rise from, well below the play area.
@export var base_y: float = -40.0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = SEED
	for layer: Dictionary in LAYERS:
		_build_layer(layer)


func _build_layer(layer: Dictionary) -> void:
	var z: float = layer["z"]
	var depth: float = layer["depth"]
	var mat: StandardMaterial3D = _flat_material(depth)
	var window_mat: StandardMaterial3D = _window_material(depth)

	var multimesh_boxes: Array[Transform3D] = []
	var window_boxes: Array[Transform3D] = []

	var x: float = from_x
	while x < to_x:
		var w: float = _rng.randf_range(layer["w"].x, layer["w"].y)
		var h: float = _rng.randf_range(layer["h"].x, layer["h"].y)
		var mass_depth: float = w * 0.6

		multimesh_boxes.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3(w, h, mass_depth)),
			Vector3(x + w * 0.5, base_y + h * 0.5, z)
		))

		if layer["windows"]:
			_scatter_windows(window_boxes, x, w, base_y, h, z + mass_depth * 0.5)

		x += w + _rng.randf_range(layer["gap"].x, layer["gap"].y)

	_add_multimesh("Mass_%d" % int(z), multimesh_boxes, mat)
	if not window_boxes.is_empty():
		_add_multimesh("Windows_%d" % int(z), window_boxes, window_mat)


## Window grid on a building face. Randomly lit cells read as an occupied city
## and give the flat masses a sense of scale.
func _scatter_windows(
	out: Array[Transform3D],
	building_x: float,
	building_w: float,
	building_base: float,
	building_h: float,
	face_z: float
) -> void:
	var cell: float = 2.4
	var cols: int = int(building_w / cell) - 1
	var rows: int = int(building_h / cell) - 1
	for c: int in range(1, maxi(1, cols)):
		for r: int in range(1, maxi(1, rows)):
			if _rng.randf() > 0.28:
				continue
			var wx: float = building_x + c * cell + cell * 0.5
			var wy: float = building_base + r * cell + cell * 0.5
			# Small and narrow. Large window quads read as decals stuck on the
			# front rather than as openings.
			out.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(0.62, 0.95, 0.1)),
				Vector3(wx, wy, face_z)
			))


## One MultiMeshInstance3D per layer keeps the whole backdrop at a handful of
## draw calls, which is what makes it affordable on WebGL2.
func _add_multimesh(node_name: String, transforms: Array[Transform3D], mat: Material) -> void:
	if transforms.is_empty():
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE

	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i: int in transforms.size():
		multi.set_instance_transform(i, transforms[i])

	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	instance.material_override = mat
	# Backdrop geometry never casts shadows — it would be invisible anyway and
	# the shadow atlas is better spent on the play plane.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _flat_material(depth: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	# Unshaded: distant masses should be pure value, unaffected by the sun angle.
	# It is cheaper and it guarantees the aerial-perspective ramp stays intact
	# regardless of how the foreground lighting is later retuned.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = NEAR_MASS.lerp(HAZE, depth)
	return mat


func _window_material(depth: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Windows are **darker** than their host mass, with a faint warm cast.
	#
	# Counter-intuitive, but correct here: once distant buildings are washed
	# pale by haze, an unlit window is a hole in that pale surface, not a lamp on
	# it. Rendering them brighter made them detach into a scatter of tan chips
	# floating in front of the skyline. Darker, they sit in the mass and give it
	# scale, which is the only job they have.
	var mass: Color = NEAR_MASS.lerp(HAZE, depth)
	mat.albedo_color = Color(
		mass.r * 0.66 + 0.02,
		mass.g * 0.62 + 0.012,
		mass.b * 0.66
	)
	return mat
