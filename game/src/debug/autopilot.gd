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

## Chase telemetry. Recorded so the fairness contract is *measured* rather than
## assumed: a competent run must keep the pursuer at arm's length the whole way.
var _chase_min_distance: float = INF
var _chase_max_distance: float = 0.0
var _chase_peak_intensity: float = 0.0

## When true the bot deliberately stands still, to verify the chase can actually
## kill. A pursuer that never catches anyone is scenery.
@export var stall_test: bool = false
## How long to run before stalling, so the drone is at its normal trailing distance
## when the test begins.
@export var stall_after: float = 4.0


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

	_track_chase()

	# Stall test: stop dead and let the pursuer close. Softlock detection has to be
	# suspended, because standing still is the whole point of the test.
	if stall_test and _elapsed >= stall_after:
		Input.action_release(&"move_right")
		Input.action_release(&"jump")
		_jump_down = false
		if _elapsed >= timeout_seconds:
			_report(false, "stall test: never caught after %.1fs" % _elapsed)
		return

	_track_progress(delta)

	if _elapsed >= timeout_seconds:
		_report(false, "timeout after %.1fs" % _elapsed)
		return

	_drive()

	if _since_log >= log_interval:
		_since_log = 0.0
		_log_line()


func _track_chase() -> void:
	if _level == null or _level.pursuer == null or _level.director == null:
		return
	var distance: float = _player.global_position.x - _level.pursuer.global_position.x
	_chase_min_distance = minf(_chase_min_distance, distance)
	_chase_max_distance = maxf(_chase_max_distance, distance)
	_chase_peak_intensity = maxf(_chase_peak_intensity, _level.director.intensity())


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
var _slide_down: bool = false


## Falling faster than this, the bot goes low to convert the landing into a roll.
@export var roll_arm_fall_speed: float = 20.0

## The bot's whole brain — deliberately almost empty.
##
## It runs right, jumps at gaps, and goes low when falling hard. It does **not**
## decide to vault, slide, mantle, wall-run or catch ledges; those have to be chosen
## by `TraversalPlanner` from the same sensor data a player would be reacting to.
##
## That restriction is the test. Earlier versions of this bot also jumped at any
## obstacle taller than a step, which meant plain jumping could paper over a
## contextual system that did not work. Now, if the course completes, the traversal
## system genuinely handles obstacles on its own; if the bot stalls at a crate, it
## does not. The level is built with geometry for every move precisely so this
## check has teeth.
func _drive() -> void:
	# Held continuously. Edge-triggering is unnecessary for an axis.
	Input.action_press(&"move_right")

	var sensor: ParkourSensor = _player.sensor

	# Something tall dead ahead is the traversal system's problem, not a gap. Without
	# this check the bot jumps at flush risers and walls, because the downward edge
	# march sees no floor beyond them and reports a bottomless gap — and a jump into
	# a wall face kills the horizontal speed that the mantle and wall-run both need.
	var obstacle_ahead: bool = (
		(
			sensor.obstacle == ParkourSensor.Obstacle.CLIMB
			or sensor.obstacle == ParkourSensor.Obstacle.WALL
		)
		and sensor.obstacle_distance <= 2.0
	)

	# Gaps are the player's job, so they are the bot's job. A real gap, not a seam
	# between two adjacent blocks.
	var want_jump: bool = (
		_player.is_on_floor()
		and not obstacle_ahead
		and sensor.edge_distance <= edge_jump_margin
		and sensor.gap_width >= min_gap_to_jump
	)
	_drive_jump_key(want_jump)

	# Arm a roll on a heavy descent. Timing an input to an impact is a skill the
	# game asks of the player, so the bot has to demonstrate it is achievable.
	var want_low: bool = not _player.is_on_floor() and _player.velocity.y < -roll_arm_fall_speed
	if want_low and not _slide_down:
		Input.action_press(&"slide")
		_slide_down = true
	elif not want_low and _slide_down:
		Input.action_release(&"slide")
		_slide_down = false


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
	# In a stall test, being caught *is* the pass condition.
	if stall_test and reason == Game.FAIL_CAUGHT:
		_report(true, "stall test: caught after %.1fs of standing still" % (
			_elapsed - stall_after
		))
		return
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
	Input.action_release(&"slide")
	_jump_down = false
	_slide_down = false

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
		"chase_min_distance": _chase_min_distance,
		"chase_max_distance": _chase_max_distance,
		"chase_peak_intensity": _chase_peak_intensity,
		"stall_test": stall_test,
	}
	finished.emit(report)
