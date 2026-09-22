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
## Horizontal slice of the world the camera tries to keep visible, in metres.
##
## **Framing is driven by width, not distance.** A side-view runner lives or dies
## on how much track is visible ahead, and Godot's default `KEEP_HEIGHT` aspect
## handling gives none of that guarantee: it fixes the *vertical* field of view,
## so on a narrow screen the horizontal view collapses. On a portrait phone the
## runner filled the frame and roughly two metres of level were visible — not
## playable.
##
## Deriving distance from the desired width instead keeps the horizontal read
## consistent from ultrawide to portrait.
@export var target_view_width: float = 15.0

## Bounds on the derived distance.
##
## The lower bound stops an ultrawide screen from shoving the camera into the
## runner's face; the upper bound stops a portrait screen from pushing so far back
## that the character becomes an unreadable speck. Inside these bounds the width
## target is honoured exactly; outside them, width is sacrificed to keep the
## character legible, because an illegible character is the worse failure.
@export var min_view_distance: float = 9.0
@export var max_view_distance: float = 17.0

@export_group("Chase response")
## How much wider the view gets at full chase intensity, as a fraction.
##
## Cinematic *and* functional. At close range the pursuer sits behind the runner,
## which with normal look-ahead framing puts it off the left edge of the screen —
## so the single most urgent thing in the game becomes invisible exactly when it
## matters. Widening brings it back into frame, and the extra view also buys the
## player reaction time at the moment they most need it.
@export_range(0.0, 1.0) var threat_view_widening: float = 0.34

## How much of the forward look-ahead is given up at full intensity. Under threat
## the runner should sit closer to centre, because what is behind has become as
## important as what is ahead.
@export_range(0.0, 1.0) var threat_lead_reduction: float = 0.7

## Rate the framing shifts at. Slow on purpose: a camera that snaps outward on every
## intensity flicker is nauseating, and the chase's own pacing is already gradual.
@export var threat_response_speed: float = 1.1

## Resolved distance for the current viewport. Recomputed on resize.
var view_distance: float = 11.0

## Smoothed chase intensity, 0..1.
var _threat: float = 0.0
var _threat_target: float = 0.0

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
## Upward aim bias applied on tall/narrow screens, in metres.
var _cramped_lift: float = 0.0


func _ready() -> void:
	fov = fov_base
	if target == null:
		target = get_tree().get_first_node_in_group(&"player") as Node3D
	if target is Player:
		var p: Player = target
		p.landed.connect(_on_player_landed)
	set_as_top_level(true)

	_resolve_view_distance()
	get_viewport().size_changed.connect(_resolve_view_distance)


## Derives `view_distance` from the viewport aspect so the horizontal world extent
## stays close to `target_view_width` whatever shape the screen is.
##
## visible_width = 2 · distance · tan(fov/2) · aspect  ⇒  solve for distance.
func _resolve_view_distance() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var aspect: float = size.x / size.y
	var half_fov: float = tan(deg_to_rad(fov_base * 0.5))
	if is_zero_approx(half_fov) or is_zero_approx(aspect):
		return
	var wanted_width: float = target_view_width * (1.0 + threat_view_widening * _threat)
	var ideal: float = wanted_width / (2.0 * half_fov * aspect)
	view_distance = clampf(ideal, min_view_distance, max_view_distance * (1.0 + threat_view_widening))

	# Tall screens get the action raised out of the thumb zone. Scaled by how tall
	# the screen is, so a mildly narrow window is barely affected.
	var tallness: float = clampf((1.3 - aspect) / 0.8, 0.0, 1.0)
	_cramped_lift = tallness * view_distance * 0.115


## True on screens too narrow to frame the game properly, so the UI can suggest
## rotating rather than silently serving a bad view.
func is_aspect_cramped() -> bool:
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.y <= 0.0:
		return false
	return (size.x / size.y) < 1.15


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

	# Ease toward the reported chase intensity and re-derive framing from it.
	if not is_equal_approx(_threat, _threat_target):
		_threat = lerpf(_threat, _threat_target, _smooth(threat_response_speed, delta))
		_resolve_view_distance()

	var lead_scale: float = 1.0 - threat_lead_reduction * _threat
	var goal: Vector3 = target.global_position
	goal.x += (facing * lead_bias + signf(velocity_x) * look_ahead_max * speed_ratio) * lead_scale
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

	# On a cramped screen the runner would otherwise sit near the vertical centre
	# with the ground hidden behind the thumb controls. Biasing the aim upward
	# lifts the play line into the clear upper area of the display.
	if _cramped_lift > 0.0:
		global_position.y += _cramped_lift


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
	_threat = _threat_target
	_resolve_view_distance()


## Reports chase pressure, 0..1. Connected to `ChaseDirector.intensity_changed`.
func set_threat(intensity: float) -> void:
	_threat_target = clampf(intensity, 0.0, 1.0)
