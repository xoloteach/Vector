extends PlayerState

## A soft landing. Exists purely to give the animation system a beat of
## compression on contact — it costs the player nothing.
##
## This state must never feel like a stall. It keeps full horizontal control, it
## does not scrub speed, and a buffered jump fires out of it on the first tick,
## which is what makes landing-into-jump chains feel continuous.

## How long the landing beat lasts before returning to normal locomotion.
const DURATION: float = 0.1


func enter(_previous: StringName, data: Dictionary) -> void:
	var impact: float = float(data.get("impact", 0.0))
	player.landed.emit(impact, false)
	player.reset_fall_metrics()


func physics_update(delta: float) -> void:
	var axis: float = player.input.move_axis
	if not is_zero_approx(axis):
		player.facing = signf(axis)
		player.apply_horizontal(delta, axis)
	else:
		# Slightly stronger friction than normal: the contact reads as absorbing
		# the drop rather than skating away from it.
		player.apply_ground_friction(delta, 1.25)

	player.apply_gravity(delta)
	player.move()

	# A jump buffered during the fall fires immediately — this is the whole
	# reason landings do not interrupt flow.
	if player.input.has_jump() and player.can_jump():
		transition_to(JUMP)
		return

	if not player.is_on_floor():
		transition_to(FALL)
		return

	if time_in_state() >= DURATION:
		if is_zero_approx(axis) and player.horizontal_speed() < player.profile.idle_speed_threshold:
			transition_to(IDLE)
		else:
			transition_to(RUN)
