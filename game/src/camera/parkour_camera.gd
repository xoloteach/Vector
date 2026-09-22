class_name ParkourCamera
extends Camera3D

## Side-view framing rig.
##
## The camera's job in a parkour game is not to follow the player — it is to
## show the player what is about to happen. Everything here serves readability:
##
##  - **Look-ahead** shifts framing in the direction of travel proportionally to
##    speed, so the faster you go the further ahead you can see. Without it, a
##    fast runner is always looking at an obstacle too late to react.
##  - **Vertical deadzone + asymmetric smoothing** stops the camera pumping on
##    every small hop, while still following real height changes. Rising is
##    tracked lazily (you are about to come back down); falling is tracked
##    quickly (you need to see the landing).
##  - **Speed pull-back** widens the view slightly at top speed, which reads as
##    acceleration even when the speed number is constant.
##  - **Impact shake** sells weight on hard landings without obscuring anything.

@export var target: Node3D

@export_group("Framing")
## Distance from the play plane.
##
## Sized from the character, not from the level. At 42° FOV this shows about
## 8.4 m of height, which puts the 1.8 m runner at roughly 21% of frame height —
## large enough that limb articulation, lean and landing compression are all
## legible. The first version sat at 15 m, and the runner was a ~90 px blob that
## no critic could read; being able to see more of the level ahead is worth
## nothing if the thing you are steering is illegible.
@export var view_distance: float = 11.0

## Height above the runner's feet the camera aims at. Slightly above mid-body, so
## the ground line sits below centre and the space the runner is moving into gets
## the upper two-thirds of the frame.
@export var height_offset: float = 1.15

## Horizontal look-ahead at full speed, metres. Small, because the view is now
## narrow: the visible width is ~15 m, so a large offset shoves the runner into
## the corner rather than revealing useful information.
@export var look_ahead_max: float = 2.0

## Constant framing bias in the facing direction. Combined with look-ahead this
## settles the runner around 30% in from the leading edge at top speed.
@export var lead_bias: float = 1.0

@export_group("Smoothing")
@export var horizontal_smoothing: float = 6.0
## Vertical movement inside this band is ignored, killing hop-pumping. Scaled
## down along with the tighter framing.
@export var vertical_deadzone: float = 0.85
@export var vertical_smoothing_up: float = 3.2
@export var vertical_smoothing_down: float = 7.0

@export_group("Speed response")
@export var fov_base: float = 42.0
## Widened only modestly at speed. A big FOV swing reads as acceleration but it
## also shrinks the character, which undoes the framing work above.
@export var fov_at_speed: float = 46.0
@export var fov_smoothing: float = 2.5

@export_group("Impact")
@export var shake_decay: float = 7.0
@export var shake_max_offset: float = 0.35

var _focus: Vector3 = Vector3.ZERO
var _shake: float = 0.0
var _initialised: bool = false


func _ready() -> void:
	fov = fov_base
	if target == null:
		target = get_tree().get_first_node_in_group(&"player") as Node3D
	if target is Player:
		var p: Player = target
		p.landed.connect(_on_player_landed)
	set_as_top_level(true)


func _physics_process(delta: float) -> void:
	if target == null:
		return

	var speed_ratio: float = 0.0
	var velocity_x: float = 0.0
	var facing: float = 1.0
	if target is Player:
		var p: Player = target
		speed_ratio = p.speed_ratio()
		velocity_x = p.velocity.x
		facing = p.facing

	var goal: Vector3 = target.global_position
	goal.x += facing * lead_bias + signf(velocity_x) * look_ahead_max * speed_ratio
	goal.y += height_offset

	if not _initialised:
		_focus = goal
		_initialised = true

	# Horizontal: straightforward exponential chase.
	_focus.x = lerpf(_focus.x, goal.x, _smooth(horizontal_smoothing, delta))

	# Vertical: only react outside the deadzone, and react faster downward.
	var dy: float = goal.y - _focus.y
	if absf(dy) > vertical_deadzone:
		var excess: float = dy - signf(dy) * vertical_deadzone
		var rate: float = vertical_smoothing_down if dy < 0.0 else vertical_smoothing_up
		_focus.y += excess * _smooth(rate, delta)

	_focus.z = target.global_position.z

	var shake_offset := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - shake_decay * delta)
		var amount: float = _shake * shake_max_offset
		shake_offset = Vector3(randf_range(-amount, amount), randf_range(-amount, amount), 0.0)

	global_position = Vector3(_focus.x, _focus.y, _focus.z + view_distance) + shake_offset
	rotation = Vector3.ZERO

	var target_fov: float = lerpf(fov_base, fov_at_speed, speed_ratio)
	fov = lerpf(fov, target_fov, _smooth(fov_smoothing, delta))


## Frame-rate independent exponential smoothing factor.
func _smooth(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


func _on_player_landed(impact_speed: float, hard: bool) -> void:
	if not hard:
		# Soft landings get a whisper of shake, proportional to the drop.
		_shake = maxf(_shake, clampf(impact_speed / 60.0, 0.0, 0.25))
		return
	_shake = 1.0


## Immediately reframe without smoothing. Used after a respawn so the camera does
## not sweep across the level.
func snap_to_target() -> void:
	_initialised = false
	_shake = 0.0
