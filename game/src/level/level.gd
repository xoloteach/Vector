class_name Level
extends Node3D

## Base class for every level.
##
## Owns the run lifecycle for one course: spawning, restarting, reacting to the
## finish line, and keeping the void underneath the level honest. Subclasses
## supply geometry by overriding `build_course()`.
##
## Levels are built **procedurally from data** rather than saved as scene trees
## full of nodes. A course then lives as a readable table of numbers that can be
## diffed, tuned and reasoned about, and the scene file stays a few hundred
## bytes. For a game whose quality lives entirely in the spacing of obstacles,
## being able to read the spacing as a list is worth more than editor handles.

signal course_built(length: float)

## --- The depth convention, and why it matters -------------------------------
##
## Gameplay happens at Z = 0. Level geometry is built so its **front face sits
## just in front of the play plane** and its body extends backwards.
##
## The naive alternative — decks centred on Z = 0 — looks correct in a top-down
## editor and is wrong on screen. With a perspective camera the deck's near edge
## projects lower than its far edge, so the runner ends up drawn above the
## visible roof line, apparently floating. Pushing the mass backwards instead
## puts the runner's feet exactly on the roof's leading edge, which is the read
## the whole side view depends on.
##
## Front face of solid geometry. Clears the runner's 0.34 m collision radius, so
## the body is fully behind the surface it stands on.
const SURFACE_FRONT_Z: float = 0.7
## Back face of walkable decks.
##
## Shallow on purpose. At 5 m deep the perspective camera revealed the whole top
## surface as a bright plateau, so roofs read as plains seen from above rather
## than edges seen from the side — which made judging where a surface *ends*
## harder than it should be. 3.5 m leaves a thin top band that reads as an edge
## while still giving the roof visible depth.
const SURFACE_BACK_Z: float = -2.8
## Props sit shallower than decks so they read as objects placed on the roof.
const PROP_FRONT_Z: float = 0.6
const PROP_BACK_Z: float = -1.9

@export var player: Player
@export var camera: ParkourCamera
@export var spawn_point: Marker3D

## X position of the finish line, filled in by `build_course()`.
var course_length: float = 0.0

var _geometry_root: Node3D


func _ready() -> void:
	_geometry_root = Node3D.new()
	_geometry_root.name = "Geometry"
	add_child(_geometry_root)

	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Player
	if camera == null:
		camera = get_viewport().get_camera_3d() as ParkourCamera

	build_course()
	_add_void_killzone()

	if player != null:
		if spawn_point != null:
			player.global_position = spawn_point.global_position
		player.died.connect(_on_player_died)

	if camera != null:
		camera.snap_to_target()

	course_built.emit(course_length)
	Game.start_run()


## Restart and pause are **polled**, not handled as events.
##
## The on-screen touch controls drive the game through `Input.action_press()`,
## which sets an action's state but does not synthesise an `InputEvent`. Anything
## reading `event.is_action_pressed()` in `_input`/`_unhandled_input` is therefore
## invisible to touch. Polling `Input.is_action_just_pressed()` sees keyboard,
## gamepad and touch identically, so there is one code path for all of them.
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"restart"):
		Game.restart_level()
	elif Input.is_action_just_pressed(&"pause"):
		Game.toggle_pause()


## Override to place geometry. Use `spawn()` so everything lands under the
## geometry root and gets cleaned up together.
func build_course() -> void:
	pass


## Adds a node to the level's geometry root.
func spawn(node: Node3D) -> Node3D:
	_geometry_root.add_child(node)
	return node


## Convenience: a solid box at a position, sized from its centre.
func block(
	centre: Vector3,
	size: Vector3,
	kind: SurfaceLibrary.Kind = SurfaceLibrary.Kind.CONCRETE,
	traversable: bool = false
) -> BoxBlock:
	var b := BoxBlock.new()
	b.size = size
	b.kind = kind
	b.traversable = traversable
	b.position = centre
	spawn(b)
	return b


## A walkable deck whose *top surface* sits at `top_y`, spanning `from_x`..`to_x`.
## Authoring by top surface rather than centre matters because every gameplay
## decision — can I clear this, can I mantle that — is about surface height.
func deck(
	from_x: float,
	to_x: float,
	top_y: float,
	# Thin, because the front face of a deck is a large flat area pointed straight
	# at the camera. At 2 m it dominated the lower third of every frame.
	thickness: float = 1.1,
	kind: SurfaceLibrary.Kind = SurfaceLibrary.Kind.CONCRETE
) -> BoxBlock:
	var width: float = to_x - from_x
	var depth: float = SURFACE_FRONT_Z - SURFACE_BACK_Z
	var centre := Vector3(
		from_x + width * 0.5,
		top_y - thickness * 0.5,
		(SURFACE_FRONT_Z + SURFACE_BACK_Z) * 0.5
	)
	return block(centre, Vector3(width, thickness, depth), kind)


## An obstacle sitting on a deck: `height` tall, `depth_x` long, starting at
## `from_x`, resting on the surface at `ground_y`.
func obstacle(
	from_x: float,
	depth_x: float,
	ground_y: float,
	height: float,
	kind: SurfaceLibrary.Kind = SurfaceLibrary.Kind.METAL
) -> BoxBlock:
	var depth: float = PROP_FRONT_Z - PROP_BACK_Z
	var centre := Vector3(
		from_x + depth_x * 0.5,
		ground_y + height * 0.5,
		(PROP_FRONT_Z + PROP_BACK_Z) * 0.5
	)
	return block(centre, Vector3(depth_x, height, depth), kind, true)


## The finish line, with its beacon, at `x` standing on `ground_y`.
func finish(x: float, ground_y: float) -> FinishLine:
	var f := FinishLine.new()
	f.position = Vector3(x, ground_y + 3.0, 0.0)
	spawn(f)
	f.reached.connect(_on_finish_reached)
	course_length = x
	return f


# ------------------------------------------------------------------- lifecycle

## A wide, deep kill volume under the whole course, so falling off anywhere ends
## the run promptly instead of after a long silent drop.
func _add_void_killzone() -> void:
	var void_zone := KillZone.new()
	void_zone.name = "VoidKillZone"
	void_zone.reason = Game.FAIL_FELL
	var span: float = maxf(course_length, 200.0) + 200.0
	void_zone.size = Vector3(span, 8.0, 40.0)
	void_zone.position = Vector3(span * 0.5 - 100.0, -18.0, 0.0)
	spawn(void_zone)


func _on_player_died(_reason: String) -> void:
	pass  # the UI layer listens to Game.run_failed and owns the retry flow


func _on_finish_reached(finishing_player: Player) -> void:
	finishing_player.controls_disabled = true
