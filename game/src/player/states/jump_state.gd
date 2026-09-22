extends PlayerState

## The rising half of a jump. Splitting rise from fall keeps each one's tuning
## and animation independent, and gives a clean hook for apex-based effects.

## Ignore ground contact for this long after takeoff. Without it, a jump started
## on a slope or while `is_on_floor()` is still latched can immediately resolve
## as a landing.
const TAKEOFF_GRACE: float = 0.06


func enter(_previous: StringName, _data: Dictionary) -> void:
	player.do_jump()


func physics_update(delta: float) -> void:
	# Releasing the key early trims the arc — the difference between a tap and a
	# hold is the main expressive tool the player has in the air.
	player.try_jump_cut()

	player.apply_gravity(delta)

	var axis: float = player.input.move_axis
	if not is_zero_approx(axis):
		player.facing = signf(axis)
		player.apply_horizontal(delta, axis, player.profile.air_control)
	else:
		player.apply_air_friction(delta)

	player.move()

	if player.velocity.y <= 0.0:
		transition_to(FALL)
		return

	# Clipping a ceiling kills upward momentum immediately; hanging there for a
	# few frames reads as a bug.
	if player.is_on_ceiling():
		player.velocity.y = minf(player.velocity.y, 0.0)
		transition_to(FALL)
		return

	if player.is_on_floor() and time_in_state() > TAKEOFF_GRACE:
		resolve_landing()
		return

	# A jump straight into a tall wall becomes an up-run rather than a dead stop
	# against its face.
	if time_in_state() > TAKEOFF_GRACE:
		resolve_airborne_traversal()
