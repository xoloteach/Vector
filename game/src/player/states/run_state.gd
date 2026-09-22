extends PlayerState

## Grounded locomotion — the state the runner spends most of its life in.
##
## Run is intentionally greedy: it absorbs small steps itself and hands off to a
## dedicated state only when something genuinely needs a different animation and
## different physics. Every unnecessary state transition is a place where flow
## can visibly hitch, so the bar for leaving Run is high.


func physics_update(delta: float) -> void:
	var axis: float = player.input.move_axis

	if not is_zero_approx(axis):
		player.facing = signf(axis)
		player.apply_horizontal(delta, axis)
	else:
		player.apply_ground_friction(delta)

	player.apply_gravity(delta)

	# Kerbs and lips get climbed silently so flow is never interrupted by
	# geometry the player would not even register as an obstacle.
	player.try_step_up()

	player.move()

	if player.input.has_jump() and player.can_jump():
		transition_to(JUMP)
		return

	if not player.is_on_floor():
		# Leaving the ground without jumping: coyote time is already running, so
		# Fall will still honour a late jump press.
		transition_to(FALL)
		return

	if is_zero_approx(axis) and player.horizontal_speed() < player.profile.idle_speed_threshold:
		transition_to(IDLE)
