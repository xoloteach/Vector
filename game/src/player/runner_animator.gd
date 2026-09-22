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

	## Reads a field by name, so tooling can iterate the bindings generically.
	## Not called `get` — that shadows `Object.get` and fails to compile.
	func angle_for(field: String) -> float:
		match field:
			"hip_l": return hip_l
			"hip_r": return hip_r
			"knee_l": return knee_l
			"knee_r": return knee_r
			"shoulder_l": return shoulder_l
			"shoulder_r": return shoulder_r
			"elbow_l": return elbow_l
			"elbow_r": return elbow_r
			_: return 0.0

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

## Looks up an authored pose by state name, for tooling (the pose sheet).
## Returns null for states with no single authored pose, such as `Run`.
static func pose_for_state(state: StringName) -> Pose:
	match state:
		PlayerState.IDLE, PlayerState.RUN:
			return _pose_idle()
		PlayerState.JUMP:
			return _pose_air_rise()
		PlayerState.FALL:
			return _pose_air_fall()
		PlayerState.LAND:
			return _pose_land()
		PlayerState.HARD_LANDING:
			return _pose_hard_landing()
		PlayerState.SLIDE:
			return _pose_slide()
		PlayerState.ROLL:
			return _pose_roll()
		PlayerState.VAULT:
			return _pose_vault_low()
		PlayerState.CLIMB:
			return _pose_climb()
		PlayerState.LEDGE_GRAB:
			return _pose_ledge_hang()
		PlayerState.WALL_RUN:
			return _pose_wall_run()
		PlayerState.DEATH:
			return _pose_death()
		_:
			return null


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
#
# Poses a real `Skeleton3D` from the Blender-generated GLB. The box rig this
# replaced is gone; the pose data and blending carried over untouched, which was
# the point of separating them from the mesh in the first place.

## Maps a pose field to the bone it drives.
const BONE_BINDINGS: Dictionary[String, String] = {
	"hip_l": "ThighL",
	"hip_r": "ThighR",
	"knee_l": "ShinL",
	"knee_r": "ShinR",
	"shoulder_l": "UpperArmL",
	"shoulder_r": "UpperArmR",
	"elbow_l": "ForearmL",
	"elbow_r": "ForearmR",
}

## Bone that carries the torso lean. The lean is split across the spine chain so
## it curves rather than hinging at one joint.
const SPINE_BONES: PackedStringArray = ["Spine", "Chest"]

var _player: Player
var _skeleton: Skeleton3D

## Bone index per pose field, resolved once.
var _bone_index: Dictionary[String, int] = {}
## Rotation axis for each bone, in that bone's own local space, corresponding to
## the character-space Z axis. See `_resolve_axis` for why this is necessary.
var _bone_axis: Dictionary[String, Vector3] = {}
## Each bone's rest rotation. Must be composed with the pose rotation — see
## `_pose_bone`.
var _bone_rest: Dictionary[String, Quaternion] = {}
var _spine_index: Array[int] = []
var _spine_axis: Array[Vector3] = []
var _spine_rest: Array[Quaternion] = []

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

	_skeleton = _find_skeleton(self)
	if _skeleton == null:
		push_error("RunnerAnimator found no Skeleton3D. Run ./scripts/build_assets.sh.")
		return

	_bind_bones()
	_apply_materials()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _bind_bones() -> void:
	for field: String in BONE_BINDINGS:
		var bone_name: String = BONE_BINDINGS[field]
		var index: int = _skeleton.find_bone(bone_name)
		if index < 0:
			push_warning("Runner skeleton has no bone '%s'." % bone_name)
			continue
		_bone_index[field] = index
		_bone_axis[field] = _resolve_axis(index)
		_bone_rest[field] = _rest_rotation(index)

	for bone_name: String in SPINE_BONES:
		var index: int = _skeleton.find_bone(bone_name)
		if index < 0:
			continue
		_spine_index.append(index)
		_spine_axis.append(_resolve_axis(index))
		_spine_rest.append(_rest_rotation(index))


static func rest_rotation_of(skeleton: Skeleton3D, bone_index: int) -> Quaternion:
	return skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()


func _rest_rotation(bone_index: int) -> Quaternion:
	return rest_rotation_of(_skeleton, bone_index)


## Finds the axis, in a bone's local space, that rotates it about the character's
## Z axis.
##
## Necessary because poses are authored in character space ("swing this limb
## forward") while `set_bone_pose_rotation` takes a rotation in the bone's own
## space, and the two differ per bone depending on how the exporter oriented it.
## Hard-coding a local axis would work for the legs and silently mangle the arms.
##
## Derivation: a bone's posed global basis is `B · R(a, θ)` where `B` is its global
## rest basis. The conjugation identity `B·R(a,θ) = R(B·a, θ)·B` means that to get a
## rotation of `θ` about character-space `Z`, we need `B·a = Z`, hence
## `a = B⁻¹ · Z`.
##
## Using the *rest* basis is deliberate: the live basis includes the parent's pose,
## so a child's rotation is automatically carried along by its parent. That is
## exactly the forward-kinematic behaviour wanted — a knee bend is relative to the
## thigh, not to the world.
func _resolve_axis(bone_index: int) -> Vector3:
	var rest_basis: Basis = _skeleton.get_bone_global_rest(bone_index).basis
	return (rest_basis.inverse() * Vector3(0.0, 0.0, 1.0)).normalized()


## Replaces the GLB's materials with tuned Godot ones.
##
## Art direction needs a fast iteration loop, and re-running Blender to adjust a
## value is not one. Blender exports placeholder colours under known names; the real
## look is defined here.
func _apply_materials() -> void:
	var mesh_instance: MeshInstance3D = _find_mesh(self)
	if mesh_instance == null or mesh_instance.mesh == null:
		return

	# Three value steps inside the silhouette. The figure still reads as one dark
	# shape, but limb positions are legible against the torso — without this the
	# whole figure merges into a single rectangle and no pose is distinguishable.
	var by_name: Dictionary[String, StandardMaterial3D] = {
		"suit": _character_material(Color(0.046, 0.054, 0.072)),
		"trim": _character_material(Color(0.094, 0.105, 0.132)),
		"accent": _character_material(Color(0.88, 0.48, 0.14)),
	}

	for surface: int in mesh_instance.mesh.get_surface_count():
		var source: Material = mesh_instance.mesh.surface_get_material(surface)
		var key: String = source.resource_name if source != null else ""
		for name: String in by_name:
			if key.begins_with(name):
				mesh_instance.set_surface_override_material(surface, by_name[name])
				break


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh(child)
		if found != null:
			return found
	return null


func _character_material(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.74
	mat.metallic = 0.04
	# A rim term traces the figure's outline with a faint cool highlight, so its
	# edges stay visible on any backdrop without lifting the body value and losing
	# the silhouette. Cheap: a per-pixel fresnel, supported on compatibility.
	mat.rim_enabled = true
	mat.rim = 0.66
	mat.rim_tint = 0.22
	return mat


func _find_player() -> Player:
	var node: Node = get_parent()
	while node != null:
		if node is Player:
			return node
		node = node.get_parent()
	push_warning("RunnerAnimator could not find its Player ancestor.")
	return null


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


func _apply(_delta: float, state: StringName, _speed_ratio: float, grounded: bool) -> void:
	if _skeleton == null:
		return

	# Each bone rotates about the axis that corresponds to the character's Z axis in
	# that bone's own local space — see `_resolve_axis`. Poses stay authored in
	# character space ("swing this limb forward") and the per-bone conversion happens
	# here.
	#
	# Limbs hang downward, so a positive rotation swings them forward.
	_pose_bone("hip_l", _current.hip_l)
	_pose_bone("hip_r", _current.hip_r)
	_pose_bone("knee_l", _current.knee_l)
	_pose_bone("knee_r", _current.knee_r)
	_pose_bone("shoulder_l", _current.shoulder_l)
	_pose_bone("shoulder_r", _current.shoulder_r)
	_pose_bone("elbow_l", _current.elbow_l)
	_pose_bone("elbow_r", _current.elbow_r)

	# The spine points upward, so a forward lean is a negative rotation. Negated here
	# so poses stay authored "positive = forward" throughout. Split across the chain
	# so the back curves instead of hinging at a single joint.
	var per_joint: float = -_current.torso / maxf(1.0, float(_spine_index.size()))
	for i: int in _spine_index.size():
		_skeleton.set_bone_pose_rotation(
			_spine_index[i], _spine_rest[i] * Quaternion(_spine_axis[i], per_joint)
		)

	# Whole-body attitude, applied to this node rather than to a bone: it is a
	# transform of the entire figure, and expressing it as a root-bone rotation would
	# make the roll's full revolution fight the skinning.
	var pitch: float = _current.root_pitch
	if not grounded and state != PlayerState.WALL_RUN and state != PlayerState.LEDGE_GRAB:
		pitch += deg_to_rad(clampf(-_player.velocity.y * 0.45, -12.0, 18.0))
	if state == PlayerState.ROLL:
		pitch += _roll_spin
	rotation.z = -pitch

	var compress: float = _squash * 0.26
	position.y = _current.root_y - compress
	scale = Vector3(1.0 + compress * 0.5, 1.0 - compress, 1.0 + compress * 0.5)


## Rotates a bone by `angle` about the character's Z axis, from its rest pose.
##
## The rest rotation must be composed in. `set_bone_pose_rotation` sets the bone's
## **absolute** local rotation, it does not add to the rest — so passing the delta
## alone silently discards the bone's rest orientation. Every limb then snapped to
## the skeleton's default axis and pointed straight *up*: the foot bone ended up at
## y ≈ 1.82 instead of 0.06, level with the head. From the outside that looked like
## a broken model or a bad export, and it cost two diagnostic passes to localise. The
## numbers in `pose_sheet.gd` are what finally identified it.
func _pose_bone(field: String, angle: float) -> void:
	if not _bone_index.has(field):
		return
	_skeleton.set_bone_pose_rotation(
		_bone_index[field],
		_bone_rest[field] * Quaternion(_bone_axis[field], angle)
	)


func _on_landed(impact_speed: float, hard: bool) -> void:
	# Compression proportional to impact, so a small hop barely registers and a long
	# drop visibly hurts.
	var base: float = clampf(impact_speed / 30.0, 0.0, 1.0)
	_squash = maxf(_squash, base * (1.0 if hard else 0.55))


func _on_rolled(_impact_speed: float) -> void:
	_roll_spin = 0.0
