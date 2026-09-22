extends PlayerState

## Sliding: low profile, momentum preserved.
##
## Two distinct jobs, which is why it is entered both by player intent and
## automatically:
##  - it is how the runner gets under things too low to stand under,
##  - it is a speed-preserving alternative to stopping.
##
## The state is *sticky under low ceilings*: while the sensor reports there is no
## headroom, the slide cannot end, no matter what the player does. Without that,
## releasing the key inside a duct would try to restore a 1.8 m capsule inside
## solid geometry and either shove the runner through the roof or wedge it.

## Downward stick applied each tick so the slide hugs descending surfaces instead
## of launching off small crests.
const GROUND_STICK: float = 2.5


func enter(_previous: StringName, _data: Dictionary) -> void:
	var profile: MovementProfile = player.profile

	player.set_body_height(Player.SLIDING_HEIGHT)
	player.input.consume_slide()

	# A small boost on entry. Sliding should feel like committing to a dive; without
	# it, the drop in eye height reads as tripping.
	if not is_zero_approx(player.velocity.x):
		player.velocity.x += signf(player.velocity.x) * profile.slide_entry_boost

	player.slid.emit()


func exit() -> void:
	# Only ever called when `can_stand_up()` has already passed, or on death.
	player.set_body_height(Player.STANDING_HEIGHT)


func physics_update(delta: float) -> void:
	var profile: MovementProfile = player.profile
	var sensor: ParkourSensor = player.sensor

	player.apply_gravity(delta)
	# Keep the body pressed down over crests so a slide under a duct cannot bounce
	# up into it.
	if player.is_on_floor():
		player.velocity.y = minf(player.velocity.y, -GROUND_STICK)

	# Friction only — no acceleration. A slide is a decision made at entry; letting
	# the player accelerate through it would make it strictly better than running.
	player.velocity.x = move_toward(player.velocity.x, 0.0, profile.slide_friction * delta)

	# Steering is allowed, but only enough to adjust a line, not to turn around.
	var axis: float = player.input.move_axis
	if not is_zero_approx(axis) and signf(axis) == signf(player.velocity.x):
		player.facing = signf(axis)

	player.move()

	if not player.is_on_floor() and player.velocity.y < -1.0:
		# Slid off an edge. Leaving the slide mid-air keeps the airborne pose and
		# landing logic consistent, and the capsule must come back for that.
		if player.can_stand_up():
			transition_to(FALL)
			return

	# --- ending the slide -----------------------------------------------------
	var blocked_above: bool = not player.can_stand_up()
	if blocked_above:
		# Trapped low. Nothing may interrupt, and if the runner is about to stall
		# under an obstruction, nudge it clear rather than leaving it stuck.
		if player.horizontal_speed() < profile.slide_exit_speed * 0.8:
			player.velocity.x = player.facing * profile.slide_exit_speed
		return

	# Slide-jump: a clean cancel that keeps full speed. This is the main piece of
	# expressive tech the slide offers, so it costs nothing.
	if player.input.has_jump() and player.can_jump():
		player.velocity.x *= profile.slide_jump_speed_keep
		transition_to(JUMP)
		return

	var expired: bool = time_in_state() >= profile.slide_max_duration
	var too_slow: bool = player.horizontal_speed() <= profile.slide_exit_speed
	var released: bool = not player.input.slide_held and not sensor.can_slide_under

	if expired or too_slow or released:
		transition_to(RUN if player.horizontal_speed() > profile.idle_speed_threshold else IDLE)


func debug_label() -> String:
	return "Slide(%.2fs)" % time_in_state()
