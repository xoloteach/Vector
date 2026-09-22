extends PlayerState

## Rolling out of a heavy landing.
##
## The skilful alternative to `HardLanding`. Same impact, but the player asked to go
## low around the moment of contact, and keeps ~92% of their speed instead of ~45%.
##
## This is the justification for hard landings existing at all. A landing penalty
## with no skilful counter is just a tax on playing fast, which teaches the player
## to avoid height — the opposite of what a parkour game wants. With a roll, a big
## drop becomes a question ("can I time this?") rather than a warning.
##
## Deliberately generous: `roll_min_impact_speed` sits *below* the hard-landing
## threshold, so the option appears before the punishment does and the player can
## discover it without first being punished.

var _arc := TraversalArc.new()
var _dir: float = 1.0


func enter(_previous: StringName, data: Dictionary) -> void:
	var profile: MovementProfile = player.profile
	var impact: float = float(data.get("impact", 0.0))

	_dir = signf(player.velocity.x)
	if is_zero_approx(_dir):
		_dir = player.facing
	player.facing = _dir

	player.input.consume_slide()

	# Lower the body for the duration. The silhouette change is what makes the roll
	# read as a distinct action at a glance rather than a fast landing.
	player.set_body_height(Player.SLIDING_HEIGHT)

	var start: Vector3 = player.global_position
	var distance: float = profile.roll_distance
	var end := Vector3(start.x + _dir * distance, start.y, start.z)

	# Scale duration with speed so a fast roll does not visibly drag behind the
	# runner's momentum.
	var speed: float = maxf(player.horizontal_speed(), 4.0)
	var duration: float = maxf(profile.roll_duration * 0.6, minf(profile.roll_duration, distance / speed))

	_arc.start(start, end, 0.0, duration, 1.0)

	# Report the landing as *soft*. Mechanically it was a heavy impact, but the roll
	# absorbed it: a hard-landing camera shake here would punish the player for
	# doing the right thing.
	player.landed.emit(impact, false)
	player.rolled.emit(impact)
	player.reset_fall_metrics()


func exit() -> void:
	# Only stand up if there is headroom — a roll that ends under a duct becomes a
	# slide rather than clipping through the ceiling.
	if player.can_stand_up():
		player.set_body_height(Player.STANDING_HEIGHT)


func physics_update(delta: float) -> void:
	# Follow the arc horizontally, but keep gravity real: rolling off a ledge should
	# drop the runner, not carry it across thin air.
	var arc_position: Vector3 = _arc.advance(delta)
	player.apply_gravity(delta)

	if player.is_on_floor():
		player.set_scripted_position(Vector3(arc_position.x, player.global_position.y, player.plane_z))
		player.velocity.x = _dir * (_arc.to.x - _arc.from.x) / _arc.duration
		player.move()
	else:
		# Left the ground mid-roll: abandon the scripted path and fall properly.
		player.velocity.x = _dir * player.profile.max_run_speed * player.profile.roll_speed_keep
		player.move()
		if player.velocity.y < -2.0:
			transition_to(FALL)
			return

	if not _arc.finished():
		return

	var profile: MovementProfile = player.profile
	player.velocity.x = _dir * profile.max_run_speed * profile.roll_speed_keep

	if not player.can_stand_up():
		transition_to(SLIDE)
		return
	transition_to(RUN if player.is_on_floor() else FALL)


func debug_label() -> String:
	return "Roll(%.0f%%)" % (_arc.progress() * 100.0)
