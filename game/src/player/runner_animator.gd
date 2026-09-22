class_name RunnerAnimator
extends Node3D

## Procedural animation for the runner: a jointed box rig posed from the movement
## state machine, with blended transitions.
##
## ### Why this exists in this form
##
## It replaces a version that only had a run cycle and an airborne blend. When the
## parkour moves landed, that version rendered a *slide* as an upright standing
## figure and a *vault* as an upright standing figure — the collision capsule
## changed, the silhouette did not. The moves were mechanically correct and visually
## unreadable, which for a game whose whole read is silhouette means they did not
## exist.
##
## ### The architecture is the point, not the boxes
##
## This is the animation system Phase 4 needs, built against a placeholder mesh:
## every state declares a target pose, and the rig *blends* toward it at a
## per-transition rate rather than snapping. Swapping the box rig for a skinned
## Blender mesh replaces `_build()` and the joint writes; the state→pose mapping and
## the blending survive intact.
##
## Blending, not switching, is the whole reason transitions do not visibly snap.
## The blend rate is per-pose because the right speed differs by move: a vault is a
## committed, fast change of shape; a landing settles.

# --- proportions, metres ------------------------------------------------------
# Athletic build, slightly long-limbed so the silhouette stays legible at ~150 px.
const HIP_HEIGHT: float = 0.94
const SHOULDER_HEIGHT: float = 1.48
const HEAD_TOP: float = 1.72
const THIGH: float = 0.46
const SHIN: float = 0.46
const UPPER_ARM: float = 0.31
const FOREARM: float = 0.31

## Strides per second at full speed. Tuned so foot contact rate matches ground
## speed and the figure does not appear to skate.
const STRIDE_RATE_AT_SPEED: float = 2.35
const STRIDE_RATE_MIN: float = 0.85

## A single full-body pose.
##
## ### Rotation axis — the bug this convention exists to prevent
##
## Every joint rotates about **Z**, not X.
##
## The first version rotated about X. In a side-on view that is catastrophically
## wrong and almost invisible as a mistake: rotating a downward-hanging limb about X
## swings it along Z — *into and out of the screen* — so every pose rendered as a
## vertical stick with the limbs merely foreshortened. The vault, the slide and the
## hang were all authored with wide, distinct silhouettes and all three came out
## looking like a standing figure. It read as an animation-quality problem for two
## review cycles when it was actually an axis typo.
##
## Rotating about Z swings limbs through the X/Y plane, which is the plane the camera
## can see.
##
## ### Sign convention
##
## Angles are authored as **positive = forward, in the direction of travel**, because
## that is how a pose is described out loud. Two consequences follow from the
## geometry and are handled at apply time, not at author time:
##
##  - limbs hang *downward*, so a positive Z rotation already swings them forward,
##  - the torso and root point *upward*, so their forward lean is a negative Z
##    rotation and gets negated in `_apply`.
##
## Knees bend backwards (heel toward the seat), so knee angles are normally negative.
class Pose:
	extends RefCounted

	var hip_l: float = 0.0
	var hip_r: float = 0.0
	var knee_l: float = 0.0
	var knee_r: float = 0.0
	var shoulder_l: float = 0.0
	var shoulder_r: float = 0.0
	var elbow_l: float = 0.0
	var elbow_r: float = 0.0
	## Upper body lean, relative to the root.
	var torso: float = 0.0
	## Whole-body pitch. Used by the roll, which rotates right through.
	var root_pitch: float = 0.0
	## Vertical offset of the whole rig, for crouches and landing compression.
	var root_y: float = 0.0
	## Vertical squash, 1.0 = none.
	var squash: float = 0.0

	func blend_toward(other: Pose, t: float) -> void:
		hip_l = lerpf(hip_l, other.hip_l, t)
		hip_r = lerpf(hip_r, other.hip_r, t)
		knee_l = lerpf(knee_l, other.knee_l, t)
		knee_r = lerpf(knee_r, other.knee_r, t)
		shoulder_l = lerpf(shoulder_l, other.shoulder_l, t)
		shoulder_r = lerpf(shoulder_r, other.shoulder_r, t)
		elbow_l = lerpf(elbow_l, other.elbow_l, t)
		elbow_r = lerpf(elbow_r, other.elbow_r, t)
		torso = lerpf(torso, other.torso, t)
		root_pitch = lerp_angle(root_pitch, other.root_pitch, t)
		root_y = lerpf(root_y, other.root_y, t)
		squash = lerpf(squash, other.squash, t)

	## Builds a pose from degrees, which is how they are actually authored.
	static func make(
		hip_lead: float, hip_trail: float,
		knee_lead: float, knee_trail: float,
		shoulder_lead: float, shoulder_trail: float,
		elbow: float, torso_lean: float,
		y_offset: float = 0.0, pitch: float = 0.0
	) -> Pose:
		var p := Pose.new()
		p.hip_l = deg_to_rad(hip_lead)
		p.hip_r = deg_to_rad(hip_trail)
		p.knee_l = deg_to_rad(knee_lead)
		p.knee_r = deg_to_rad(knee_trail)
		p.shoulder_l = deg_to_rad(shoulder_lead)
		p.shoulder_r = deg_to_rad(shoulder_trail)
		p.elbow_l = deg_to_rad(elbow)
		p.elbow_r = deg_to_rad(elbow * 0.8)
		p.torso = deg_to_rad(torso_lean)
		p.root_y = y_offset
		p.root_pitch = deg_to_rad(pitch)
		return p


# --- authored poses -----------------------------------------------------------
#
# Each is shaped so that its *silhouette alone* identifies the action. That is the
# test: at 150 px, with no colour information, a slide must not be confusable with a
# crouch, and a vault must not be confusable with a jump.

static func _pose_idle() -> Pose:
	return Pose.make(4, -4, -9, -9, -6, 6, 18, 3)

static func _pose_air_rise() -> Pose:
	# Knees tucked high, arms swept up — a tall, wide, unmistakably airborne shape.
	return Pose.make(52, -24, -88, -58, 104, 62, 62, -8)

static func _pose_air_fall() -> Pose:
	# Lead leg reaching for the ground, arms dropping to balance.
	return Pose.make(24, -14, -32, -68, 34, -16, 52, 7)

static func _pose_land() -> Pose:
	# Deep knee absorb, torso forward over the feet.
	return Pose.make(20, -16, -56, -50, 28, -20, 46, 24, -0.1)

static func _pose_hard_landing() -> Pose:
	return Pose.make(28, -20, -80, -72, 14, -30, 30, 42, -0.26)

static func _pose_slide() -> Pose:
	# Feet-first with the torso angled back, trailing leg folded under — a baseball
	# slide rather than lying flat.
	#
	# An earlier version dropped the root 0.62 m and pitched it hard, which is closer
	# to what a real slide looks like and was unreadable: the figure became a ~20 px
	# smear along the deck's own edge line. Keeping the head and chest clear of the
	# surface is what lets the pose read, and that is worth more than anatomical
	# accuracy.
	return Pose.make(80, 32, -20, -98, -58, -74, 32, -34, -0.3, -30)

static func _pose_roll() -> Pose:
	# Fully tucked ball. Root spin is driven separately, so the body rotates *through*
	# the roll rather than sliding along in a tucked pose.
	return Pose.make(104, 90, -124, -116, 84, 72, 112, 72, -0.46)

static func _pose_vault_low() -> Pose:
	# Legs split wide, trail leg swept back, body pitched forward over the obstacle:
	# a hurdle. The wide split is what makes it read as clearing something.
	return Pose.make(84, -50, -26, -82, -38, 44, 36, 32)

static func _pose_vault_high() -> Pose:
	# Both legs swept to one side with a hand planted behind — a swing-through.
	return Pose.make(64, 40, -88, -104, -84, 48, 26, 40)

static func _pose_climb() -> Pose:
	# Reaching up and pulling: arms overhead, lead knee driving up to the lip.
	return Pose.make(92, -12, -108, -32, 156, 138, 40, 22)

static func _pose_ledge_hang() -> Pose:
	# Hanging straight from both arms, legs trailing slightly bent. A long vertical
	# shape, nothing like any grounded pose.
	return Pose.make(10, -10, -30, -22, 174, 168, 8, -4)

static func _pose_wall_run() -> Pose:
	# Driving upward against the wall: one knee high, both arms reaching.
	return Pose.make(98, -20, -104, -26, 152, 112, 32, -14)

static func _pose_death() -> Pose:
	return Pose.make(14, -10, -32, -38, -46, -60, 20, 48, -0.42)


# --- rig ----------------------------------------------------------------------

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

## The live pose, blended toward the target every frame.
var _current: Pose = Pose.new()
var _scratch: Pose = Pose.new()

## Gait phase in radians, advanced by distance so foot contacts lock to ground speed.
var _phase: float = 0.0
## Landing compression, spikes on impact and decays.
var _squash: float = 0.0
## Extra root spin for the roll, in radians.
var _roll_spin: float = 0.0


func _ready() -> void:
	_player = _find_player()
	if _player != null:
		_player.landed.connect(_on_landed)
		_player.rolled.connect(_on_rolled)
	_build()


func _find_player() -> Player:
	var node: Node = get_parent()
	while node != null:
		if node is Player:
			return node
		node = node.get_parent()
	push_warning("RunnerAnimator could not find its Player ancestor.")
	return null


func _build() -> void:
	# Three value steps inside the silhouette. The figure still reads as a dark
	# shape, but limb positions are legible against the torso — without this the
	# whole rig merges into one rectangle and no pose is distinguishable.
	var torso_mat: StandardMaterial3D = _material(Color(0.042, 0.05, 0.068))
	var limb_mat: StandardMaterial3D = _material(Color(0.072, 0.082, 0.105))
	var near_mat: StandardMaterial3D = _material(Color(0.105, 0.118, 0.145))
	var accent: StandardMaterial3D = _material(Color(0.86, 0.46, 0.13))

	_root = Node3D.new()
	_root.name = "Rig"
	add_child(_root)

	_torso = _joint(_root, "Torso", Vector3(0.0, HIP_HEIGHT, 0.0))
	_box(_torso, Vector3(0.34, 0.56, 0.24), Vector3(0.0, 0.28, 0.0), torso_mat)
	# Shoulder yoke in the accent colour: a readable highlight that makes body
	# orientation and lean obvious at small sizes.
	_box(_torso, Vector3(0.40, 0.10, 0.26), Vector3(0.0, 0.52, 0.0), accent)

	_head = _joint(_torso, "Head", Vector3(0.0, SHOULDER_HEIGHT - HIP_HEIGHT, 0.0))
	_box(_head, Vector3(0.21, 0.24, 0.22), Vector3(0.0, HEAD_TOP - SHOULDER_HEIGHT + 0.02, 0.0), torso_mat)

	# Near-side limbs (+Z, toward the camera) are the lighter pair.
	_hip_l = _joint(_root, "HipL", Vector3(0.0, HIP_HEIGHT, 0.115))
	_hip_r = _joint(_root, "HipR", Vector3(0.0, HIP_HEIGHT, -0.115))
	_knee_l = _limb(_hip_l, "KneeL", THIGH, SHIN, 0.155, near_mat)
	_knee_r = _limb(_hip_r, "KneeR", THIGH, SHIN, 0.155, limb_mat)

	_shoulder_l = _joint(_torso, "ShoulderL", Vector3(0.0, SHOULDER_HEIGHT - HIP_HEIGHT - 0.05, 0.17))
	_shoulder_r = _joint(_torso, "ShoulderR", Vector3(0.0, SHOULDER_HEIGHT - HIP_HEIGHT - 0.05, -0.17))
	_elbow_l = _limb(_shoulder_l, "ElbowL", UPPER_ARM, FOREARM, 0.105, near_mat)
	_elbow_r = _limb(_shoulder_r, "ElbowR", UPPER_ARM, FOREARM, 0.105, limb_mat)


func _limb(
	parent: Node3D, child_name: String, upper: float, lower: float,
	thickness: float, mat: StandardMaterial3D
) -> Node3D:
	_box(parent, Vector3(thickness, upper, thickness), Vector3(0.0, -upper * 0.5, 0.0), mat)
	var joint: Node3D = _joint(parent, child_name, Vector3(0.0, -upper, 0.0))
	_box(joint, Vector3(thickness * 0.88, lower, thickness * 0.88), Vector3(0.0, -lower * 0.5, 0.0), mat)
	return joint


func _joint(parent: Node3D, joint_name: String, offset: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = joint_name
	node.position = offset
	parent.add_child(node)
	return node


func _box(parent: Node3D, size: Vector3, offset: Vector3, mat: StandardMaterial3D) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = offset
	mesh_instance.material_override = mat
	parent.add_child(mesh_instance)


func _material(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.75
	mat.metallic = 0.05
	# A rim term traces the outline of every limb with a faint cool highlight, so the
	# figure's edges stay visible on any backdrop without lifting the body value and
	# losing the silhouette. Cheap: a per-pixel fresnel, supported on compatibility.
	mat.rim_enabled = true
	mat.rim = 0.62
	mat.rim_tint = 0.25
	return mat


# --- per-frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	if _player == null:
		return

	var state: StringName = _player.state_name()
	var speed_ratio: float = _player.speed_ratio()
	var grounded: bool = _player.is_on_floor()

	_advance_gait(delta, state, speed_ratio, grounded)
	_squash = maxf(0.0, _squash - delta * 4.5)

	var target: Pose = _target_pose(state, speed_ratio)
	_current.blend_toward(target, minf(1.0, _blend_rate(state) * delta))
	_apply(delta, state, speed_ratio, grounded)


func _advance_gait(delta: float, state: StringName, speed_ratio: float, grounded: bool) -> void:
	var cycling: bool = (
		grounded
		and speed_ratio > 0.02
		and (state == PlayerState.RUN or state == PlayerState.LAND)
	)
	if cycling:
		var rate: float = maxf(STRIDE_RATE_MIN, STRIDE_RATE_AT_SPEED * speed_ratio)
		_phase += rate * TAU * delta
	elif state == PlayerState.ROLL:
		# The roll spins the whole body forward once through its duration.
		_roll_spin += TAU * delta / maxf(0.1, _player.profile.roll_duration)
	else:
		_roll_spin = 0.0


## Maps a movement state to the pose it should be blending toward.
##
## `Run` is the only procedural one; everything else is an authored pose, because a
## discrete action wants a specific readable shape rather than a cycle.
func _target_pose(state: StringName, speed_ratio: float) -> Pose:
	match state:
		PlayerState.RUN:
			return _run_pose(speed_ratio)
		PlayerState.IDLE:
			return _pose_idle()
		PlayerState.JUMP:
			return _pose_air_rise()
		PlayerState.FALL:
			# Rising into a fall still reads as rising until the apex passes.
			return _pose_air_rise() if _player.velocity.y > 1.0 else _pose_air_fall()
		PlayerState.LAND:
			# Blend the landing beat back into the run cycle, so a landing at speed
			# does not stall the gait.
			var landing: Pose = _pose_land()
			if speed_ratio > 0.25:
				landing.blend_toward(_run_pose(speed_ratio), 0.55)
			return landing
		PlayerState.HARD_LANDING:
			return _pose_hard_landing()
		PlayerState.SLIDE:
			return _pose_slide()
		PlayerState.ROLL:
			return _pose_roll()
		PlayerState.VAULT:
			return _vault_pose()
		PlayerState.CLIMB:
			return _pose_climb()
		PlayerState.LEDGE_GRAB:
			return _pose_ledge_hang()
		PlayerState.WALL_RUN:
			return _pose_wall_run()
		PlayerState.DEATH:
			return _pose_death()
		_:
			return _pose_idle()


## Which vault shape to use. Read from the sensor rather than stored, so a vault
## that re-classifies mid-approach still shows the right silhouette.
func _vault_pose() -> Pose:
	var high: bool = (
		_player.sensor != null
		and _player.sensor.obstacle == ParkourSensor.Obstacle.HIGH_VAULT
	)
	return _pose_vault_high() if high else _pose_vault_low()


## Blend speed per state. Faster for committed actions, slower for settling ones.
##
## Tuned per state because one global rate cannot serve both: fast enough for a
## vault to read as decisive makes a landing look twitchy, and slow enough for a
## landing to settle makes a vault look like it is being dragged into position.
func _blend_rate(state: StringName) -> float:
	match state:
		PlayerState.VAULT, PlayerState.ROLL, PlayerState.SLIDE:
			return 26.0
		PlayerState.CLIMB, PlayerState.WALL_RUN, PlayerState.LEDGE_GRAB:
			return 20.0
		PlayerState.JUMP:
			return 16.0
		PlayerState.LAND, PlayerState.HARD_LANDING:
			return 18.0
		PlayerState.DEATH:
			return 8.0
		_:
			return 13.0


## The run cycle, built fresh each frame from the gait phase.
func _run_pose(speed_ratio: float) -> Pose:
	var swing: float = lerpf(7.0, 54.0, speed_ratio)
	var knee: float = lerpf(9.0, 80.0, speed_ratio)
	var arm: float = lerpf(5.0, 46.0, speed_ratio)

	var l: float = sin(_phase)
	var r: float = sin(_phase + PI)

	var p := _scratch
	# Positive = forward, so the leg is forward at the peak of its half-cycle.
	p.hip_l = l * deg_to_rad(swing)
	p.hip_r = r * deg_to_rad(swing)
	# Knees flex hardest on the rearward recovery half — that asymmetry is what makes
	# a run read as a run rather than a march. Negative because knees bend backwards.
	p.knee_l = -(deg_to_rad(knee) * maxf(0.0, -l) + deg_to_rad(8.0))
	p.knee_r = -(deg_to_rad(knee) * maxf(0.0, -r) + deg_to_rad(8.0))
	# Arms counter-swing: left arm opposes left leg.
	p.shoulder_l = -l * deg_to_rad(arm)
	p.shoulder_r = -r * deg_to_rad(arm)
	p.elbow_l = deg_to_rad(lerpf(14.0, 78.0, speed_ratio))
	p.elbow_r = p.elbow_l * 0.85
	p.torso = deg_to_rad(lerpf(3.0, 17.0, speed_ratio))
	p.root_pitch = 0.0
	# Two bobs per stride, since both feet plant per cycle.
	p.root_y = -absf(sin(_phase)) * 0.055 * speed_ratio
	p.squash = 0.0
	return p


func _apply(delta: float, state: StringName, speed_ratio: float, grounded: bool) -> void:
	# Z axis throughout — see the note on `Pose`. Rotating these about X swings the
	# limbs into the screen, where the side-view camera cannot see them.
	#
	# Limbs hang downward, so a positive Z rotation already swings them forward.
	_hip_l.rotation.z = _current.hip_l
	_hip_r.rotation.z = _current.hip_r
	_knee_l.rotation.z = _current.knee_l
	_knee_r.rotation.z = _current.knee_r
	_shoulder_l.rotation.z = _current.shoulder_l
	_shoulder_r.rotation.z = _current.shoulder_r
	_elbow_l.rotation.z = _current.elbow_l
	_elbow_r.rotation.z = _current.elbow_r

	# The torso points upward, so a forward lean is a negative Z rotation. Negated
	# here so poses can be authored with "positive = forward" throughout.
	_torso.rotation.z = -_current.torso

	# Whole-body attitude. In the air, pitch follows vertical velocity so rising and
	# falling read differently even before the pose finishes blending.
	var pitch: float = _current.root_pitch
	if not grounded and state != PlayerState.WALL_RUN and state != PlayerState.LEDGE_GRAB:
		pitch += deg_to_rad(clampf(-_player.velocity.y * 0.45, -12.0, 18.0))
	if state == PlayerState.ROLL:
		pitch += _roll_spin
	_root.rotation.z = -pitch

	var compress: float = _squash * 0.26
	_root.position.y = _current.root_y - compress
	_root.scale = Vector3(1.0 + compress * 0.5, 1.0 - compress, 1.0 + compress * 0.5)


func _on_landed(impact_speed: float, hard: bool) -> void:
	# Compression proportional to impact, so a small hop barely registers and a long
	# drop visibly hurts.
	var base: float = clampf(impact_speed / 30.0, 0.0, 1.0)
	_squash = maxf(_squash, base * (1.0 if hard else 0.55))


func _on_rolled(_impact_speed: float) -> void:
	_roll_spin = 0.0
