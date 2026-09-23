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
@export var kill_plane_y: float = -90.0

## Impact speed at or above which a well-timed slide input becomes a roll.
## Slightly below the hard-landing threshold, so the skilful option is available
## before the punishment starts rather than only as damage control.
@export var roll_min_impact_speed: float = 22.0

# ------------------------------------------------------------------------ slide

@export_group("Slide")

## Minimum speed to start a slide. Prevents a standing crouch-scoot.
@export var slide_min_speed: float = 5.0

## Speed lost per second while sliding. Low: a slide should carry you through a
## gap, not park you under it.
@export var slide_friction: float = 7.0

## Speed below which the slide ends on its own.
@export var slide_exit_speed: float = 3.2

## Longest a slide can run even if held, so it cannot be used as free travel.
@export var slide_max_duration: float = 1.15

## Small forward impulse on entry, so committing to a slide feels like a dive
## rather than a stumble.
@export var slide_entry_boost: float = 1.6

## Fraction of speed kept when a slide is cancelled into a jump. Above 1.0 would
## make slide-jumping a speed exploit; at 1.0 it is a pure, skilful transition.
@export_range(0.0, 1.2) var slide_jump_speed_keep: float = 1.0

# ------------------------------------------------------------------------ vault

@export_group("Vault")

## Duration of a low hurdle vault at full speed. Short — the whole point is that
## it does not interrupt the run.
@export var low_vault_duration: float = 0.3
## Duration of a hand-plant vault over a chest-high obstacle.
@export var high_vault_duration: float = 0.42
## Fraction of speed kept through a low vault. Deliberately 1.0: clearing a low
## obstacle cleanly is the reward for approaching it fast.
@export_range(0.0, 1.2) var low_vault_speed_keep: float = 1.0
## Fraction of speed kept through a high vault. A small cost, so route choice
## between vaulting and going around has meaning.
@export_range(0.0, 1.2) var high_vault_speed_keep: float = 0.88
## Extra clearance added above the obstacle so the arc never grazes it.
@export var vault_clearance: float = 0.28

# ------------------------------------------------------------------- mantle/climb

@export_group("Climb")

## Minimum speed to attempt a mantle.
@export var mantle_min_speed: float = 2.5
## Duration of the pull onto a surface, at the shortest.
@export var mantle_duration_base: float = 0.34
## Extra duration per metre of height climbed.
@export var mantle_duration_per_metre: float = 0.12
## Fraction of speed kept on arrival. A mantle costs momentum by nature — that
## cost is what makes vaulting and routing around worth considering.
@export_range(0.0, 1.0) var mantle_speed_keep: float = 0.52

# ---------------------------------------------------------------------- wall run

@export_group("Wall run")

## Minimum speed to convert a wall impact into an up-run.
@export var wall_run_min_speed: float = 7.0
## Upward speed at the start of the run. Converts horizontal momentum into height.
@export var wall_run_launch_speed: float = 12.5
## How long the runner can stay on the wall.
@export var wall_run_duration: float = 0.42
## Gravity multiplier while on the wall — reduced, so the climb reads as driven
## rather than merely delayed.
@export_range(0.0, 1.0) var wall_run_gravity_scale: float = 0.42
## Horizontal speed pushed away from the wall when the run ends without reaching
## a ledge, so the runner falls clear instead of scraping down the face.
@export var wall_kick_speed: float = 5.5

# --------------------------------------------------------------------- ledge grab

@export_group("Ledge")

## How long the runner hangs before automatically pulling up.
##
## Auto-climbing is a softlock guard as much as a convenience: a hang with no
## timeout is a state the player can sit in forever, and on touch especially it is
## not obvious what to press.
@export var ledge_hang_time: float = 0.22
## Duration of the pull-up.
@export var ledge_climb_duration: float = 0.38
## Horizontal speed granted on arriving at the top. Low — a ledge catch is a
## recovery, so it should feel like surviving rather than gaining.
@export var ledge_exit_speed: float = 4.0

# ------------------------------------------------------------------------- roll

@export_group("Roll")

## Duration of a landing roll.
@export var roll_duration: float = 0.42
## Fraction of speed kept through a roll, versus `hard_landing_speed_keep` for
## eating it standing. The gap between the two is the reward for timing.
@export_range(0.0, 1.2) var roll_speed_keep: float = 0.92
## Forward distance covered by the roll.
@export var roll_distance: float = 2.2

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
