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

## Whether this level runs a chase. Off for test courses and the title backdrop.
@export var chase_enabled: bool = true

## Attract mode: the level renders as a backdrop for the title screen, with the runner
## inert. Set before the level enters the tree.
var attract_mode: bool = false

var director: ChaseDirector
var pursuer: Pursuer
var fx: RunnerFX

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

	fx = RunnerFX.new()
	fx.name = "RunnerFX"
	add_child(fx)

	build_course()
	_add_void_killzone()

	if player != null:
		if spawn_point != null:
			player.global_position = spawn_point.global_position
		player.died.connect(_on_player_died)
		fx.setup(player)
		if chase_enabled:
			_start_chase()

	if camera != null:
		camera.snap_to_target()

	course_built.emit(course_length)

	if attract_mode:
		# Frozen scenery for the title screen: the runner stands still and the run
		# clock never starts, so the title cannot accrue a time or a death.
		if player != null:
			player.controls_disabled = true
		return

	Game.start_run()


## Restart and pause are **polled**, not handled as events.
##
## Disabled in attract mode: the title screen owns the keyboard there, and a stray R
## or Esc must not restart or pause a level the player has not started.
##
## The on-screen touch controls drive the game through `Input.action_press()`,
## which sets an action's state but does not synthesise an `InputEvent`. Anything
## reading `event.is_action_pressed()` in `_input`/`_unhandled_input` is therefore
## invisible to touch. Polling `Input.is_action_just_pressed()` sees keyboard,
## gamepad and touch identically, so there is one code path for all of them.
func _process(_delta: float) -> void:
	if attract_mode:
		return
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
##
## Authoring by top surface rather than centre matters because every gameplay
## decision — can I clear this, can I mantle that — is about surface height.
##
## ### `thickness` is a gameplay parameter, not a visual one
##
## A deck extends *down* from its top by `thickness`. For a deck with open air
## underneath, the default is deliberately thin: the front face is a large flat
## area pointed straight at the camera, and at 2 m it dominated the lower third of
## every frame.
##
## But when a deck is meant to form a **flush riser or wall** against a lower deck,
## its thickness must reach down to at least the lower deck's surface. Otherwise a
## void opens up between the two, and what looks like a solid 3 m wall is actually a
## gap with an overhang above it. That exact mistake made the wall-run beat
## unreachable: the runner ran off the lower deck into the void and fell, because
## there was no wall face in front of it to run up.
##
## Rule of thumb: for a riser, pass `thickness >= (top_y - lower_deck_top_y) + 0.2`.
func deck(
	from_x: float,
	to_x: float,
	top_y: float,
	thickness: float = 0.85,
	kind: SurfaceLibrary.Kind = SurfaceLibrary.Kind.CONCRETE
) -> BoxBlock:
	var width: float = to_x - from_x
	var depth: float = SURFACE_FRONT_Z - SURFACE_BACK_Z
	var centre := Vector3(
		from_x + width * 0.5,
		top_y - thickness * 0.5,
		(SURFACE_FRONT_Z + SURFACE_BACK_Z) * 0.5
	)
	var body: BoxBlock = block(centre, Vector3(width, thickness, depth), kind)
	# Decks do not cast. They are far too wide for the shadow atlas to resolve and
	# self-shadow their own front faces into a visible diagonal weave. They still
	# receive, so the runner and props are grounded normally.
	body.casts_shadow = false
	if thickness > 1.4:
		_add_face_seams(from_x, to_x, top_y, thickness)
	return body


## Horizontal seam lines across a tall deck or riser face.
##
## A flush riser's front face is a large flat rectangle aimed straight at the
## camera, and undressed it reads as a blank grey slab with no sense of scale —
## which also makes it hard to judge *how tall* the thing is. A couple of recessed
## seams give the face a unit of measure. Non-colliding and slightly proud of the
## surface, so they cannot z-fight with it.
func _add_face_seams(from_x: float, to_x: float, top_y: float, thickness: float) -> void:
	const SEAM_SPACING: float = 1.1
	var width: float = to_x - from_x
	var offset: float = SEAM_SPACING
	while offset < thickness - 0.25:
		var seam: BoxBlock = block(
			Vector3(from_x + width * 0.5, top_y - offset, SURFACE_FRONT_Z + 0.06),
			Vector3(width - 0.1, 0.07, 0.05),
			SurfaceLibrary.Kind.DARK
		)
		seam.solid = false
		offset += SEAM_SPACING


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


# ------------------------------------------------------------------- prop kit

## Places a piece of **scenery** from the environment kit.
##
## Scenery never collides and always sits behind the play plane. `depth` is how far
## back, and it drives both the position and the automatic value fade in
## `PropLibrary` — so pushing a prop back for visual interest also guarantees it
## stops competing with the runner's silhouette.
func scenery(
	kind: String,
	x: float,
	ground_y: float,
	depth: float = 4.0,
	yaw_degrees: float = 0.0,
	prop_scale: float = 1.0
) -> Node3D:
	var node: Node3D = PropLibrary.create(kind, depth)
	if node == null:
		return null
	node.position = Vector3(x, ground_y, -depth)
	node.rotation.y = deg_to_rad(yaw_degrees)
	node.scale = Vector3.ONE * prop_scale
	spawn(node)
	return node


## Places a piece of **furniture**: a detailed prop mesh in the play plane, with a
## separate coarse collision box sized to the gameplay dimensions.
##
## Two objects on purpose. Gameplay collision stays axis-aligned, coarse and
## predictable; the visual mesh can be as detailed as it likes. That separation is
## what stops "I clearly cleared that" complaints, and it means a prop can be
## re-modelled without retesting traversal.
##
## `collide_height` and `collide_depth_x` are the numbers the movement system
## actually sees, so they are what the beat is designed around — the mesh follows.
func furniture(
	kind: String,
	x: float,
	ground_y: float,
	collide_height: float,
	collide_depth_x: float,
	surface: SurfaceLibrary.Kind = SurfaceLibrary.Kind.METAL
) -> BoxBlock:
	var block_body: BoxBlock = obstacle(
		x - collide_depth_x * 0.5, collide_depth_x, ground_y, collide_height, surface
	)
	# The collision box is invisible; the prop provides the visuals.
	var mesh: MeshInstance3D = block_body.get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		mesh.visible = false

	var node: Node3D = PropLibrary.create(kind, 0.0)
	if node != null:
		node.position = Vector3(x, ground_y, (PROP_FRONT_Z + PROP_BACK_Z) * 0.5)
		spawn(node)
	return block_body


## An overhead obstruction leaving `clearance` metres of headroom — a slide-under.
##
## The duct prop is modelled with its underside at the origin, so it is positioned
## directly by the clearance it leaves. Clearance is the only dimension gameplay
## cares about, so it is the one the API takes.
func overhead(
	x: float,
	ground_y: float,
	clearance: float,
	length: float = 3.0
) -> BoxBlock:
	var thickness: float = 0.66
	var block_body: BoxBlock = block(
		Vector3(x, ground_y + clearance + thickness * 0.5, (PROP_FRONT_Z + PROP_BACK_Z) * 0.5),
		Vector3(length, thickness, PROP_FRONT_Z - PROP_BACK_Z),
		SurfaceLibrary.Kind.METAL,
		true
	)
	var mesh: MeshInstance3D = block_body.get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		mesh.visible = false

	var node: Node3D = PropLibrary.create("duct_section", 0.0)
	if node != null:
		node.position = Vector3(x, ground_y + clearance, (PROP_FRONT_Z + PROP_BACK_Z) * 0.5)
		node.scale = Vector3(length / 3.0, 1.0, 1.0)
		spawn(node)

	# Support legs, behind the play plane so they never obstruct the runner.
	for side_x: float in [x - length * 0.5 + 0.3, x + length * 0.5 - 0.3]:
		var leg: BoxBlock = block(
			Vector3(side_x, ground_y + (clearance + thickness) * 0.5, -2.4),
			Vector3(0.2, clearance + thickness, 0.22),
			SurfaceLibrary.Kind.TRIM
		)
		leg.solid = false

	return block_body


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


## Spawns the pursuer and its director.
##
## Created in code rather than placed in the scene so the chase can be switched off
## per level with a single flag, and so the pursuer always starts relative to
## wherever the runner actually spawned.
func _start_chase() -> void:
	director = ChaseDirector.new()
	director.name = "ChaseDirector"
	add_child(director)
	director.setup(player)

	pursuer = Pursuer.new()
	pursuer.name = "Pursuer"
	add_child(pursuer)
	pursuer.setup(player, director)

	# The camera widens and re-centres as pressure rises, so the pursuer stays in
	# frame instead of sitting off the left edge exactly when it matters most.
	if camera != null:
		director.intensity_changed.connect(camera.set_threat)


func _on_player_died(_reason: String) -> void:
	pass  # the UI layer listens to Game.run_failed and owns the retry flow


func _on_finish_reached(finishing_player: Player) -> void:
	finishing_player.controls_disabled = true
