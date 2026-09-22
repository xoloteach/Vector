extends PlayerState

## Standing still. The only state that expects to persist with no input.


func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	player.apply_ground_friction(delta)
	player.move()

	if not player.is_on_floor():
		transition_to(FALL)
		return

	if player.input.has_jump() and player.can_jump():
		transition_to(JUMP)
		return

	if not is_zero_approx(player.input.move_axis):
		transition_to(RUN)
