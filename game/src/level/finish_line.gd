@tool
class_name FinishLine
extends Area3D

## End of the level. Completes the run and hands control to the outro.

signal reached(player: Player)

@export var size: Vector3 = Vector3(2.0, 6.0, 6.0):
	set(value):
		size = value
		_rebuild()

## A vertical light shaft so the goal is visible from a long way off. In a
## side-scroller the player needs to know the run has an end in sight.
@export var show_beacon: bool = true:
	set(value):
		show_beacon = value
		_rebuild()

var _collision: CollisionShape3D
var _beacon: MeshInstance3D
var _triggered: bool = false


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	collision_layer = 0
	collision_mask = 2
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

	if _beacon == null:
		_beacon = get_node_or_null("Beacon") as MeshInstance3D
	if show_beacon:
		if _beacon == null:
			_beacon = MeshInstance3D.new()
			_beacon.name = "Beacon"
			add_child(_beacon)
		var m: BoxMesh = _beacon.mesh as BoxMesh
		if m == null:
			m = BoxMesh.new()
			_beacon.mesh = m
		m.size = Vector3(0.5, 26.0, 0.5)
		_beacon.position = Vector3(0.0, 10.0, 0.0)

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.45, 0.95, 0.72, 0.22)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beacon.material_override = mat
		_beacon.visible = true
	elif _beacon != null:
		_beacon.visible = false


func _on_body_entered(body: Node3D) -> void:
	if _triggered:
		return
	var player := body as Player
	if player == null:
		return
	_triggered = true
	reached.emit(player)
	Game.complete_run()
