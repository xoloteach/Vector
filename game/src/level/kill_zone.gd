@tool
class_name KillZone
extends Area3D

## A volume that ends the run on contact.
##
## Used for the void below the rooftops and for explicit hazards. Kept as an
## Area3D rather than a collision layer so a hazard can overlap walkable
## geometry (a gap between two roofs) without affecting traversal probing.

@export var size: Vector3 = Vector3(10.0, 4.0, 8.0):
	set(value):
		size = value
		_rebuild()

## Reason reported to the UI, so "you fell" and "you were crushed" can read
## differently.
@export var reason: String = Game.FAIL_FELL

## Draw a visible warning slab. Off for the void (the drop is self-evident), on
## for hazards the player must be able to see and avoid.
@export var visible_marker: bool = false:
	set(value):
		visible_marker = value
		_rebuild()

var _collision: CollisionShape3D
var _marker: MeshInstance3D


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	monitoring = true
	collision_layer = 0
	collision_mask = 2  # player only
	body_entered.connect(_on_body_entered)


func _rebuild() -> void:
	if not is_inside_tree():
		return

	if _collision == null:
		_collision = get_node_or_null("Collision") as CollisionShape3D
	if _collision == null:
		_collision = CollisionShape3D.new()
		_collision.name = "Collision"
		add_child(_collision)
	var shape: BoxShape3D = _collision.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		_collision.shape = shape
	shape.size = size

	if _marker == null:
		_marker = get_node_or_null("Marker") as MeshInstance3D
	if visible_marker:
		if _marker == null:
			_marker = MeshInstance3D.new()
			_marker.name = "Marker"
			add_child(_marker)
		var m: BoxMesh = _marker.mesh as BoxMesh
		if m == null:
			m = BoxMesh.new()
			_marker.mesh = m
		m.size = size
		_marker.material_override = SurfaceLibrary.get_material(SurfaceLibrary.Kind.HAZARD)
		_marker.visible = true
	elif _marker != null:
		_marker.visible = false


func _on_body_entered(body: Node3D) -> void:
	var player := body as Player
	if player == null:
		return
	player.kill(reason)
