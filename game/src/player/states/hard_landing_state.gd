extends PlayerState

## A landing heavy enough to cost something.
##
## The penalty is momentum, not time: most of the horizontal speed is scrubbed
## and input is locked out briefly. That makes a badly judged drop *feel*
## expensive without taking control away long enough to be irritating, and it
## gives the player a clear reason to prefer a controlled route.


func enter(_previous: StringName, data: Dictionary) -> void:
	var impact: float = float(data.get("impact", 0.0))
	var profile: MovementProfile = player.profile

	player.velocity.x *= profile.hard_landing_speed_keep
	player.velocity.y = 0.0
	player.input.lock(profile.hard_landing_recovery)
	player.landed.emit(impact, true)
	player.reset_fall_metrics()


func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	# Heavy friction on top of the speed cut: the runner visibly absorbs it.
	player.apply_ground_friction(delta, 2.2)
	player.move()

	if not player.is_on_floor():
		transition_to(FALL)
		return

	if time_in_state() >= player.profile.hard_landing_recovery:
		if is_zero_approx(player.input.move_axis) and player.horizontal_speed() < player.profile.idle_speed_threshold:
			transition_to(IDLE)
		else:
			transition_to(RUN)
