class_name PropLibrary
extends RefCounted

## Loads and dresses the Blender-generated environment kit.
##
## ### Materials are re-assigned on load, and dimmed by depth
##
## The GLBs ship placeholder materials named by *intent* (`kit_metal`,
## `kit_dark`, …). This maps those onto `SurfaceLibrary`, so props automatically
## share the level's value structure and batch with the block geometry instead of
## introducing a second, drifting palette.
##
## More importantly, a prop's material is **lightened toward the haze colour in
## proportion to how far behind the play plane it sits**. This enforces by
## construction the rule that was learned the hard way during Demo 0.1: nothing in
## the scene may compete with the runner's silhouette. A near-black vent stack
## standing directly behind the runner's torso swallows the figure. With depth
## dimming, a prop pushed back for visual depth automatically *becomes* background,
## and the only truly dark things on screen are the runner and the fascia lines
## below the walking surface.
##
## The same ramp is used by `SkylineBackdrop`, so props and skyline agree.

## Where the kit lives.
const PROP_PATH: String = "res://assets/props/%s.glb"

## Kit material name -> the level surface kind it maps to.
const MATERIAL_MAP: Dictionary[String, SurfaceLibrary.Kind] = {
	"kit_concrete": SurfaceLibrary.Kind.CONCRETE,
	"kit_metal": SurfaceLibrary.Kind.METAL,
	"kit_dark": SurfaceLibrary.Kind.DARK,
	"kit_trim": SurfaceLibrary.Kind.TRIM,
	"kit_accent": SurfaceLibrary.Kind.PAINTED,
	"kit_glass": SurfaceLibrary.Kind.GLASS,
}

## Depth at which a prop is fully faded into the haze. Beyond this, props are pure
## background shape.
const FULL_FADE_DEPTH: float = 18.0

## Minimum fade applied to *any* prop placed behind the play plane, however close.
##
## A floor, not a curve — and it is load-bearing. A railing two metres behind the
## runner is geometrically almost in the play plane, so a depth-proportional fade
## barely touched it, and a near-black railing running horizontally through the
## runner's torso at exactly body height merged with the silhouette. The rule is
## absolute rather than graduated: scenery is *never* part of the foreground
## palette, no matter how close it sits.
const MINIMUM_SCENERY_FADE: float = 0.3

## Depth below which a prop counts as being in the play plane — furniture — and
## keeps the full foreground palette.
const FOREGROUND_DEPTH: float = 0.75

## Colour distant geometry converges on. Matches `SkylineBackdrop.HAZE`.
const HAZE: Color = Color(0.29, 0.28, 0.335)

static var _scene_cache: Dictionary[String, PackedScene] = {}
## Material cache keyed by "kind:depth_bucket", so a hundred props at the same
## depth share one material and one draw call.
static var _material_cache: Dictionary[String, StandardMaterial3D] = {}


## Instantiates a prop, with materials resolved for its depth.
##
## `depth` is how far *behind* the play plane the prop sits (positive numbers mean
## further away), used only for the value ramp.
static func create(kind: String, depth: float = 0.0) -> Node3D:
	var scene: PackedScene = _load(kind)
	if scene == null:
		return null
	var instance: Node3D = scene.instantiate() as Node3D
	if instance == null:
		return null
	_dress(instance, depth)
	return instance


static func _load(kind: String) -> PackedScene:
	if _scene_cache.has(kind):
		return _scene_cache[kind]
	var path: String = PROP_PATH % kind
	if not ResourceLoader.exists(path):
		push_error("Prop '%s' not found at %s. Run ./scripts/build_assets.sh." % [kind, path])
		return null
	var scene: PackedScene = load(path) as PackedScene
	_scene_cache[kind] = scene
	return scene


## Walks the instance and swaps every surface material for a depth-adjusted one.
static func _dress(node: Node, depth: float) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		for surface: int in mesh_instance.mesh.get_surface_count():
			var source: Material = mesh_instance.mesh.surface_get_material(surface)
			var key: String = source.resource_name if source != null else ""
			var kind: SurfaceLibrary.Kind = _kind_for(key)
			mesh_instance.set_surface_override_material(
				surface, _material(kind, depth)
			)
		# Scenery casts no shadows. Props behind the play plane throw long shadows
		# across the walking surface at this sun angle, which adds noise exactly
		# where the player needs to read the ground.
		if depth > 1.0:
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for child: Node in node.get_children():
		_dress(child, depth)


static func _kind_for(material_name: String) -> SurfaceLibrary.Kind:
	for key: String in MATERIAL_MAP:
		# glTF import may suffix material names, so match on the prefix.
		if material_name.begins_with(key):
			return MATERIAL_MAP[key]
	return SurfaceLibrary.Kind.CONCRETE


## Depth-faded variant of a surface material.
##
## Quantised into 0.1 buckets so nearby props share a cached material rather than
## each allocating their own — the point of the shared palette is draw-call
## batching, and a continuous fade would defeat it.
static func _material(kind: SurfaceLibrary.Kind, depth: float) -> StandardMaterial3D:
	var fade: float = 0.0
	if depth > FOREGROUND_DEPTH:
		fade = maxf(
			MINIMUM_SCENERY_FADE,
			clampf(depth / FULL_FADE_DEPTH, 0.0, 1.0)
		)
	var bucket: int = int(round(fade * 10.0))
	var key: String = "%d:%d" % [int(kind), bucket]
	if _material_cache.has(key):
		return _material_cache[key]

	var base: StandardMaterial3D = SurfaceLibrary.get_material(kind)
	if bucket == 0:
		_material_cache[key] = base
		return base

	var faded: StandardMaterial3D = base.duplicate() as StandardMaterial3D
	var t: float = float(bucket) / 10.0
	faded.albedo_color = base.albedo_color.lerp(HAZE, t)
	# Distant geometry loses its specular response along with its contrast;
	# leaving props glossy at distance makes them pop forward again.
	faded.roughness = lerpf(base.roughness, 0.95, t)
	faded.metallic = lerpf(base.metallic, 0.0, t)
	if t > 0.55:
		# Far enough back that the sun angle should not matter — flat shape only,
		# which is both cheaper and keeps the aerial-perspective ramp intact.
		faded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		faded.albedo_color = base.albedo_color.lerp(HAZE, minf(1.0, t * 1.1))
	_material_cache[key] = faded
	return faded


## Drops the caches. Only needed by tooling that rebuilds assets at edit time.
static func clear_cache() -> void:
	_scene_cache.clear()
	_material_cache.clear()
