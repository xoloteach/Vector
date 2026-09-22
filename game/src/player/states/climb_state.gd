extends PlayerState

## Mantling onto a surface too tall to vault.
##
## This state exists to delete a specific failure. A flush riser taller than the
## step-up allowance is, to a capsule, a wall: the body hits its face mid-jump,
## collision zeroes horizontal velocity, and the runner slides up the face and
## arrives on top with nothing left. The level had to be redesigned around that
## during Demo 0.1, replacing every flush step with a gap.
##
## With a mantle, wall contact at speed becomes a deliberate climb that keeps
## about half the momentum, and flush geometry becomes usable level design again.

var _arc := TraversalArc.new()


func enter(_previous: StringName, _data: Dictionary) -> void:
	var sensor: ParkourSensor = player.sensor
	var profile: MovementProfile = player.profile

	var dir: float = signf(player.velocity.x)
	if is_zero_approx(dir):
		dir = player.facing
	player.facing = dir

	var start: Vector3 = player.global_position
	var height: float = sensor.obstacle_height

	# Target a point on top of the surface, far enough in that the capsule is fully
	# supported rather than balanced on the lip.
	var inset: float = ParkourSensor.BODY_RADIUS + 0.3
	var top_y: float = start.y + height
	if sensor.obstacle_top != Vector3.ZERO:
		top_y = sensor.obstacle_top.y
	var end := Vector3(
		start.x + dir * (sensor.obstacle_distance + inset),
		top_y + 0.02,
		start.z
	)

	# Taller climbs take longer, which is what makes height feel like it costs
	# something without needing an explicit penalty.
	var duration: float = profile.mantle_duration_base + profile.mantle_duration_per_metre * height

	# Lift slightly above the target so the body rises past the lip before moving
	# forward over it, rather than cutting the corner through it.
	_arc.start(start, end, 0.18, duration, 1.25)
	player.climbed.emit(height)


func physics_update(delta: float) -> void:
	player.set_scripted_position(_arc.advance(delta))
	player.velocity = Vector3.ZERO

	if not _arc.finished():
		return

	var profile: MovementProfile = player.profile
	var dir: float = signf(_arc.to.x - _arc.from.x)
	# Arrive with a modest push so the runner walks out of the mantle instead of
	# stalling on the edge it just climbed.
	var speed: float = profile.max_run_speed * profile.mantle_speed_keep
	player.velocity = Vector3(dir * speed, 0.0, 0.0)
	player.reset_fall_metrics()

	transition_to(RUN if player.is_on_floor() else FALL)


func debug_label() -> String:
	return "Climb(%.0f%%)" % (_arc.progress() * 100.0)
