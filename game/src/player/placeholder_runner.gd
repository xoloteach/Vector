class_name PlaceholderRunner
extends Node3D

## Temporary blocked-out runner: a jointed humanoid built from boxes, animated
## procedurally.
##
## This exists so movement can be judged *now*, before the Blender pipeline
## lands. A capsule would let the controller be tested but would tell us nothing
## about whether the movement reads — and readability is the thing most at risk
## in a silhouette-based side-view game. A jointed figure with a real gait
## exposes foot sliding, bad jump arcs and mushy landings immediately.
##
## Replaced wholesale in Phase 3 by a skinned mesh from `blender/scripts/`. The
## rig proportions here are the spec that model will be built to.

# Proportions, metres. Athletic build, slightly long-limbed so the silhouette
# stays legible when the figure is only ~80 px tall on screen.
const HIP_HEIGHT: float = 0.94
const SHOULDER_HEIGHT: float = 1.48
const HEAD_HEIGHT: float = 1.66
const THIGH: float = 0.46
const SHIN: float = 0.46
const UPPER_ARM: float = 0.30
const FOREARM: float = 0.30

## Strides per second at full run speed. Tuned so the foot contact rate matches
## the ground speed and the figure does not appear to skate.
const STRIDE_RATE_AT_SPEED: float = 2.35
## Stride rate floor, so a slow jog still cycles rather than freezing.
const STRIDE_RATE_MIN: float = 0.8

var _player: Player
var _root: Node3D

var _torso: Node3D
var _head: Node3D
var _hip_l: Node3D
var _hip_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _shoulder_l: Node3D
var _shoulder_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D

## Gait phase in radians, advanced by distance travelled rather than by time so
## foot contacts stay locked to ground speed at any velocity.
var _phase: float = 0.0
## Smoothed 0..1 blend between the airborne pose and the running pose.
var _air_blend: float = 0.0
## Landing compression, spikes on impact and decays.
var _squash: float = 0.0


func _ready() -> void:
	_player = get_parent().get_parent() as Player
	if _player == null:
		# Visual is a grandchild of Player (Player > Visual > Runner). If the
		# hierarchy changes, fail loudly rather than animating nothing.
		_player = _find_player_ancestor()
	if _player != null:
		_player.landed.connect(_on_landed)
	_build()


func _find_player_ancestor() -> Player:
	var node: Node = get_parent()
	while node != null:
		if node is Player:
			return node
		node = node.get_parent()
	push_warning("PlaceholderRunner could not find its Player ancestor.")
	return null


# --------------------------------------------------------------------- skeleton

func _build() -> void:
	var dark: StandardMaterial3D = _material(Color(0.055, 0.065, 0.085))
	var accent: StandardMaterial3D = _material(Color(0.82, 0.44, 0.13))

	_root = Node3D.new()
	_root.name = "Rig"
	add_child(_root)

	# Torso pivots at the hip so leaning tips the whole upper body.
	_torso = _joint(_root, "Torso", Vector3(0.0, HIP_HEIGHT, 0.0))
	_box(_torso, Vector3(0.34, 0.56, 0.24), Vector3(0.0, 0.28, 0.0), dark)
	# A shoulder yoke in the accent colour gives the silhouette a readable
	# highlight so body orientation is clear at small screen sizes.
	_box(_torso, Vector3(0.40, 0.10, 0.26), Vector3(0.0, 0.52, 0.0), accent)

	_head = _joint(_torso, "Head", Vector3(0.0, SHOULDER_HEIGHT - HIP_HEIGHT, 0.0))
	_box(_head, Vector3(0.21, 0.24, 0.22), Vector3(0.0, HEAD_HEIGHT - SHOULDER_HEIGHT + 0.06, 0.0), dark)

	_hip_l = _joint(_root, "HipL", Vector3(0.0, HIP_HEIGHT, 0.10))
	_hip_r = _joint(_root, "HipR", Vector3(0.0, HIP_HEIGHT, -0.10))
	_knee_l = _limb(_hip_l, "KneeL", THIGH, SHIN, 0.15, dark)
	_knee_r = _limb(_hip_r, "KneeR", THIGH, SHIN, 0.15, dark)

	_shoulder_l = _joint(_torso, "ShoulderL", Vector3(0.0, SHOULDER_HEIGHT - HIP_HEIGHT - 0.04, 0.16))
	_shoulder_r = _joint(_torso, "ShoulderR", Vector3(0.0, SHOULDER_HEIGHT - HIP_HEIGHT - 0.04, -0.16))
	_elbow_l = _limb(_shoulder_l, "ElbowL", UPPER_ARM, FOREARM, 0.10, dark)
	_elbow_r = _limb(_shoulder_r, "ElbowR", UPPER_ARM, FOREARM, 0.10, dark)


## Creates a two-segment limb: a segment hanging from `parent`, and a child joint
## at its end carrying the second segment. Returns the child joint.
func _limb(
	parent: Node3D,
	child_name: String,
	upper: float,
	lower: float,
	thickness: float,
	mat: StandardMaterial3D
) -> Node3D:
	_box(parent, Vector3(thickness, upper, thickness), Vector3(0.0, -upper * 0.5, 0.0), mat)
	var joint: Node3D = _joint(parent, child_name, Vector3(0.0, -upper, 0.0))
	_box(joint, Vector3(thickness * 0.9, lower, thickness * 0.9), Vector3(0.0, -lower * 0.5, 0.0), mat)
	return joint


func _joint(parent: Node3D, joint_name: String, offset: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = joint_name
	node.position = offset
	parent.add_child(node)
	return node


func _box(parent: Node3D, size: Vector3, offset: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.material_override = mat
	parent.add_child(mesh_instance)
	return mesh_instance


func _material(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.75
	mat.metallic = 0.05
	# A rim term traces the outline of every limb with a faint cool highlight.
	#
	# This is doing readability work, not decoration. The runner is deliberately
	# near-black so it reads as a silhouette, which means on any dark backdrop it
	# risks vanishing entirely. The rim guarantees the *edges* of the figure stay
	# visible no matter what is behind it, without lifting the body value and
	# losing the silhouette. It is also cheap — a per-pixel fresnel, supported in
	# the compatibility renderer.
	mat.rim_enabled = true
	mat.rim = 0.62
	mat.rim_tint = 0.25
	return mat


# -------------------------------------------------------------------- animation

func _process(delta: float) -> void:
	if _player == null:
		return

	var speed_ratio: float = _player.speed_ratio()
	var grounded: bool = _player.is_on_floor()

	# Advance the gait by distance, not time: one stride per fixed distance means
	# feet plant at the same world points regardless of frame rate or speed.
	var stride_rate: float = maxf(STRIDE_RATE_MIN, STRIDE_RATE_AT_SPEED * speed_ratio)
	if grounded and speed_ratio > 0.02:
		_phase += stride_rate * TAU * delta
	elif grounded:
		_phase = lerp_angle(_phase, 0.0, minf(1.0, 8.0 * delta))

	var air_target: float = 0.0 if grounded else 1.0
	_air_blend = lerpf(_air_blend, air_target, minf(1.0, 11.0 * delta))
	_squash = maxf(0.0, _squash - delta * 4.5)

	if grounded:
		_pose_ground(speed_ratio)
	_pose_air_blend()
	_apply_body_attitude(speed_ratio, delta)


## Running / idle pose driven by gait phase.
func _pose_ground(speed_ratio: float) -> void:
	var swing: float = deg_to_rad(lerpf(6.0, 52.0, speed_ratio))
	var knee_bend: float = deg_to_rad(lerpf(8.0, 78.0, speed_ratio))
	var arm_swing: float = deg_to_rad(lerpf(4.0, 44.0, speed_ratio))

	var l: float = sin(_phase)
	var r: float = sin(_phase + PI)

	# Thighs swing fore/aft; knees flex hardest on the recovery (rearward) half,
	# which is what makes a run read as a run and not a march.
	_hip_l.rotation.x = -l * swing
	_hip_r.rotation.x = -r * swing
	_knee_l.rotation.x = knee_bend * maxf(0.0, -l) + deg_to_rad(6.0)
	_knee_r.rotation.x = knee_bend * maxf(0.0, -r) + deg_to_rad(6.0)

	# Arms counter-swing against the legs.
	_shoulder_l.rotation.x = r * arm_swing
	_shoulder_r.rotation.x = l * arm_swing
	_elbow_l.rotation.x = -deg_to_rad(lerpf(10.0, 72.0, speed_ratio))
	_elbow_r.rotation.x = -deg_to_rad(lerpf(10.0, 72.0, speed_ratio))


## Blends toward a tucked airborne pose. Blending rather than switching is what
## keeps takeoff and landing from snapping.
func _pose_air_blend() -> void:
	if _air_blend < 0.01:
		return
	var rising: bool = _player.velocity.y > 0.0
	var b: float = _air_blend

	# Rising: legs trail and tuck. Falling: lead leg reaches for the ground.
	var lead: float = deg_to_rad(-38.0 if rising else -14.0)
	var trail: float = deg_to_rad(26.0 if rising else 8.0)
	var knee_front: float = deg_to_rad(74.0 if rising else 28.0)
	var knee_back: float = deg_to_rad(52.0 if rising else 62.0)

	_hip_l.rotation.x = lerpf(_hip_l.rotation.x, lead, b)
	_hip_r.rotation.x = lerpf(_hip_r.rotation.x, trail, b)
	_knee_l.rotation.x = lerpf(_knee_l.rotation.x, knee_front, b)
	_knee_r.rotation.x = lerpf(_knee_r.rotation.x, knee_back, b)

	# Arms up and forward in the air — reads as reaching, and widens the
	# silhouette so the airborne state is unmistakable.
	_shoulder_l.rotation.x = lerpf(_shoulder_l.rotation.x, deg_to_rad(-52.0), b)
	_shoulder_r.rotation.x = lerpf(_shoulder_r.rotation.x, deg_to_rad(-24.0), b)
	_elbow_l.rotation.x = lerpf(_elbow_l.rotation.x, deg_to_rad(-88.0), b)
	_elbow_r.rotation.x = lerpf(_elbow_r.rotation.x, deg_to_rad(-64.0), b)


## Whole-body attitude: forward lean with speed, vertical compression on impact,
## and a small bob synced to the gait.
func _apply_body_attitude(speed_ratio: float, delta: float) -> void:
	var lean: float = deg_to_rad(lerpf(2.0, 15.0, speed_ratio))
	if not _player.is_on_floor():
		# Pitch with vertical velocity so rising and falling read differently.
		lean = deg_to_rad(clampf(-_player.velocity.y * 0.5, -14.0, 20.0))
	_root.rotation.x = lerp_angle(_root.rotation.x, lean, minf(1.0, 9.0 * delta))

	var bob: float = 0.0
	if _player.is_on_floor() and speed_ratio > 0.05:
		# Two bobs per stride, since both feet plant per cycle.
		bob = -absf(sin(_phase)) * 0.055 * speed_ratio
	var compress: float = _squash * 0.26
	_root.position.y = bob - compress
	_root.scale = Vector3(1.0 + compress * 0.5, 1.0 - compress, 1.0 + compress * 0.5)


func _on_landed(impact_speed: float, hard: bool) -> void:
	# Compression proportional to impact, so a small hop barely registers and a
	# long drop visibly hurts.
	var base: float = clampf(impact_speed / 30.0, 0.0, 1.0)
	_squash = maxf(_squash, base * (1.0 if hard else 0.55))
