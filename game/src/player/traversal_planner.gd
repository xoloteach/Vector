class_name TraversalPlanner
extends RefCounted

## Decides which parkour move the situation calls for.
##
## The single place in the codebase that answers "what should the runner do about
## the thing in front of it?". States ask; they do not decide for themselves.
##
## ### Why this is separate from both the sensor and the states
##
## The sensor reports *facts* about the world. The states *execute* moves. Between
## those sits a genuine third concern — judgement — and it is the part that
## determines whether the game feels intelligent or fussy. Scattering it across
## `RunState` and `FallState` would mean the same decision could be made two
## different ways depending on which state the runner happened to be in, which is
## exactly how contextual traversal systems become unpredictable.
##
## ### The design brief
##
## The player must never have to be precise. They hold a direction and the runner
## picks the athletic, momentum-preserving option. Getting that wrong in the
## generous direction (vaulting something you meant to jump) is a much cheaper
## error than the reverse (stopping dead at a crate), so thresholds lean toward
## *doing* the move.
##
## Priority order matters, and it is ranked by how much momentum each outcome
## preserves. Given an ambiguous obstacle the runner should always attempt the
## fastest viable option, because losing speed is the thing that feels worst.

## Nothing to do; keep running.
const NONE: StringName = &""


## Chooses a grounded traversal, or NONE.
##
## `intent_slide` is the player explicitly asking to go low; it outranks the
## automatic choices because an explicit input should never be overridden by the
## contextual system.
static func plan_grounded(player: Player, intent_slide: bool) -> StringName:
	var sensor: ParkourSensor = player.sensor
	var profile: MovementProfile = player.profile
	var speed: float = player.horizontal_speed()

	# --- forced low: an overhead obstruction with a passage under it -----------
	#
	# Highest priority, and not really a choice. Sliding is the only way through, and
	# entering it automatically is the difference between a duct being an obstacle
	# and a duct being a wall the player does not understand.
	#
	# Checked ahead of the vault and mantle tests deliberately: a duct's top surface
	# sits within mantling range, so on height alone the runner would happily climb
	# onto the thing it was supposed to pass beneath.
	if (
		sensor.obstacle == ParkourSensor.Obstacle.SLIDE_UNDER
		and sensor.obstacle_distance <= _slide_reach(speed)
		and speed > profile.slide_min_speed * 0.6
	):
		return PlayerState.SLIDE

	# Already underneath something too low to stand in.
	if sensor.can_slide_under and speed > profile.slide_min_speed * 0.6:
		return PlayerState.SLIDE

	# --- explicit slide -------------------------------------------------------
	if intent_slide and speed > profile.slide_min_speed:
		return PlayerState.SLIDE

	# --- vault: fastest way past an obstacle, so it is tried first ------------
	if sensor.is_vaultable() and sensor.obstacle_distance <= _vault_reach(speed):
		return PlayerState.VAULT

	# --- mantle: slower, but it gets the runner on top of things --------------
	if (
		sensor.obstacle == ParkourSensor.Obstacle.CLIMB
		and sensor.obstacle_distance <= 0.5
		and speed > profile.mantle_min_speed
	):
		return PlayerState.CLIMB

	# --- wall run: the obstacle is too tall to mantle, but speed can buy height
	if (
		sensor.obstacle == ParkourSensor.Obstacle.WALL
		and sensor.obstacle_distance <= 0.45
		and speed > profile.wall_run_min_speed
	):
		return PlayerState.WALL_RUN

	return NONE


## Chooses an airborne traversal, or NONE.
static func plan_airborne(player: Player) -> StringName:
	var sensor: ParkourSensor = player.sensor
	var profile: MovementProfile = player.profile

	# --- ledge catch ----------------------------------------------------------
	# Only while descending, and only when actually moving at the ledge. Grabbing
	# on the way up would cut good jumps short, and grabbing without forward
	# intent would make the runner stick to walls it was trying to pass.
	if (
		sensor.ledge_available
		and player.velocity.y < 1.0
		and absf(player.velocity.x) > 0.5
		and not player.is_on_floor()
	):
		return PlayerState.LEDGE_GRAB

	# --- wall run from the air ------------------------------------------------
	# A jump into a tall wall becomes an up-run rather than a dead stop against it.
	if (
		sensor.obstacle == ParkourSensor.Obstacle.WALL
		and sensor.obstacle_distance <= 0.4
		and player.horizontal_speed() > profile.wall_run_min_speed
		and player.velocity.y < 2.0
	):
		return PlayerState.WALL_RUN

	return NONE


## Chooses how to absorb an impact: roll, hard landing, soft landing or death.
##
## Rolling is *earned*. It requires the player to have asked to go low around the
## moment of contact, so a well-timed input converts an expensive landing into a
## cheap one. That is the whole reason hard landings exist — without a skilful
## alternative a landing penalty is just a tax.
static func plan_landing(player: Player, intent_slide: bool) -> StringName:
	var profile: MovementProfile = player.profile
	var impact: float = player.peak_fall_speed

	if impact >= profile.lethal_landing_speed:
		return PlayerState.DEATH

	if impact >= profile.roll_min_impact_speed and intent_slide:
		return PlayerState.ROLL

	if impact >= profile.hard_landing_speed:
		return PlayerState.HARD_LANDING

	return PlayerState.LAND


## How close an obstacle must be before a vault commits.
##
## Scales with speed: a faster runner needs to start the move earlier or the body
## reaches the obstacle face before the vault has lifted it clear. This is the same
## relationship that made an early fixed threshold clip the first crate.
static func _vault_reach(speed: float) -> float:
	return clampf(0.45 + speed * 0.075, 0.45, 1.5)


## How close an overhead obstruction must be before the slide commits.
##
## Longer than the vault reach: the body has to already be low by the time it
## arrives, and dropping into a slide takes a moment. Starting late means clipping
## the duct standing up.
static func _slide_reach(speed: float) -> float:
	return clampf(0.8 + speed * 0.12, 0.8, 2.4)
