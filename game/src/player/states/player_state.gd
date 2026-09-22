class_name PlayerState
extends Node

## Base class for every player movement state.
##
## Contract:
##  - a state may read anything on `player`, but may only mutate movement
##    through the player's helper methods,
##  - a state never reads `Input` directly (use `player.input`),
##  - a state never raycasts (use `player.sensor`),
##  - a state requests changes with `transition_to()` and then returns
##    immediately — it must not keep running logic after transitioning,
##  - a state never talks to another state.
##
## Names used for transitions, so typos fail at parse time rather than runtime.
const IDLE: StringName = &"Idle"
const RUN: StringName = &"Run"
const JUMP: StringName = &"Jump"
const FALL: StringName = &"Fall"
const LAND: StringName = &"Land"
const HARD_LANDING: StringName = &"HardLanding"
const DEATH: StringName = &"Death"

var player: Player = null
var machine: PlayerStateMachine = null


func setup(p: Player, m: PlayerStateMachine) -> void:
	player = p
	machine = m


## Called once when the state becomes active. `previous` is the state we came
## from; `data` carries hand-off values (impact speed, target ledge, etc).
func enter(_previous: StringName, _data: Dictionary) -> void:
	pass


## Called once when leaving. Undo anything temporary (collision shape changes,
## speed caps, visual offsets) here — never in `enter` of the next state.
func exit() -> void:
	pass


## Called every physics tick while active. The state is responsible for calling
## `player.move()` exactly once, or for explicitly choosing not to move.
func physics_update(_delta: float) -> void:
	pass


## Human-readable label for the debug overlay. Override when a state has
## meaningful substate.
func debug_label() -> String:
	return str(name)


# ------------------------------------------------------------------- shorthands

func transition_to(next: StringName, data: Dictionary = {}) -> void:
	machine.transition_to(next, data)


func time_in_state() -> float:
	return machine.time_in_state


## Shared airborne resolution: picks the right landing state based on impact
## speed, or death if the impact is lethal. Returns true if a transition was
## made, so callers can `return` immediately.
func resolve_landing() -> bool:
	if not player.is_on_floor():
		return false
	var impact: float = player.peak_fall_speed
	var profile: MovementProfile = player.profile

	if impact >= profile.lethal_landing_speed:
		transition_to(DEATH, {"reason": Game.FAIL_IMPACT, "impact": impact})
		return true
	if impact >= profile.hard_landing_speed:
		transition_to(HARD_LANDING, {"impact": impact})
		return true
	transition_to(LAND, {"impact": impact})
	return true
