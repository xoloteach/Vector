class_name PlayerInput
extends Node

## Buffered input snapshot for the player controller.
##
## States never poll `Input` directly. Everything goes through here so that
## forgiveness features — jump buffering, coyote-compatible consumption,
## input lockout during recovery animations — exist in exactly one place and
## behave identically for every state.

## Horizontal intent, -1..1. Digital keys are read as a clean sign so there is
## no analogue ramp-up on keyboard.
var move_axis: float = 0.0

## True while the jump key is held, used for variable jump height.
var jump_held: bool = false

## True while the slide key is held, used to sustain slides.
var slide_held: bool = false

## Set when slide is freshly pressed; consumed like jump.
var _slide_buffer: float = 0.0

## Seconds remaining on a remembered jump press. Non-zero means "the player
## wants to jump as soon as it is legal".
var _jump_buffer: float = 0.0

var _buffer_time: float = 0.14

## While locked, all intent reads as neutral. Used by recovery states so a
## mashing player cannot cancel out of a hard landing.
var _lock_timer: float = 0.0


func configure(buffer_time: float) -> void:
	_buffer_time = buffer_time


## Sampled in `_physics_process`, not `_process`.
##
## The controller runs on the physics tick, so input has to be latched on the
## same clock. Sampling in `_process` means the buffer can be refilled or expire
## between two physics ticks, which loses presses at low frame rates and
## double-counts them at high ones. This was a real bug: jumps were being
## registered as held-then-released within a single tick.
func _physics_process(delta: float) -> void:
	_lock_timer = maxf(0.0, _lock_timer - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_slide_buffer = maxf(0.0, _slide_buffer - delta)

	if _lock_timer > 0.0:
		move_axis = 0.0
		jump_held = false
		slide_held = false
		return

	var axis: float = 0.0
	if Input.is_action_pressed("move_right"):
		axis += 1.0
	if Input.is_action_pressed("move_left"):
		axis -= 1.0
	move_axis = axis

	jump_held = Input.is_action_pressed("jump")
	slide_held = Input.is_action_pressed("slide")

	if Input.is_action_just_pressed("jump"):
		_jump_buffer = _buffer_time
	if Input.is_action_just_pressed("slide"):
		_slide_buffer = _buffer_time


## True if a jump press is pending. Does not consume it — call `consume_jump()`
## once the jump actually fires.
func has_jump() -> bool:
	return _jump_buffer > 0.0


func consume_jump() -> bool:
	if _jump_buffer <= 0.0:
		return false
	_jump_buffer = 0.0
	return true


func has_slide() -> bool:
	return _slide_buffer > 0.0


func consume_slide() -> bool:
	if _slide_buffer <= 0.0:
		return false
	_slide_buffer = 0.0
	return true


## Suppress all input for `duration` seconds and drop anything buffered.
func lock(duration: float) -> void:
	_lock_timer = maxf(_lock_timer, duration)
	_jump_buffer = 0.0
	_slide_buffer = 0.0
	move_axis = 0.0
	jump_held = false
	slide_held = false


func is_locked() -> bool:
	return _lock_timer > 0.0


## Drop buffered presses without locking. Used when a state consumes intent in a
## way that should not carry over.
func clear_buffers() -> void:
	_jump_buffer = 0.0
	_slide_buffer = 0.0
