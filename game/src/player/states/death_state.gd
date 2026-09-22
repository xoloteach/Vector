extends PlayerState

## Terminal state. Nothing transitions out of it — recovery happens by reloading
## the level, which is deliberate: a death that can be walked out of teaches the
## player that mistakes are free.

var _reason: String = Game.FAIL_FELL


func enter(_previous: StringName, data: Dictionary) -> void:
	_reason = String(data.get("reason", Game.FAIL_FELL))
	player.is_dead = true
	player.velocity.x *= 0.15
	player.input.lock(9999.0)
	player.died.emit(_reason)
	Game.fail_run(_reason)


## After this long the body stops being simulated.
##
## Without it, a runner who died by falling accelerates downward forever — the
## debug overlay caught it at y = -237 still doing terminal velocity. Harmless
## but it is a dead state that never resolves, and an unbounded coordinate is the
## kind of thing that eventually breaks something else.
const SETTLE_TIME: float = 1.5

var _settled: bool = false


func physics_update(delta: float) -> void:
	if _settled:
		return

	# Keep simulating briefly so the body settles onto the ground instead of
	# freezing mid-air, which reads as a crash rather than a death.
	player.apply_gravity(delta)
	player.apply_ground_friction(delta, 3.0)
	player.move()

	if player.is_on_floor() or time_in_state() >= SETTLE_TIME:
		_settled = true
		player.velocity = Vector3.ZERO


func exit() -> void:
	_settled = false


func debug_label() -> String:
	return "Death(%s)" % _reason
