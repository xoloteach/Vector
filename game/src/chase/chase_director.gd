class_name ChaseDirector
extends Node

## Decides how much pressure the chase applies, moment to moment.
##
## Separate from the drone itself because "how fast should the pursuer be going"
## and "how does a pursuer move" are different problems, and mixing them is how
## chase AI becomes impossible to tune. The drone asks this for a target speed; it
## does not decide its own difficulty.
##
## ### The fairness contract
##
## A chase that can be outrun forever is not a threat. A chase that cannot be
## outrun is not a game. The rules here are chosen so the player can always tell
## which situation they are in, and so the pursuer's behaviour is always explicable:
##
## 1. **At the settled distance the pursuer runs at exactly parity.** A player
##    holding top speed is never overtaken. Extra speed above parity only becomes
##    available when the gap is already far wider than intended, so it restores a
##    chase rather than punishing good play.
##
## 2. **It closes only when the runner is slow.** Catch-up is driven by the
##    *distance* between them, and distance only opens up when the runner is
##    moving. Fail a vault and stall, and the gap shrinks — because you stopped,
##    not because the game decided to punish you. Slower moves cost ground too: a
##    mantle keeps about half your speed, and the drone takes that back.
##
## 3. **There is a floor on the gap.** Below `panic_distance` the pursuer stops
##    accelerating entirely. Without this, a single mistake spirals: the gap
##    collapses, the pursuer is on top of you, and recovery is impossible. The floor
##    turns a mistake into a scare instead of a death sentence.
##
## 4. **It never teleports and never clips through the level.** It flies over the
##    terrain, which is visible and therefore honest. When it gains ground the
##    player can see exactly why.
##
## 5. **Intensity is published, not implied.** Everything that signals danger —
##    HUD, audio, the drone's own lighting — reads one number, so the cues can
##    never disagree with the actual threat.

signal intensity_changed(intensity: float)
signal caught
## Emitted when the chase crosses into or out of the danger band, so cues fire once
## on the transition instead of every frame.
signal danger_changed(in_danger: bool)

@export_group("Distances")
## Where the pursuer tries to sit, in metres behind the runner.
##
## The equilibrium gap works out a few metres wider than this (the pursuer only
## reaches parity when the error term has ramped it there), landing around 14 m —
## close enough to be a constant presence, far enough that one mistake is a scare
## rather than a death.
@export var target_distance: float = 10.0
## Beyond this the pursuer is effectively out of the picture and intensity is zero.
@export var max_distance: float = 24.0
## Inside this the runner is in trouble: cues escalate.
@export var danger_distance: float = 6.0
## Inside this the pursuer stops trying to close — see rule 3.
@export var panic_distance: float = 4.2
## Contact range.
@export var catch_distance: float = 1.35

@export_group("Speed")
## Cruise speed, as a fraction of the runner's top speed.
@export_range(0.1, 1.2) var cruise_speed_ratio: float = 0.74

## Ceiling while closing a large gap, as a fraction of the runner's top speed.
##
## Slightly *above* parity, and deliberately so. An earlier version capped this
## below 1.0, which sounded fair and produced no game: the runner simply outran the
## drone forever, the gap grew to 38 m, and peak threat over a whole level was 0.17
## — the chase was scenery.
##
## The cap is only reachable when the gap is already much wider than target, so it
## restores a chase that has come apart rather than punishing good play. At the
## equilibrium distance the pursuer is running at exactly parity, so a player
## holding top speed is never overtaken.
@export_range(0.1, 1.5) var max_speed_ratio: float = 1.06

## How aggressively distance error converts into extra speed.
@export var catchup_gain: float = 0.05

## Shapes the distance-to-intensity curve. Below 1.0 lifts the mid-range, so the
## normal trailing distance reads as real, sustained tension instead of registering
## as almost nothing.
@export var intensity_curve: float = 0.85

@export_group("Escalation")
## Optional slow ramp in cruise speed over the course of a run, so a long level
## does not become steady-state. Fraction added at the end of the ramp.
@export_range(0.0, 0.5) var escalation_amount: float = 0.1
@export var escalation_time: float = 90.0

var _player: Player
var _intensity: float = 0.0
var _in_danger: bool = false
var _elapsed: float = 0.0
var _active: bool = false


func setup(player: Player) -> void:
	_player = player
	_active = true
	Game.run_failed.connect(func(_reason: String) -> void: _active = false)
	Game.run_completed.connect(func(_t: float) -> void: _active = false)


func _process(delta: float) -> void:
	if _active and not Game.is_paused():
		_elapsed += delta


## Target horizontal speed for the pursuer, given how far behind it currently is.
func target_speed(distance: float) -> float:
	if _player == null:
		return 0.0
	var top: float = _player.profile.max_run_speed

	# Rule 3: inside the panic floor, stop closing. The runner gets room to recover.
	if distance <= panic_distance:
		return top * cruise_speed_ratio * 0.72

	var cruise: float = cruise_speed_ratio + escalation_amount * clampf(
		_elapsed / maxf(1.0, escalation_time), 0.0, 1.0
	)

	# Rule 2: extra speed comes from the gap being too wide, nothing else.
	var error: float = maxf(0.0, distance - target_distance)
	var ratio: float = clampf(cruise + error * catchup_gain, 0.0, max_speed_ratio)
	return top * ratio


## Updates published state from the current gap. Called by the pursuer each tick,
## so there is one authority for "how dangerous is this right now".
func report_distance(distance: float) -> void:
	if not _active:
		return

	# Inverted and eased: intensity should climb slowly across the middle distances
	# and sharply once the drone is close, which is how the threat actually feels.
	var normalised: float = clampf(distance / max_distance, 0.0, 1.0)
	var next: float = pow(1.0 - normalised, intensity_curve)
	if not is_equal_approx(next, _intensity):
		_intensity = next
		intensity_changed.emit(_intensity)

	var danger: bool = distance <= danger_distance
	if danger != _in_danger:
		_in_danger = danger
		danger_changed.emit(danger)

	if distance <= catch_distance:
		_active = false
		caught.emit()
		_player.kill(Game.FAIL_CAUGHT)


func intensity() -> float:
	return _intensity


func is_in_danger() -> bool:
	return _in_danger


func is_active() -> bool:
	return _active
