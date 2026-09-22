class_name TraversalArc
extends RefCounted

## A timed positional arc, used by the scripted traversal states.
##
## Vaults, mantles, rolls and ledge climbs all move the body along a known path
## rather than by integrating forces. That is a deliberate choice:
##
##  - **The path is verified before it starts.** `ParkourSensor` has already
##    confirmed the obstacle's height, depth and that there is somewhere to land,
##    so the motion cannot fail halfway and leave the runner inside geometry.
##  - **It is repeatable.** Physics-driven traversal over an obstacle produces a
##    slightly different result every time depending on approach frame; an arc
##    produces the same clean action every time, which is what makes these moves
##    feel *authored* rather than accidental.
##  - **Animation can be trusted.** A fixed duration means an animation can be
##    timed to the motion instead of chasing it.
##
## While an arc runs, the owning state does not call `move_and_slide()` — it sets
## position directly. Normal physics resumes the moment the arc completes.

var from: Vector3 = Vector3.ZERO
var to: Vector3 = Vector3.ZERO
## Extra height added at the midpoint, over and above the straight line.
var lift: float = 0.0
var duration: float = 0.3
var elapsed: float = 0.0

## Shapes the horizontal progress curve. 1.0 is linear; below 1.0 front-loads the
## movement, which reads as a committed launch rather than a glide.
var ease_exponent: float = 0.85


func start(
	start_position: Vector3,
	end_position: Vector3,
	arc_lift: float,
	arc_duration: float,
	ease: float = 0.85
) -> void:
	from = start_position
	to = end_position
	lift = arc_lift
	# Never zero — a zero-length arc would divide by zero and teleport the body.
	duration = maxf(0.05, arc_duration)
	ease_exponent = ease
	elapsed = 0.0


## Advances by `delta` and returns the position for this tick.
func advance(delta: float) -> Vector3:
	elapsed = minf(duration, elapsed + delta)
	return position_at(progress())


func position_at(t: float) -> Vector3:
	var eased: float = pow(clampf(t, 0.0, 1.0), ease_exponent)
	var base: Vector3 = from.lerp(to, eased)
	# A sine hump peaks at the midpoint and returns to zero at both ends, so the
	# arc always lands exactly on `to` regardless of lift.
	base.y += lift * sin(PI * clampf(t, 0.0, 1.0))
	return base


func progress() -> float:
	return clampf(elapsed / duration, 0.0, 1.0)


func finished() -> bool:
	return elapsed >= duration


## Instantaneous velocity along the arc, so the state can hand a sensible
## velocity back to the physics simulation on exit instead of dropping to zero.
func velocity_at_end() -> Vector3:
	var span: Vector3 = to - from
	var horizontal: float = span.x / duration
	# Tail of the sine hump is descending, so vertical velocity at the end is
	# negative for a lifted arc.
	var vertical: float = span.y / duration - lift * PI / duration
	return Vector3(horizontal, vertical, 0.0)
