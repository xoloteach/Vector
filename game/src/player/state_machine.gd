class_name PlayerStateMachine
extends Node

## Flat state machine for the player controller.
##
## Deliberately flat rather than hierarchical: every parkour action is a
## first-class state, transitions are explicit, and there is exactly one active
## state at a time. That makes "why is the player doing this?" answerable by
## reading one file.
##
## States are child nodes. The node name is the state name, so adding a state is
## adding a node — no registry to keep in sync.

signal state_changed(from: StringName, to: StringName)

## Emitted whenever a transition is requested for a state that does not exist.
## Loud failure beats a silent freeze.
signal transition_failed(requested: StringName)

var current: PlayerState = null
var current_name: StringName = &""
var previous_name: StringName = &""

## Seconds spent in the current state. States read this instead of each keeping
## their own timer.
var time_in_state: float = 0.0

## Short history, newest last. Invaluable when debugging a traversal that picks
## the wrong action.
var history: Array[StringName] = []

const HISTORY_LIMIT: int = 12

var _states: Dictionary[StringName, PlayerState] = {}
var _player: Player = null


func setup(player: Player, initial: StringName) -> void:
	_player = player
	for child: Node in get_children():
		if child is PlayerState:
			var state: PlayerState = child
			state.setup(player, self)
			_states[StringName(child.name)] = state
		else:
			push_warning("StateMachine child '%s' is not a PlayerState." % child.name)
	transition_to(initial)


func transition_to(next: StringName, data: Dictionary = {}) -> void:
	if not _states.has(next):
		push_error("No player state named '%s'." % next)
		transition_failed.emit(next)
		return

	# Re-entering the same state is usually a logic bug, but a few states
	# legitimately want to restart (e.g. chained vaults). Allow it, and let the
	# state decide via `data`.
	var from: StringName = current_name
	if current != null:
		current.exit()

	previous_name = from
	current = _states[next]
	current_name = next
	time_in_state = 0.0

	history.append(next)
	if history.size() > HISTORY_LIMIT:
		history.remove_at(0)

	current.enter(from, data)
	state_changed.emit(from, next)


func physics_update(delta: float) -> void:
	if current == null:
		return
	time_in_state += delta
	current.physics_update(delta)


func has_state(name: StringName) -> bool:
	return _states.has(name)


func is_in(name: StringName) -> bool:
	return current_name == name


## True if the state was active within the last `depth` transitions.
func was_recently(name: StringName, depth: int = 2) -> bool:
	var start: int = maxi(0, history.size() - depth - 1)
	for i: int in range(start, history.size() - 1):
		if history[i] == name:
			return true
	return false
