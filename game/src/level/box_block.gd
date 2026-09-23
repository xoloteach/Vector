@tool
class_name BoxBlock
extends StaticBody3D

## A box of level geometry that builds its own mesh and collision from a size.
##
## Levels are authored as lists of these rather than as baked meshes, which
## means a `.tscn` for a whole level is a few kilobytes of transforms and stays
## readable and diffable in git. It also guarantees the visual box and the
## collision box can never disagree, which is the single most common source of
## "I clearly landed on that" complaints.
##
## Depth (Z) is a visual property only — gameplay is a 2D plane, so blocks are
## made generously deep to avoid the runner ever appearing to float in front of
## the surface they are standing on.

@export var size: Vector3 = Vector3(4.0, 1.0, 3.0):
	set(value):
		size = value
		_rebuild()

@export var kind: SurfaceLibrary.Kind = SurfaceLibrary.Kind.CONCRETE:
	set(value):
		kind = value
		_rebuild()

## Multiplied into the material colour via vertex colour, for subtle per-block
## value variation so a wall of identical boxes does not read as wallpaper.
@export var tint: Color = Color.WHITE:
	set(value):
		tint = value
		_rebuild()

## When false the block is decoration only — no collision. Used for background
## layers and for detail that should never interfere with traversal.
@export var solid: bool = true:
	set(value):
		solid = value
		_rebuild()

## Marks the block as something the parkour system should treat as traversable
## furniture (physics layer 3) rather than structural world (layer 1). Purely
## informational for now; the sensor probes both.
@export var traversable: bool = false:
	set(value):
		traversable = value
		_rebuild()

## Whether this block casts shadows. Turned off for large structural decks — see
## the note in `_rebuild()`.
@export var casts_shadow: bool = true:
	set(value):
		casts_shadow = value
		_rebuild()

var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return

	if _mesh_instance == null:
		_mesh_instance = get_node_or_null("Mesh") as MeshInstance3D
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "Mesh"
		add_child(_mesh_instance)

	var box_mesh: BoxMesh = _mesh_instance.mesh as BoxMesh
	if box_mesh == null:
		box_mesh = BoxMesh.new()
		_mesh_instance.mesh = box_mesh
	box_mesh.size = size
	_apply_tint()

	collision_layer = (4 if traversable else 1) if solid else 0
	collision_mask = 0  # static geometry never needs to detect anything

	# Shadow casting is opt-out, for two different reasons.
	#
	# **Decoration** never casts. Decorative blocks are thin plates sitting a few
	# centimetres off the surfaces they trim, so at a grazing sun angle they throw
	# jagged, shadow-map-aliased sawtooth edges across the geometry right where the
	# player is reading a deck edge. They are readability aids; letting them damage
	# readability defeats the point.
	#
	# **Large structural blocks** opt out via `casts_shadow`. A 28 m deck is wide
	# enough that the shadow atlas cannot resolve it, and it self-shadows its own
	# front face into a visible diagonal weave — on the largest flat surface in the
	# frame. Receiving is unaffected, so the runner and the props still cast onto the
	# deck, which is where grounding shadows actually matter.
	_mesh_instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (solid and casts_shadow)
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)

	if _collision == null:
		_collision = get_node_or_null("Collision") as CollisionShape3D
	if solid:
		if _collision == null:
			_collision = CollisionShape3D.new()
			_collision.name = "Collision"
			add_child(_collision)
		var shape: BoxShape3D = _collision.shape as BoxShape3D
		if shape == null:
			shape = BoxShape3D.new()
			_collision.shape = shape
		shape.size = size
		_collision.disabled = false
	elif _collision != null:
		_collision.disabled = true


## Applies `tint` by baking it into a per-block material copy only when it is
## actually not white, so the shared-material fast path is preserved for the
## overwhelming majority of blocks.
func _apply_tint() -> void:
	if tint.is_equal_approx(Color.WHITE):
		_mesh_instance.material_override = SurfaceLibrary.get_material(kind)
		return
	var base: StandardMaterial3D = SurfaceLibrary.get_material(kind)
	var copy: StandardMaterial3D = base.duplicate() as StandardMaterial3D
	copy.albedo_color = base.albedo_color * tint
	_mesh_instance.material_override = copy


## Convenience constructor for procedural level generation.
static func create(
	position: Vector3,
	block_size: Vector3,
	block_kind: SurfaceLibrary.Kind = SurfaceLibrary.Kind.CONCRETE
) -> BoxBlock:
	var block := BoxBlock.new()
	block.size = block_size
	block.kind = block_kind
	block.position = position
	return block
