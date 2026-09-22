class_name Player
extends CharacterBody3D

## The runner.
##
## 2.5D: the simulation is a 2D plane (X horizontal, Y vertical) rendered in 3D.
## Z is pinned to `plane_z` every tick so no amount of collision resolution can
## push the runner out of the play plane — that class of bug is impossible to
## debug from a screenshot, so it is designed out rather than watched for.
##
## This script owns *physics primitives and shared bookkeeping only*. All
## decisions about what the runner is doing live in `states/`. Sensing lives in
## `sensors/`. Keeping those three concerns apart is what stops this file from
## becoming the usual 2000-line player blob.

signal jumped(speed_ratio: float)
signal landed(impact_speed: float, hard: bool)
signal died(reason: String)
signal state_changed(from: StringName, to: StringName)

@export var profile: MovementProfile

## The Z plane gameplay is locked to. Scenery lives in front of and behind it.
@export var plane_z: float = 0.0

## How fast the visual mesh swings around when the runner reverses. Fast enough
## to feel responsive, slow enough that the turn is legible.
@export var visual_turn_speed: float = 16.0

# ---------------------------------------------------------------- child systems

var input: PlayerInput
var sensor: ParkourSensor
var machine: PlayerStateMachine
var visual: Node3D

# --------------------------------------------------------------- shared metrics

## -1 facing left, +1 facing right. States set this; the visual follows.
var facing: float = 1.0

## Seconds since the runner left the ground. Zero while grounded.
var airborne_time: float = 0.0

## Time remaining during which a jump is still legal after leaving a ledge.
var coyote_timer: float = 0.0

## Greatest downward speed reached during the current airborne period. Landing
## states read this to decide soft vs hard vs lethal, then reset it.
var peak_fall_speed: float = 0.0

## Y at which the current airborne period began, for drop-height logic.
var fall_start_y: float = 0.0

var is_dead: bool = false

## Set true by the level when the runner crosses the finish, so states stop
## fighting the outro.
var controls_disabled: bool = false

var _was_on_floor: bool = true
var _turn_visual_target: float = 1.0

## True once the current jump's height has been trimmed by an early release, so
## the cut cannot compound across ticks.
var _jump_cut_used: bool = false


func _ready() -> void:
	if profile == null:
		# A missing profile would otherwise fail deep inside a state with a
		# confusing nil error. Fall back to defaults and say so.
		profile = MovementProfile.new()
		push_warning("Player has no MovementProfile; using defaults.")

	input = PlayerInput.new()
	input.name = "PlayerInput"
	input.configure(profile.jump_buffer_time)
	add_child(input)

	visual = get_node_or_null("Visual") as Node3D

	sensor = get_node_or_null("ParkourSensor") as ParkourSensor
	if sensor == null:
		sensor = ParkourSensor.new()
		sensor.name = "ParkourSensor"
		add_child(sensor)
	sensor.setup(self)

	machine = get_node_or_null("StateMachine") as PlayerStateMachine
	if machine == null:
		push_error("Player is missing its StateMachine child; movement is dead.")
		return
	machine.state_changed.connect(_on_state_changed)

	# Snapping keeps the runner glued to the ground over small undulations and
	# makes the step-up trick below resolve in a single tick.
	floor_snap_length = 0.55
	floor_max_angle = deg_to_rad(52.0)
	floor_stop_on_slope = true
	slide_on_ceiling = false
	max_slides = 5

	global_position.z = plane_z
	_turn_visual_target = facing

	machine.setup(self, PlayerState.IDLE)


func _physics_process(delta: float) -> void:
	if controls_disabled:
		# Still simulate gravity so the runner settles instead of hovering.
		apply_gravity(delta)
		apply_ground_friction(delta, 1.6)
		move()
		return

	sensor.poll()
	_pre_move_bookkeeping(delta)
	machine.physics_update(delta)
	_post_move_bookkeeping(delta)


func _process(delta: float) -> void:
	_update_visual_facing(delta)


# ---------------------------------------------------------------- bookkeeping

func _pre_move_bookkeeping(delta: float) -> void:
	if is_on_floor():
		airborne_time = 0.0
		coyote_timer = profile.coyote_time
	else:
		if _was_on_floor:
			# Just left the ground: remember where from, for drop-height checks.
			fall_start_y = global_position.y
		airborne_time += delta
		coyote_timer = maxf(0.0, coyote_timer - delta)
		peak_fall_speed = maxf(peak_fall_speed, -velocity.y)


func _post_move_bookkeeping(_delta: float) -> void:
	_was_on_floor = is_on_floor()
	Game.report_progress(global_position.x)

	if global_position.y < profile.kill_plane_y and not is_dead:
		kill(Game.FAIL_FELL)


func _on_state_changed(from: StringName, to: StringName) -> void:
	state_changed.emit(from, to)


func _update_visual_facing(delta: float) -> void:
	if visual == null:
		return
	_turn_visual_target = facing
	# Interpolate the Y rotation toward the facing direction. Using the angle
	# rather than scale.x avoids mirroring normals and breaking lighting.
	var target_yaw: float = 0.0 if _turn_visual_target >= 0.0 else PI
	visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, minf(1.0, visual_turn_speed * delta))


# --------------------------------------------------------- movement primitives

## Advances the body. Every state must call this exactly once per tick (or
## deliberately skip it, e.g. while frozen on a ledge).
func move() -> void:
	velocity.z = 0.0
	move_and_slide()
	# Hard-pin the play plane. Collision resolution against angled geometry can
	# otherwise introduce a slow Z drift that is invisible until the camera
	# framing goes subtly wrong.
	global_position.z = plane_z


func apply_gravity(delta: float) -> void:
	velocity.y -= profile.gravity_for(velocity.y) * delta
	velocity.y = maxf(velocity.y, -profile.max_fall_speed)


## Accelerates horizontally toward `axis * max_run_speed * speed_scale`.
## `accel_scale` lets air states reduce control authority without duplicating
## the acceleration maths.
func apply_horizontal(delta: float, axis: float, accel_scale: float = 1.0, speed_scale: float = 1.0) -> void:
	var target: float = axis * profile.max_run_speed * speed_scale
	var accel: float = profile.ground_acceleration
	# Reversing direction gets the higher deceleration so turns feel decisive.
	if not is_zero_approx(axis) and signf(axis) != signf(velocity.x) and not is_zero_approx(velocity.x):
		accel = profile.ground_turn_deceleration
	velocity.x = move_toward(velocity.x, target, accel * accel_scale * delta)


func apply_ground_friction(delta: float, scale: float = 1.0) -> void:
	velocity.x = move_toward(velocity.x, 0.0, profile.ground_friction * scale * delta)


func apply_air_friction(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, profile.air_friction * delta)


## Fires a jump. `vertical_scale` trims height for contextual jumps (wall kicks,
## ledge hops) without hard-coding numbers in those states.
func do_jump(vertical_scale: float = 1.0) -> void:
	var v: float = profile.jump_velocity_at_speed(speed_ratio()) * vertical_scale
	velocity.y = v
	coyote_timer = 0.0
	_jump_cut_used = false
	reset_fall_metrics()
	input.consume_jump()
	jumped.emit(speed_ratio())


## Cuts a rising jump short when the player releases the key, for variable
## height. Safe to call every tick.
##
## Single-shot per jump. Applying the multiplier every tick compounds it — at 60
## Hz a 0.45 factor becomes 0.45^n and the jump collapses to a hop within four
## frames. That bug made every jump about 0.3 m tall.
func try_jump_cut() -> void:
	if _jump_cut_used:
		return
	if velocity.y > 0.0 and not input.jump_held:
		velocity.y *= profile.jump_cut_factor
		_jump_cut_used = true


## True when jumping is legal: grounded, or inside the coyote window.
func can_jump() -> bool:
	return is_on_floor() or coyote_timer > 0.0


## Number of lift heights tried when resolving a step. Four is enough resolution
## that the vertical pop is imperceptible, and cheap enough to run every tick.
const STEP_PROBE_COUNT: int = 4

## Climbs kerbs and small lips without leaving the run state, so tiny geometry
## never interrupts flow. Returns true if a step was taken.
##
## Lifts by the *smallest* amount that clears, not by the maximum allowance.
## Always lifting the full `step_up_height` throws the runner above a low kerb
## and drops it back, producing a visible hop and a spurious Fall transition on
## every pavement edge.
func try_step_up() -> bool:
	if not is_on_floor() or absf(velocity.x) < 0.5:
		return false

	var forward := Vector3(signf(velocity.x) * maxf(0.22, absf(velocity.x) * 0.02), 0.0, 0.0)
	if not test_move(global_transform, forward):
		return false  # nothing in the way

	var max_step: float = profile.step_up_height
	for i: int in range(1, STEP_PROBE_COUNT + 1):
		var lift: float = max_step * float(i) / float(STEP_PROBE_COUNT)
		var lifted: Transform3D = global_transform.translated(Vector3.UP * lift)
		if not test_move(lifted, forward):
			global_position.y += lift
			return true

	return false  # a real wall, not a step — let the parkour system decide


func reset_fall_metrics() -> void:
	peak_fall_speed = 0.0
	fall_start_y = global_position.y


# ------------------------------------------------------------------- accessors

func horizontal_speed() -> float:
	return absf(velocity.x)


## Current speed as a 0..1 fraction of top speed. Used for animation blending,
## camera zoom, jump height bonus and FX intensity.
func speed_ratio() -> float:
	return clampf(horizontal_speed() / profile.max_run_speed, 0.0, 1.0)


## How far the runner has fallen from the start of this airborne period.
func drop_height() -> float:
	return maxf(0.0, fall_start_y - global_position.y)


func state_name() -> StringName:
	return machine.current_name if machine != null else &""


# ----------------------------------------------------------------------- death

func kill(reason: String) -> void:
	if is_dead:
		return
	if machine != null and machine.has_state(PlayerState.DEATH):
		machine.transition_to(PlayerState.DEATH, {"reason": reason})
	else:
		is_dead = true
		died.emit(reason)
		Game.fail_run(reason)
