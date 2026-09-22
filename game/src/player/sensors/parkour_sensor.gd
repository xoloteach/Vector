class_name ParkourSensor
extends Node3D

## All of the runner's perception of the world, in one place.
##
## States consume the fields below as a **read-only snapshot** refreshed once per
## physics tick by `poll()`. No state is allowed to raycast for itself; if a
## state needs to know something about the world, the question gets added here.
## That rule is what keeps traversal behaviour debuggable — there is exactly one
## place where "what does the runner think is in front of it" is decided.
##
## Probing uses direct space-state queries rather than RayCast3D nodes. Node
## based casts would need repositioning every tick anyway, and the direct API
## lets the probe fan scale with speed without churning the scene tree.

enum Obstacle {
	NONE,        ## clear ahead
	STEP,        ## kerb height — absorbed by the run state, no dedicated move
	LOW_VAULT,   ## hip height, thin — hurdle straight over without slowing
	HIGH_VAULT,  ## chest height, thin — plant a hand and swing through
	CLIMB,       ## head height or above, thick — mantle onto the top
	WALL,        ## too tall to mantle — wall-run or kick off
}

# ------------------------------------------------------------------- geometry

## Physics layers treated as solid for probing: world (1) + traversable (3).
const SOLID_MASK: int = 1 | 4

## Heights above the feet at which forward probes are cast, low to high.
const PROBE_HEIGHTS: PackedFloat32Array = [0.18, 0.5, 0.9, 1.3, 1.65]

## Capsule dimensions, mirrored from the collision shape.
const BODY_HEIGHT: float = 1.8
const BODY_RADIUS: float = 0.34

# ------------------------------------------------------- classification limits

@export_group("Classification")
## At or below this the obstacle is a step the run state absorbs silently.
@export var step_max_height: float = 0.42
## Upper bound for a hurdle-style vault taken at speed without losing momentum.
@export var low_vault_max_height: float = 1.05
## Upper bound for a hand-plant vault.
@export var high_vault_max_height: float = 1.7
## Upper bound for mantling onto a surface. Above this it is a wall.
@export var climb_max_height: float = 2.7
## An obstacle deeper than this cannot be vaulted over — it must be climbed onto.
@export var vault_max_depth: float = 1.9
## Minimum horizontal speed before vaults are offered at all. Walking into a
## crate should not trigger an athletic hurdle.
@export var vault_min_speed: float = 4.5

@export_group("Reach")
## Base forward probe distance, extended in proportion to speed so a fast
## runner commits to traversal earlier and the animation has room to play.
@export var base_reach: float = 0.75
@export var reach_per_speed: float = 0.085
## How far ahead the gap probe looks for missing ground.
@export var gap_probe_distance: float = 1.6
## How far down the gap probe looks before declaring a drop.
@export var gap_probe_depth: float = 4.0

# --------------------------------------------------------------- snapshot (ro)

## Classification of whatever is directly ahead.
var obstacle: Obstacle = Obstacle.NONE
## Height of the obstacle's top surface above the runner's feet, metres.
var obstacle_height: float = 0.0
## Horizontal distance from the body surface to the obstacle face, metres.
var obstacle_distance: float = 0.0
## Depth of the obstacle along the run direction. INF when the far side was not
## found within the probe range (i.e. it is effectively a solid mass).
var obstacle_depth: float = 0.0
## World position of the top-front corner — the point a vault or mantle targets.
var obstacle_top: Vector3 = Vector3.ZERO
## True when there is somewhere to land on the far side of a vaultable obstacle.
var obstacle_has_landing: bool = false

## True when the ground disappears within `gap_probe_distance` ahead.
var gap_ahead: bool = false
## Drop from the runner's feet to whatever is below the gap probe. INF if the
## probe found nothing at all (a true void).
var gap_depth: float = 0.0

## Distance from the body to the point where the ground ahead stops, INF while
## the ground continues for the whole probed span. This is the number that lets
## anything — animation anticipation, the camera, an autopilot — know a jump is
## coming *before* the runner is over the edge.
var edge_distance: float = INF
## Width of the gap beyond that edge, INF when no landing was found within reach.
var gap_width: float = INF
## Height of the far side relative to the runner's feet. Positive means up.
var far_side_height: float = 0.0

## Height of solid ceiling above the runner's head, INF when clear. Used to keep
## the runner crouched/sliding while under a duct rather than standing up into it.
var ceiling_clearance: float = INF

## True when a slide would fit under an obstruction the runner cannot stand in.
var can_slide_under: bool = false

## Distance to a wall on the facing side, INF when none in reach.
var wall_distance: float = INF
## Surface normal of that wall, for wall-run and kick direction.
var wall_normal: Vector3 = Vector3.ZERO

## Height of solid ground below the feet, INF when airborne over nothing.
var ground_distance: float = INF

var _player: Player = null
var _space: PhysicsDirectSpaceState3D = null
var _exclude: Array[RID] = []


func setup(player: Player) -> void:
	_player = player
	_exclude = [player.get_rid()]


## Refresh every field. Called once per physics tick before the state machine
## runs, so all states in a tick see a consistent view of the world.
func poll() -> void:
	if _player == null:
		return
	_space = _player.get_world_3d().direct_space_state
	if _space == null:
		return

	var feet: Vector3 = _feet()
	var dir: float = signf(_player.velocity.x)
	if is_zero_approx(dir):
		dir = _player.facing

	_probe_ground(feet)
	_probe_ceiling(feet)
	_probe_gap(feet, dir)
	_probe_obstacle(feet, dir)
	_probe_wall(feet, dir)

	can_slide_under = (
		ceiling_clearance < BODY_HEIGHT - 0.1
		and ceiling_clearance > 0.95
	)


# ------------------------------------------------------------------- the probes

func _probe_ground(feet: Vector3) -> void:
	var hit: Dictionary = _ray(feet + Vector3.UP * 0.1, Vector3.DOWN * (gap_probe_depth + 0.1))
	ground_distance = (feet.y - float(hit["position"].y)) if not hit.is_empty() else INF


func _probe_ceiling(feet: Vector3) -> void:
	var origin: Vector3 = feet + Vector3.UP * 0.4
	var hit: Dictionary = _ray(origin, Vector3.UP * (BODY_HEIGHT + 0.6))
	ceiling_clearance = (float(hit["position"].y) - feet.y) if not hit.is_empty() else INF


## How far forward the edge march looks. Generous, because a fast runner needs to
## know about a gap roughly a second before reaching it.
const EDGE_SCAN_DISTANCE: float = 14.0
## Resolution of the edge march. 0.2 m is accurate enough to time a takeoff and
## cheap enough to run every tick.
const EDGE_SCAN_STEP: float = 0.2
## How far *down* the search for a landing surface looks past an edge.
##
## Must exceed the deepest survivable drop or the sensor reports a void where
## there is a floor. At the lethal impact speed of 40 m/s that is about 16 m, so
## 26 m covers every drop in the game with margin. Getting this wrong made a
## routine 5 m drop look like a bottomless pit, which in turn made the autopilot
## jump into it and take an unearned hard landing.
const LANDING_SCAN_DEPTH: float = 26.0


func _probe_gap(feet: Vector3, dir: float) -> void:
	# Immediate "is there floor a stride ahead" check, used for bracing.
	var ahead: Vector3 = feet + Vector3(dir * gap_probe_distance, 0.25, 0.0)
	var hit: Dictionary = _ray(ahead, Vector3.DOWN * (gap_probe_depth + 0.25))
	if hit.is_empty():
		gap_ahead = true
		gap_depth = INF
	else:
		var drop: float = feet.y - float(hit["position"].y)
		gap_depth = drop
		# A shallow lip is not a gap; only a genuine step down counts, so the
		# runner does not brace for every minor height change.
		gap_ahead = drop > 0.9

	_march_for_edge(feet, dir)


## Walks probes forward along the ground to find (a) where the surface the runner
## is on ends, and (b) where the next landable surface starts.
##
## March-and-sample rather than a single long ray because the question is not
## "is something there" but "where does *this* surface stop" — which needs
## sampling at ground level across the span.
func _march_for_edge(feet: Vector3, dir: float) -> void:
	edge_distance = INF
	gap_width = INF
	far_side_height = 0.0

	# Tolerance for "still the same surface": anything within this of the
	# runner's foot height counts as continuous ground.
	const SAME_SURFACE_TOLERANCE: float = 0.75

	var travelled: float = EDGE_SCAN_STEP
	var found_edge: bool = false

	while travelled <= EDGE_SCAN_DISTANCE:
		var from: Vector3 = feet + Vector3(dir * travelled, 0.4, 0.0)
		var h: Dictionary = _ray(from, Vector3.DOWN * (0.4 + SAME_SURFACE_TOLERANCE))

		if not found_edge:
			if h.is_empty():
				edge_distance = maxf(0.0, travelled - BODY_RADIUS)
				found_edge = true
			# else: still on the same surface, keep going
		else:
			# Past the edge: look much further down for the landing surface, so
			# a drop onto a lower roof still counts as a landing.
			var deep: Dictionary = _ray(from, Vector3.DOWN * LANDING_SCAN_DEPTH)
			if not deep.is_empty():
				gap_width = travelled - (edge_distance + BODY_RADIUS)
				far_side_height = float(deep["position"].y) - feet.y
				return

		travelled += EDGE_SCAN_STEP


func _probe_obstacle(feet: Vector3, dir: float) -> void:
	obstacle = Obstacle.NONE
	obstacle_height = 0.0
	obstacle_distance = 0.0
	obstacle_depth = 0.0
	obstacle_has_landing = false
	obstacle_top = Vector3.ZERO

	var reach: float = base_reach + reach_per_speed * _player.horizontal_speed()

	# Fan forward rays bottom-up. The highest one that hits brackets the top of
	# the obstacle; if the topmost probe also hits, it is at least wall-height.
	var lowest_hit_height: float = -1.0
	var highest_hit_height: float = -1.0
	var face_x: float = 0.0
	for h: float in PROBE_HEIGHTS:
		var origin: Vector3 = feet + Vector3(0.0, h, 0.0)
		var hit: Dictionary = _ray(origin, Vector3(dir * (reach + BODY_RADIUS), 0.0, 0.0))
		if hit.is_empty():
			continue
		if lowest_hit_height < 0.0:
			lowest_hit_height = h
			face_x = float(hit["position"].x)
		highest_hit_height = h

	if lowest_hit_height < 0.0:
		return  # nothing ahead

	obstacle_distance = maxf(0.0, absf(face_x - feet.x) - BODY_RADIUS)

	# Find the exact top surface: stand a probe just past the face and drop it.
	var inset: float = dir * 0.12
	var top_probe: Vector3 = Vector3(face_x + inset, feet.y + climb_max_height + 0.6, feet.z)
	var top_hit: Dictionary = _ray(top_probe, Vector3.DOWN * (climb_max_height + 1.2))
	if top_hit.is_empty():
		# Taller than we can mantle, or an overhang — treat as wall.
		obstacle = Obstacle.WALL
		obstacle_height = climb_max_height + 1.0
		return

	obstacle_top = top_hit["position"]
	obstacle_height = obstacle_top.y - feet.y

	# Depth: walk probes along the top surface until the ground falls away. The
	# distance at which it does is the obstacle's depth, which is what decides
	# vault-over versus climb-onto.
	obstacle_depth = INF
	var surface_y: float = obstacle_top.y
	var probe_step: float = 0.22
	var travelled: float = probe_step
	while travelled <= vault_max_depth + probe_step:
		var p: Vector3 = Vector3(face_x + dir * travelled, surface_y + 0.35, feet.z)
		var h2: Dictionary = _ray(p, Vector3.DOWN * 0.7)
		if h2.is_empty():
			obstacle_depth = travelled
			break
		travelled += probe_step

	# Is there anywhere to land past it? Probe beyond the far edge.
	var beyond: float = (obstacle_depth if obstacle_depth < INF else vault_max_depth) + 0.5
	var land_probe: Vector3 = Vector3(face_x + dir * beyond, surface_y + 0.2, feet.z)
	var land_hit: Dictionary = _ray(land_probe, Vector3.DOWN * LANDING_SCAN_DEPTH)
	obstacle_has_landing = not land_hit.is_empty()

	obstacle = _classify(highest_hit_height)


func _classify(_highest_probe: float) -> Obstacle:
	var h: float = obstacle_height
	var thin: bool = obstacle_depth <= vault_max_depth
	var fast: bool = _player.horizontal_speed() >= vault_min_speed

	if h <= step_max_height:
		return Obstacle.STEP
	if h <= low_vault_max_height and thin and fast:
		return Obstacle.LOW_VAULT
	if h <= high_vault_max_height and thin and fast:
		return Obstacle.HIGH_VAULT
	if h <= climb_max_height:
		return Obstacle.CLIMB
	return Obstacle.WALL


func _probe_wall(feet: Vector3, dir: float) -> void:
	wall_distance = INF
	wall_normal = Vector3.ZERO
	# Chest height is the right place to ask "is there a wall to work with" —
	# low probes catch kerbs, high probes miss railings.
	var origin: Vector3 = feet + Vector3(0.0, BODY_HEIGHT * 0.55, 0.0)
	var hit: Dictionary = _ray(origin, Vector3(dir * (BODY_RADIUS + 0.55), 0.0, 0.0))
	if hit.is_empty():
		return
	wall_distance = maxf(0.0, absf(float(hit["position"].x) - feet.x) - BODY_RADIUS)
	wall_normal = hit["normal"]


# ----------------------------------------------------------------- convenience

## True when the obstacle ahead is close enough and of a kind the runner should
## act on this tick.
func obstacle_in_range(max_distance: float = 0.55) -> bool:
	return obstacle != Obstacle.NONE and obstacle_distance <= max_distance


func is_vaultable() -> bool:
	return (
		(obstacle == Obstacle.LOW_VAULT or obstacle == Obstacle.HIGH_VAULT)
		and obstacle_has_landing
	)


func is_climbable() -> bool:
	return obstacle == Obstacle.CLIMB or obstacle == Obstacle.WALL


func obstacle_name() -> String:
	return Obstacle.keys()[obstacle]


# ----------------------------------------------------------------------- helpers

func _feet() -> Vector3:
	return _player.global_position


func _ray(from: Vector3, motion: Vector3) -> Dictionary:
	var params := PhysicsRayQueryParameters3D.create(from, from + motion)
	params.collision_mask = SOLID_MASK
	params.exclude = _exclude
	params.hit_back_faces = false
	return _space.intersect_ray(params)
