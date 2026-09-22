extends PlayerState

## Running *up* a wall, trading horizontal momentum for height.
##
## ### Why vertical, not lateral
##
## The usual wall-run — sprinting along a wall face — does not exist in a strict
## side view. A wall the runner meets while travelling along X is perpendicular to
## travel, so "along the wall" means into the screen, off the play plane. And
## kicking off backwards, the other standard option, sends the runner away from the
## goal, which in a left-to-right runner is a punishment dressed as a move.
##
## The version that works here is a **tic-tac up-run**: hit a tall wall fast, run a
## short way up it, and if the top comes within reach, catch it. Height is bought
## with speed, which makes arriving fast the answer to obstacles that are too tall
## to mantle — the same lesson the rest of the movement set teaches.
##
## Failure is graceful. Out of wall before reaching the top, the runner kicks clear
## and falls with control rather than scraping down the face.

var _dir: float = 1.0
var _reached_ledge: bool = false


func enter(_previous: StringName, _data: Dictionary) -> void:
	var profile: MovementProfile = player.profile

	_dir = signf(player.velocity.x)
	if is_zero_approx(_dir):
		_dir = player.facing
	player.facing = _dir
	_reached_ledge = false

	# Convert momentum into height. Scaled by how fast the runner arrived, so a
	# faster approach genuinely climbs higher — that relationship is the mechanic.
	var speed_ratio: float = player.speed_ratio()
	player.velocity.y = profile.wall_run_launch_speed * lerpf(0.72, 1.0, speed_ratio)
	# Hold lightly against the wall so contact is maintained without the runner
	# grinding forward into it.
	player.velocity.x = _dir * 0.6

	player.reset_fall_metrics()
	player.wall_ran.emit()


func physics_update(delta: float) -> void:
	var profile: MovementProfile = player.profile
	var sensor: ParkourSensor = player.sensor

	# Reduced gravity: the climb should read as driven, not merely delayed.
	player.velocity.y -= profile.gravity * profile.wall_run_gravity_scale * delta
	player.velocity.x = _dir * 0.6
	player.move()

	# Reaching the top is the whole point — hand straight over to the ledge catch.
	if sensor.ledge_available:
		_reached_ledge = true
		transition_to(LEDGE_GRAB)
		return

	var expired: bool = time_in_state() >= profile.wall_run_duration
	var falling: bool = player.velocity.y <= 0.0
	# Wall gone: either the runner cleared its top, or it ran out sideways.
	var lost_wall: bool = sensor.wall_distance == INF and time_in_state() > 0.08

	if expired or falling or lost_wall:
		_kick_off()


## Pushes clear of the wall so the descent is controlled rather than a scrape.
func _kick_off() -> void:
	var profile: MovementProfile = player.profile
	if player.sensor.wall_distance == INF:
		# The wall ended — carry on forward over whatever was climbed.
		player.velocity.x = _dir * maxf(profile.wall_kick_speed, player.horizontal_speed())
	else:
		# Still a wall ahead and no ledge: give up and drop back, away from it.
		player.velocity.x = -_dir * profile.wall_kick_speed * 0.6
	transition_to(FALL)


func debug_label() -> String:
	return "WallRun(%.2fs%s)" % [time_in_state(), " ledge" if _reached_ledge else ""]
