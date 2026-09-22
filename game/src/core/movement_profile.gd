@icon("res://icon.svg")
class_name MovementProfile
extends Resource

## Every number that defines how the runner feels, in one place.
##
## Movement tuning is the single most important thing in this game, so it lives
## in a Resource rather than being scattered across state scripts. That makes it
## possible to tweak feel without touching logic, and to A/B two profiles by
## swapping one reference on the Player.
##
## Units are metres and seconds. The world is built at human scale: the runner
## is 1.8 m tall, a low vault is ~0.9 m, a chest-high wall is ~1.4 m.

# ---------------------------------------------------------------- ground speed

@export_group("Ground")

## Top horizontal speed while sprinting. High enough to feel urgent; the whole
## level is paced around this number.
@export var max_run_speed: float = 11.5

## How hard the runner accelerates toward top speed. Large values feel
## responsive; too large and momentum stops reading visually.
@export var ground_acceleration: float = 60.0

## Deceleration when input opposes current motion. Deliberately higher than
## acceleration so direction changes feel decisive.
@export var ground_turn_deceleration: float = 90.0

## Deceleration with no input. Low enough that letting go coasts rather than
## stopping dead — momentum should feel like it has mass.
@export var ground_friction: float = 38.0

## Below this speed the runner is considered idle rather than running.
@export var idle_speed_threshold: float = 0.6

# ------------------------------------------------------------------------- air

@export_group("Air")

## Downward acceleration while rising.
@export var gravity: float = 34.0

## Gravity is multiplied by this while descending. Asymmetric gravity is the
## cheapest way to make jumps feel snappy without shrinking their arc: the rise
## stays floaty and readable, the fall bites.
@export var fall_gravity_multiplier: float = 1.45

## Terminal velocity, so long drops stay survivable and readable.
@export var max_fall_speed: float = 42.0

## Peak height of a full-commitment jump from standing. Jump velocity is derived
## from this and `gravity`, so height stays correct when gravity is retuned.
@export var jump_height: float = 2.45

## Extra jump height granted at full run speed, scaled linearly by speed.
## Running jumps should clearly outperform standing jumps.
@export var run_jump_height_bonus: float = 0.55

## Horizontal control authority in the air, as a fraction of ground
## acceleration. Below 1.0 so air control assists without erasing commitment.
@export_range(0.0, 1.0) var air_control: float = 0.45

## Air drag. Keeps horizontal speed from creeping up during long airtime.
@export var air_friction: float = 2.0

# ----------------------------------------------------------------- forgiveness

@export_group("Forgiveness")

## Grace period after walking off a ledge during which jump still works.
## Players read "I pressed jump at the edge" far more generously than physics
## does; this closes the gap.
@export var coyote_time: float = 0.13

## A jump pressed this long before landing is remembered and fires on contact.
@export var jump_buffer_time: float = 0.14

## Releasing jump while rising cuts upward velocity by this fraction, giving
## variable jump height.
@export_range(0.0, 1.0) var jump_cut_factor: float = 0.45

## Steps at or below this height are climbed silently without leaving the run
## state, so pavement lips and small ledges never interrupt flow.
@export var step_up_height: float = 0.42

# ---------------------------------------------------------------------- impacts

@export_group("Landing")

## Falling faster than this triggers a heavy landing (momentum penalty).
@export var hard_landing_speed: float = 26.0

## Falling faster than this is lethal.
@export var lethal_landing_speed: float = 40.0

## Fraction of horizontal speed retained through a hard landing.
@export_range(0.0, 1.0) var hard_landing_speed_keep: float = 0.45

## How long a hard landing locks out input. Short — punishing, not annoying.
@export var hard_landing_recovery: float = 0.28

## Any fall below this world Y kills the runner, regardless of geometry.
@export var kill_plane_y: float = -30.0

# ----------------------------------------------------------------------- derived

## Upward velocity needed to reach `jump_height`, from v = sqrt(2 * g * h).
func jump_velocity() -> float:
	return sqrt(2.0 * gravity * jump_height)

## Jump velocity including the running bonus. `speed_ratio` is current
## horizontal speed over `max_run_speed`, clamped to 0..1.
func jump_velocity_at_speed(speed_ratio: float) -> float:
	var height: float = jump_height + run_jump_height_bonus * clampf(speed_ratio, 0.0, 1.0)
	return sqrt(2.0 * gravity * height)

## Gravity for the current vertical velocity, applying the fall multiplier.
func gravity_for(vertical_velocity: float) -> float:
	return gravity * fall_gravity_multiplier if vertical_velocity < 0.0 else gravity
