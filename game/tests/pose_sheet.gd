extends Node

## Renders the runner alone, large, on a neutral backdrop — one image per pose.
##
##   ./scripts/pose_sheet.sh
##
## The in-level shots show the character at gameplay scale (~150 px) against a busy
## backdrop, which is the right way to judge *readability* but hopeless for
## diagnosing the rig. A near-black low-poly figure that small is genuinely
## ambiguous: "the pose is wrong", "the model is rotated" and "the silhouette is
## fine and I am misreading it" all look identical.
##
## This isolates the variable. Neutral mid-grey background, flat lighting, figure
## filling the frame, one frame per authored pose plus the untouched rest pose as a
## control.

const MODEL_PATH: String = "res://assets/characters/runner.glb"

## Poses to render, by the state name the animator maps them from.
const POSE_STATES: PackedStringArray = [
	"Idle", "Run", "Jump", "Fall", "Land", "HardLanding",
	"Slide", "Roll", "Vault", "Climb", "LedgeGrab", "WallRun", "Death",
]

var _out_dir: String = "res://../captures/poses"
var _skeleton: Skeleton3D
var _animator: RunnerAnimator
var _rig: Node3D


func _ready() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("=== pose sheet -> %s ===" % _out_dir)

	_build_stage()
	await _render_all()


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			_out_dir = args[i + 1]


func _build_stage() -> void:
	# Flat neutral lighting: the point is to see shape, not to judge the art
	# direction, so nothing here should flatter or hide the geometry.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.44, 0.48)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.ambient_light_energy = 0.9
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 24.0, 0.0)
	key.light_energy = 1.4
	add_child(key)

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if packed == null:
		printerr("could not load %s" % MODEL_PATH)
		get_tree().quit(1)
		return

	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	var model: Node = packed.instantiate()
	_rig.add_child(model)
	_skeleton = _find_skeleton(model)

	# Frame the figure tightly and dead-on from the side, matching the game's view
	# direction so what is judged here is what the game shows.
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.95, 3.4)
	camera.fov = 42.0
	add_child(camera)


func _render_all() -> void:
	# Control frame: the rest pose, nothing applied. If this is upright and correct,
	# the model and import are fine and any problem is in the posing.
	await _shoot("00-rest")

	# Poses are applied through the same bone bindings and axis maths the animator
	# uses. The animator node itself is not instantiated here — it needs a live
	# Player to drive it, and adding a non-functional one only adds noise.
	for state: String in POSE_STATES:
		_apply_named_pose(state)
		_report_landmarks(state)
		await _shoot("%02d-%s" % [POSE_STATES.find(state) + 1, state.to_lower()])

	print("POSE SHEET: DONE")
	get_tree().call_deferred("quit", 0)


## Applies a pose by name using the same axis maths the animator uses, without
## needing a live Player.
func _apply_named_pose(state: String) -> void:
	var pose: RunnerAnimator.Pose = RunnerAnimator.pose_for_state(StringName(state))
	if pose == null:
		return

	for field: String in RunnerAnimator.BONE_BINDINGS:
		_rotate(RunnerAnimator.BONE_BINDINGS[field], pose.angle_for(field))

	var per_joint: float = -pose.torso / float(RunnerAnimator.SPINE_BONES.size())
	for bone_name: String in RunnerAnimator.SPINE_BONES:
		_rotate(bone_name, per_joint)

	_rig.rotation.z = -pose.root_pitch
	_rig.position.y = pose.root_y


## Rotates a bone about the character's Z axis, composing with its rest rotation.
## Mirrors `RunnerAnimator._pose_bone` exactly; if these two ever disagree, the pose
## sheet stops being evidence about the game.
func _rotate(bone_name: String, angle: float) -> void:
	var index: int = _skeleton.find_bone(bone_name)
	if index < 0:
		return
	var axis: Vector3 = (
		_skeleton.get_bone_global_rest(index).basis.inverse() * Vector3(0.0, 0.0, 1.0)
	).normalized()
	var rest: Quaternion = RunnerAnimator.rest_rotation_of(_skeleton, index)
	_skeleton.set_bone_pose_rotation(index, rest * Quaternion(axis, angle))


## Prints where key landmarks actually ended up.
##
## Reading a pose off a 900 px render of a dark low-poly figure is unreliable — the
## same image can support "the pose is wrong", "the model is rotated" and "you are
## misreading it". Numbers settle it: if the head is at y≈1.6 and the feet near 0,
## the figure is upright whatever the picture seems to show.
func _report_landmarks(state: String) -> void:
	var landmarks: PackedStringArray = ["Head", "HandL", "FootL", "ThighL"]
	var parts: Array[String] = []
	for bone_name: String in landmarks:
		var index: int = _skeleton.find_bone(bone_name)
		if index < 0:
			continue
		var origin: Vector3 = _skeleton.get_bone_global_pose(index).origin
		parts.append("%s=(%.2f,%.2f)" % [bone_name, origin.x, origin.y])
	print("  %-12s %s" % [state, " ".join(parts)])


func _shoot(name: String) -> void:
	for _i: int in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s.png" % [_out_dir, name]
	if image.save_png(path) != OK:
		printerr("failed to write %s" % path)
	else:
		print("wrote %s.png" % name)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null
