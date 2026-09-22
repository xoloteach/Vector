extends PlayerState

## Vaulting: clearing a thin obstacle without breaking stride.
##
## The signature move. Everything about it is tuned so that approaching an obstacle
## fast is *better* than slowing down for it — a low vault costs no speed at all.
##
## Motion is a scripted arc rather than a jump, because the sensor has already
## verified the obstacle's height, its depth, and that there is somewhere to land.
## Given that, an authored path produces the same clean action every time, where a
## physics jump would vary with approach frame and occasionally clip. See
## `TraversalArc` for the full reasoning.

var _arc := TraversalArc.new()
var _speed_keep: float = 1.0
var _high: bool = false


func enter(_previous: StringName, _data: Dictionary) -> void:
	var sensor: ParkourSensor = player.sensor
	var profile: MovementProfile = player.profile

	_high = sensor.obstacle == ParkourSensor.Obstacle.HIGH_VAULT
	_speed_keep = profile.high_vault_speed_keep if _high else profile.low_vault_speed_keep

	var dir: float = signf(player.velocity.x)
	if is_zero_approx(dir):
		dir = player.facing
	player.facing = dir

	var start: Vector3 = player.global_position
	var speed: float = maxf(player.horizontal_speed(), profile.slide_min_speed)

	# Land clear of the far edge. `obstacle_depth` is INF when the far side was not
	# found within probe range, in which case fall back to a conservative span —
	# the planner only offers a vault when a landing was confirmed, so this is a
	# belt-and-braces bound rather than an expected case.
	var depth: float = sensor.obstacle_depth if sensor.obstacle_depth < INF else 1.2
	var span: float = sensor.obstacle_distance + depth + 0.55

	# Duration from the profile, but never so short that the arc outruns the
	# runner's actual speed — that would read as a teleport.
	var duration: float = profile.high_vault_duration if _high else profile.low_vault_duration
	duration = maxf(duration, span / maxf(speed, 1.0))

	# Land at the far side's height if the sensor found one, otherwise at the
	# obstacle top, so vaulting onto a higher deck works as well as over a crate.
	var landing_y: float = start.y
	if sensor.obstacle_has_landing and sensor.obstacle_top != Vector3.ZERO:
		landing_y = minf(sensor.obstacle_top.y, start.y + sensor.obstacle_height)
		# A vault over something leaves the runner on the far side at ground level,
		# not perched on top; only clamp upward if the far side is genuinely higher.
		landing_y = maxf(start.y, landing_y) if sensor.obstacle_height > 0.9 else start.y

	var end := Vector3(start.x + dir * span, landing_y, start.z)

	# Arc must clear the obstacle's top plus margin, measured from the higher of the
	# two endpoints so an uphill vault still clears.
	var peak: float = start.y + sensor.obstacle_height + profile.vault_clearance
	var lift: float = maxf(0.12, peak - maxf(start.y, end.y))

	_arc.start(start, end, lift, duration, 0.9)
	player.vaulted.emit(_high)


func physics_update(delta: float) -> void:
	var next: Vector3 = _arc.advance(delta)
	player.set_scripted_position(next)
	# Keep velocity meaningful during the arc so animation, camera look-ahead and
	# the speed meter do not read as a dead stop mid-vault.
	player.velocity = _arc.velocity_at_end()

	if not _arc.finished():
		return

	# Hand momentum back to the simulation.
	var dir: float = signf(_arc.to.x - _arc.from.x)
	var carried: float = absf(_arc.velocity_at_end().x) * _speed_keep
	player.velocity = Vector3(dir * carried, 0.0, 0.0)
	player.reset_fall_metrics()

	# Let the normal states sort out whether there is ground here. Going through
	# Fall rather than assuming Run means a vault off the end of a roof behaves
	# correctly with no special case.
	transition_to(RUN if player.is_on_floor() else FALL)


func debug_label() -> String:
	return "Vault(%s %.0f%%)" % ["high" if _high else "low", _arc.progress() * 100.0]
