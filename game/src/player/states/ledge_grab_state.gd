extends PlayerState

## Catching a ledge on the way down, then pulling up.
##
## Pure anti-frustration. A jump that falls a little short of a roof is the most
## common death in a game built out of gaps, and whether that feels fair depends
## almost entirely on whether the character *tried* to grab the edge it visibly
## touched. Catching the lip converts a large share of near-misses into recoveries
## without making any of the jumps themselves easier.
##
## Two phases in one state — a brief hang, then a scripted pull-up — because they
## are never independently reachable and splitting them would add a transition
## whose only effect is another place for the animation to hitch.
##
## The hang **times out**. A hang the player has to escape manually is a state they
## can sit in forever, and on touch it is not obvious what to press. Automatic
## pull-up also keeps the move reading as recovery rather than as a rest stop.

enum Phase { HANG, CLIMB }

var _phase: Phase = Phase.HANG
var _arc := TraversalArc.new()
var _ledge: Vector3 = Vector3.ZERO
var _dir: float = 1.0


func enter(_previous: StringName, _data: Dictionary) -> void:
	var sensor: ParkourSensor = player.sensor

	_phase = Phase.HANG
	_ledge = sensor.ledge_point
	_dir = signf(player.velocity.x)
	if is_zero_approx(_dir):
		_dir = player.facing
	player.facing = _dir

	# Freeze completely. The catch has to read as an impact absorbed, and any
	# residual drift would slide the runner along the wall face.
	player.velocity = Vector3.ZERO

	# Snap to a consistent hang position so the pose is identical every time,
	# regardless of the trajectory that arrived here.
	#
	# Hung so the *hands* sit at the lip, which means the head ends up just below it.
	# A shallower offset left the runner's shoulders above the ledge it was supposedly
	# hanging from, which read as floating beside the wall rather than gripping it.
	var hang_y: float = _ledge.y - ParkourSensor.BODY_HEIGHT * 0.97
	player.set_scripted_position(Vector3(
		_ledge.x - _dir * (ParkourSensor.BODY_RADIUS + 0.04),
		hang_y,
		player.plane_z
	))

	# The catch cancels the fall, so the impact must be discarded — otherwise the
	# landing at the top of the pull-up would be resolved against the speed of the
	# fall that was just survived, and a saved jump would kill the player.
	player.reset_fall_metrics()
	player.grabbed_ledge.emit()


func physics_update(delta: float) -> void:
	match _phase:
		Phase.HANG:
			_update_hang(delta)
		Phase.CLIMB:
			_update_climb(delta)


func _update_hang(_delta: float) -> void:
	# Held in place: no gravity, no movement.
	player.velocity = Vector3.ZERO

	# Voluntary drop. Asking to go low is the natural "let go", and it lets a
	# player who grabbed a ledge they did not want get off it immediately.
	if player.input.slide_held or player.input.has_slide():
		player.input.consume_slide()
		# Push clear of the wall so the release does not re-grab the same ledge.
		player.velocity = Vector3(-_dir * 1.8, -1.0, 0.0)
		player.reset_fall_metrics()
		transition_to(FALL)
		return

	var ready: bool = time_in_state() >= player.profile.ledge_hang_time
	# Jump pulls up early, so a confident player never waits for the timeout.
	if ready or player.input.has_jump():
		player.input.consume_jump()
		_begin_climb()


func _begin_climb() -> void:
	_phase = Phase.CLIMB
	var start: Vector3 = player.global_position
	var end := Vector3(
		_ledge.x + _dir * (ParkourSensor.BODY_RADIUS + 0.28),
		_ledge.y + 0.02,
		player.plane_z
	)
	_arc.start(start, end, 0.14, player.profile.ledge_climb_duration, 1.2)


func _update_climb(delta: float) -> void:
	player.set_scripted_position(_arc.advance(delta))
	player.velocity = Vector3.ZERO

	if not _arc.finished():
		return

	player.velocity = Vector3(_dir * player.profile.ledge_exit_speed, 0.0, 0.0)
	player.reset_fall_metrics()
	transition_to(RUN if player.is_on_floor() else FALL)


func debug_label() -> String:
	return "LedgeGrab(%s)" % ("hang" if _phase == Phase.HANG else "climb")
