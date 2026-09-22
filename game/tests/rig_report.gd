extends Node

## Prints the imported runner's node hierarchy and bone rest orientations.
##
##   godot --headless --path game res://tests/rig_report.tscn
##
## Exists because retargeting bugs are invisible from the outside: a character that
## renders lying on its side looks identical to one whose pose axes are wrong, and
## guessing between them from a screenshot wastes whole render cycles. This prints
## the actual transforms the engine ended up with.

const MODEL_PATH: String = "res://assets/characters/runner.glb"


func _ready() -> void:
	print("=== runner rig report ===")
	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if packed == null:
		printerr("could not load %s" % MODEL_PATH)
		get_tree().call_deferred("quit", 1)
		return

	var root: Node = packed.instantiate()
	add_child(root)

	print("\n--- hierarchy ---")
	_dump(root, 0)

	var skeleton: Skeleton3D = _find_skeleton(root)
	if skeleton == null:
		printerr("no Skeleton3D found")
		get_tree().call_deferred("quit", 1)
		return

	print("\n--- skeleton node transform ---")
	print("  position %s" % skeleton.position)
	print("  rotation_degrees %s" % skeleton.rotation_degrees)
	print("  scale %s" % skeleton.scale)

	print("\n--- bone global rest (origin, and where local axes point) ---")
	for i: int in skeleton.get_bone_count():
		var rest: Transform3D = skeleton.get_bone_global_rest(i)
		var axis: Vector3 = (rest.basis.inverse() * Vector3(0.0, 0.0, 1.0)).normalized()
		print("  %-14s origin=%s  localY_in_skel=%s  z_axis_local=%s" % [
			skeleton.get_bone_name(i),
			_v(rest.origin),
			_v(rest.basis * Vector3(0.0, 1.0, 0.0)),
			_v(axis),
		])

	print("\nRIG REPORT: DONE")
	get_tree().call_deferred("quit", 0)


func _dump(node: Node, depth: int) -> void:
	var transform_text: String = ""
	if node is Node3D:
		var n3: Node3D = node
		transform_text = "  pos=%s rot=%s scale=%s" % [
			_v(n3.position), _v(n3.rotation_degrees), _v(n3.scale)
		]
	print("%s%s [%s]%s" % ["  ".repeat(depth), node.name, node.get_class(), transform_text])
	for child: Node in node.get_children():
		_dump(child, depth + 1)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _v(v: Vector3) -> String:
	return "(%6.2f,%6.2f,%6.2f)" % [v.x, v.y, v.z]
