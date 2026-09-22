class_name Autopilot
extends Node

## A bot that plays the level, for headless verification.
##
## This is the project's primary automated test. "The project compiles" and even
## "the scene boots" say nothing about whether the course is *completable* — and
## completability is the property most easily broken by a movement tuning change
## or a one-metre level edit. The autopilot answers that question on every run,
## in a few seconds, with no display attached.
##
## It drives the game through the real input system (`Input.action_press`) rather
## than by poking the controller, so it exercises the same path a human does:
## input buffering, coyote time, state transitions, collision. A bug that only
## appears through real input will still be caught.
##
## The bot is deliberately *not* frame-perfect. It jumps using the same
## information a player has — the gap-edge distance from the sensor — with a
## reaction margin. If the course can only be cleared by a machine, it is too
## hard, and this test should fail.

signal finished(report: Dictionary)

## Give up after this long. Generous enough for a slow route, short enough that a
## stuck runner fails fast.
@export var timeout_seconds: float = 90.0

## Jump when the edge of the current surface is this close. Late enough to use
## the full jump arc; early enough to survive a frame of latency.
@export var edge_jump_margin: float = 0.85

## Jump when an obstacle face is this close. Larger than the gap margin because
## clearing a solid object needs the jump to be *rising* by the time the body
## reaches its face, not merely airborne.
@export var obstacle_jump_margin: float = 1.6

## A gap narrower than this is a seam between blocks, not something to jump.
@export var min_gap_to_jump: float = 0.6

## Log a progress line this often.
@export var log_interval: float = 0.75

var _player: Player
var _level: Level
var _elapsed: float = 0.0
var _since_log: float = 0.0
var _done: bool = false

# Diagnostics gathered for the report.
var _max_x: float = -INF
var _states_seen: Dictionary[StringName, int] = {}
var _jump_count: int = 0
var _hard_landings: int = 0
var _stuck_for: float = 0.0
var _last_x: float = -INF
var _min_fps: float = INF


func setup(player: Player, level: Level) -> void:
	_player = player
	_level = level
	_player.died.connect(_on_died)
	_player.jumped.connect(func(_r: float) -> void: _jump_count += 1)
	_player.landed.connect(func(_s: float, hard: bool) -> void:
		if hard:
			_hard_landings += 1
	)
	_player.state_changed.connect(func(_from: StringName, to: StringName) -> void:
		_states_seen[to] = _states_seen.get(to, 0) + 1
	)
	Game.run_completed.connect(_on_completed)


func _physics_process(delta: float) -> void:
	if _done or _player == null:
		return

	_elapsed += delta
	_since_log += delta

	_track_progress(delta)

	if _elapsed >= timeout_seconds:
		_report(false, "timeout after %.1fs" % _elapsed)
		return

	_drive()

	if _since_log >= log_interval:
		_since_log = 0.0
		_log_line()


func _track_progress(delta: float) -> void:
	var x: float = _player.global_position.x
	_max_x = maxf(_max_x, x)
	# Frame rate is only meaningful with a renderer attached. Headless reports a
	# nominal value, so it is recorded but labelled as not-a-measurement.
	if DisplayServer.get_name() != "headless":
		var fps: float = Engine.get_frames_per_second()
		if fps > 0.0:
			_min_fps = minf(_min_fps, fps)

	# Detect a runner that is alive but going nowhere — a softlock. This is the
	# failure mode a human tester would catch in one second and a compile check
	# would never catch at all.
	if absf(x - _last_x) < 0.05:
		_stuck_for += delta
		if _stuck_for > 3.0:
			_report(false, "softlocked at x=%.1f y=%.1f state=%s" % [
				x, _player.global_position.y, _player.state_name()
			])
			return
	else:
		_stuck_for = 0.0
	_last_x = x


## How long the bot keeps the jump key down after committing. The controller
## reads a released key as "cut the jump short", so a bot that taps for one tick
## only ever produces minimum-height hops.
@export var jump_hold_time: float = 0.42

var _jump_down: bool = false
var _jump_hold_remaining: float = 0.0


## The bot's whole brain: always run right, jump when the sensor says the ground
## or a wall is about to interrupt that.
func _drive() -> void:
	# Held continuously. Edge-triggering is unnecessary for an axis.
	Input.action_press(&"move_right")

	var sensor: ParkourSensor = _player.sensor
	var want_jump: bool = false

	if _player.is_on_floor():
		# Gap ahead, and a real gap rather than a block seam.
		if sensor.edge_distance <= edge_jump_margin and sensor.gap_width >= min_gap_to_jump:
			want_jump = true
		# Something to clear that is taller than a step.
		elif (
			sensor.obstacle != ParkourSensor.Obstacle.NONE
			and sensor.obstacle != ParkourSensor.Obstacle.STEP
			and sensor.obstacle_distance <= obstacle_jump_margin
			and sensor.obstacle_height > _player.profile.step_up_height
		):
			want_jump = true

	_drive_jump_key(want_jump)


## Presses jump on the rising edge only, then holds for `jump_hold_time`.
##
## `Input.action_press` re-arms `is_action_just_pressed` on every call, so calling
## it each tick makes the buffer look like an infinite stream of fresh presses and
## the runner re-jumps the instant it touches anything.
func _drive_jump_key(want_jump: bool) -> void:
	if want_jump and not _jump_down:
		Input.action_press(&"jump")
		_jump_down = true
		_jump_hold_remaining = jump_hold_time
		return

	if _jump_down:
		_jump_hold_remaining -= get_physics_process_delta_time()
		if _jump_hold_remaining <= 0.0:
			Input.action_release(&"jump")
			_jump_down = false


func _log_line() -> void:
	var sensor: ParkourSensor = _player.sensor
	print("[bot] t=%5.2f x=%7.2f y=%6.2f vx=%5.1f %-12s edge=%s gap=%s obst=%s" % [
		_elapsed,
		_player.global_position.x,
		_player.global_position.y,
		_player.velocity.x,
		_player.state_name(),
		_fmt(sensor.edge_distance),
		_fmt(sensor.gap_width),
		sensor.obstacle_name(),
	])


func _fmt(value: float) -> String:
	return "inf" if value == INF else "%.2f" % value


# ------------------------------------------------------------------- conclusions

func _on_died(reason: String) -> void:
	_report(false, "died (%s) at x=%.1f y=%.1f" % [
		reason, _player.global_position.x, _player.global_position.y
	])


func _on_completed(elapsed: float) -> void:
	_report(true, "reached the finish in %.2fs" % elapsed)


func _report(success: bool, summary: String) -> void:
	if _done:
		return
	_done = true
	Input.action_release(&"move_right")
	Input.action_release(&"jump")

	var course_length: float = _level.course_length if _level != null else 0.0
	var report: Dictionary = {
		"success": success,
		"summary": summary,
		"elapsed": _elapsed,
		"max_x": _max_x,
		"course_length": course_length,
		"completion": (_max_x / course_length) if course_length > 0.0 else 0.0,
		"jumps": _jump_count,
		"hard_landings": _hard_landings,
		"min_fps": _min_fps,
		"states": _states_seen,
	}
	finished.emit(report)
