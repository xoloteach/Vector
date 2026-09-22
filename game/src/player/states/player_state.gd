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
## These must match the node names under the StateMachine exactly.
const IDLE: StringName = &"Idle"
const RUN: StringName = &"Run"
const JUMP: StringName = &"Jump"
const FALL: StringName = &"Fall"
const LAND: StringName = &"Land"
const HARD_LANDING: StringName = &"HardLanding"
const DEATH: StringName = &"Death"
const SLIDE: StringName = &"Slide"
const VAULT: StringName = &"Vault"
const CLIMB: StringName = &"Climb"
const LEDGE_GRAB: StringName = &"LedgeGrab"
const WALL_RUN: StringName = &"WallRun"
const ROLL: StringName = &"Roll"

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


## Shared airborne resolution: asks the planner how this impact should be
## absorbed and transitions accordingly. Returns true if a transition was made, so
## callers can `return` immediately.
func resolve_landing() -> bool:
	if not player.is_on_floor():
		return false
	var impact: float = player.peak_fall_speed
	# Slide held *or* freshly pressed both count, so a roll can be armed slightly
	# before touchdown as well as on the frame of contact.
	var intent_slide: bool = player.input.slide_held or player.input.has_slide()
	var next: StringName = TraversalPlanner.plan_landing(player, intent_slide)
	transition_to(next, {"impact": impact, "reason": Game.FAIL_IMPACT})
	return true


## Shared airborne opportunity check: ledge catches and wall runs. Returns true if
## a transition was made.
func resolve_airborne_traversal() -> bool:
	var next: StringName = TraversalPlanner.plan_airborne(player)
	if next == TraversalPlanner.NONE:
		return false
	transition_to(next)
	return true
