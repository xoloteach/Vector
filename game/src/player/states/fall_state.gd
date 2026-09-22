extends PlayerState

## Descending, whether from a jump, a ledge, or a drop.
##
## Also the home of coyote time: walking off an edge lands here, and a jump
## pressed shortly after still fires, because the player's mental model is "I
## was on the ledge" and the physics disagrees by about two frames.


func physics_update(delta: float) -> void:
	player.apply_gravity(delta)

	var axis: float = player.input.move_axis
	if not is_zero_approx(axis):
		player.facing = signf(axis)
		player.apply_horizontal(delta, axis, player.profile.air_control)
	else:
		player.apply_air_friction(delta)

	player.move()

	if player.is_on_floor():
		resolve_landing()
		return

	# Late jump press, still inside the grace window.
	if player.coyote_timer > 0.0 and player.input.has_jump():
		transition_to(JUMP)
