extends Node

## Renders the level from fixed viewpoints and writes PNGs.
##
##   ./scripts/shots.sh <name>
##
## Purpose: a fast visual iteration loop. The browser capture path is the honest
## end-to-end test, but it costs roughly four minutes per look (export, serve,
## SwiftShader boot, play, screenshot) which is far too slow to tune lighting,
## composition or a traversal pose against. This runs in one process in seconds.
##
## ### Deterministic *and* able to show moves in progress
##
## Static stations teleport the runner to a mark, snap the camera and shoot. That
## is enough for composition and lighting, but it cannot photograph a vault,
## because a vault only exists while it is happening.
##
## Action stations therefore place the runner *before* an obstacle, hold real input
## for a fixed number of physics ticks, and then shoot. Because the start position,
## the input and the tick count are all fixed, the resulting frame is the same every
## run — so these are still valid for before/after regression comparison, which a
## live-play capture is not.

## `x`/`y` place the runner. `hold` lists actions pressed during simulation.
## `ticks` is how many 60 Hz physics steps to run before capturing — omit or set 0
## for a frozen composition shot.
const STATIONS: Array[Dictionary] = [
	# --- composition and lighting ---
	{"name": "a-start-deck", "x": 8.0, "y": 0.6},
	{"name": "b-kerb", "x": 23.0, "y": 0.6},
	{"name": "c-gap-edge", "x": 33.0, "y": 0.6},
	{"name": "d-raised-deck", "x": 72.0, "y": 2.1},
	{"name": "e-lower-deck", "x": 105.0, "y": -2.9},
	{"name": "f-mantle-steps", "x": 147.0, "y": -2.9},
	{"name": "g-wall-face", "x": 169.0, "y": 0.1},
	{"name": "h-final-deck", "x": 210.0, "y": 3.1},
	{"name": "i-drop-edge", "x": 222.0, "y": 3.1},

	# --- moves, mid-action ---
	# Each starts a run-up short of its obstacle and simulates forward. Tick counts
	# were found by stepping until the pose was at its most readable.
	{"name": "m1-low-vault", "x": 43.0, "y": 0.6, "hold": ["move_right"], "ticks": 34},
	{"name": "m2-high-vault", "x": 72.0, "y": 2.1, "hold": ["move_right"], "ticks": 30},
	{"name": "m3-slide-duct", "x": 80.0, "y": 2.1, "hold": ["move_right"], "ticks": 44},
	{"name": "m4-mantle", "x": 146.0, "y": -2.9, "hold": ["move_right"], "ticks": 26},
	{"name": "m5-wall-run", "x": 164.0, "y": 0.1, "hold": ["move_right"], "ticks": 46},
	{"name": "m6-ledge-grab", "x": 164.0, "y": 0.1, "hold": ["move_right"], "ticks": 58},
	{"name": "m7-airborne", "x": 30.0, "y": 0.6, "hold": ["move_right", "jump"], "ticks": 32},
	{"name": "m8-roll", "x": 216.0, "y": 3.1, "hold": ["move_right", "slide"], "ticks": 96},
	# The pursuer, placed explicitly. `drone_offset` is how far behind the runner to
	# park it.
	#
	# It cannot be photographed by simply waiting: during normal play the drone trails
	# outside the frame, and letting it close means it catches the runner and ends the
	# run. Placing it directly is the only way to get a repeatable image of the chase
	# at a chosen distance — which is also exactly what reviewing the *readability* of
	# the threat requires.
	{"name": "n1-pursuer-far", "x": 20.0, "y": 0.6, "drone_offset": 13.0},
	{"name": "n2-pursuer-close", "x": 20.0, "y": 0.6, "drone_offset": 5.5},
]

const LEVEL_PATH: String = "res://scenes/levels/level_01.tscn"

var _out_dir: String = "res://../captures/shots"
var _level: Level


func _ready() -> void:
	_parse_args()
	print("=== Roofline shot harness -> %s ===" % _out_dir)
	DirAccess.make_dir_recursive_absolute(_out_dir)

	var packed: PackedScene = load(LEVEL_PATH) as PackedScene
	if packed == null:
		printerr("could not load %s" % LEVEL_PATH)
		get_tree().quit(1)
		return
	_level = packed.instantiate() as Level
	add_child(_level)

	await _shoot_all()


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			_out_dir = args[i + 1]


func _shoot_all() -> void:
	var player: Player = _level.player
	var camera: ParkourCamera = _level.camera
	if player == null or camera == null:
		printerr("level is missing a player or camera")
		get_tree().quit(1)
		return

	var written: int = 0
	for station: Dictionary in STATIONS:
		var ticks: int = int(station.get("ticks", 0))
		var hold: Array = station.get("hold", [])

		_reset_player(player, station["x"], station["y"])
		_place_drone(player, station.get("drone_offset", -1.0))

		if ticks > 0:
			for action: String in hold:
				Input.action_press(StringName(action))
			# Let the simulation run. Physics is left enabled here on purpose: the
			# point is to photograph the movement system actually working.
			for _i: int in ticks:
				await get_tree().physics_frame
			for action: String in hold:
				Input.action_release(StringName(action))
		else:
			# Frozen composition shot: hold the runner still so the frame is purely
			# about lighting and layout.
			player.velocity = Vector3(player.profile.max_run_speed, 0.0, 0.0)
			camera.snap_to_target()
			for _i: int in 3:
				await get_tree().physics_frame

		await RenderingServer.frame_post_draw

		var image: Image = get_viewport().get_texture().get_image()
		var label: String = "%s [%s]" % [station["name"], player.state_name()]
		var path: String = "%s/%s.png" % [_out_dir, station["name"]]
		if image.save_png(path) != OK:
			printerr("failed to write %s" % path)
		else:
			written += 1
			print("wrote %-22s state=%s" % [station["name"] + ".png", player.state_name()])
		# Reported so a station that silently stopped exercising its move — because
		# the level moved, or a threshold changed — is visible in the log rather than
		# only in the image.
		if ticks > 0:
			print("      %s" % label)

	print("SHOTS: DONE (%d)" % written)
	# Deferred so stdout flushes before teardown; a direct quit() swallowed the
	# verdict line and made the wrapper report failure on a successful run.
	get_tree().call_deferred("quit", 0)


## Parks the pursuer a fixed distance behind the runner, or well out of frame when
## the station does not want it.
##
## Out of frame by default because most stations exist to judge geometry and poses,
## and a drone wandering through those shots would make them non-comparable between
## runs.
func _place_drone(player: Player, offset: float) -> void:
	if _level.pursuer == null:
		return
	var behind: float = offset if offset > 0.0 else 400.0
	# Feed the camera the intensity this distance would produce, so chase framing is
	# exercised rather than merely the drone being present.
	if _level.camera != null and _level.director != null:
		_level.director.report_distance(behind)
		_level.camera.set_threat(_level.director.intensity())
	_level.pursuer.global_position = Vector3(
		player.global_position.x - behind,
		player.global_position.y + _level.pursuer.hover_height,
		player.plane_z
	)


## Puts the runner back to a known state between stations, so one station's leftover
## velocity or crouched capsule cannot contaminate the next.
##
## Also restarts the run: earlier stations legitimately end in death (the runner is
## dropped into place and falls), which deactivates the chase director for every
## station after it. Without the reset, half the sheet silently had no pursuer.
func _reset_player(player: Player, x: float, y: float) -> void:
	for action: String in ["move_right", "move_left", "jump", "slide"]:
		Input.action_release(StringName(action))
	player.is_dead = false
	player.input.lock(0.0)
	Game.start_run()
	player.set_body_height(Player.STANDING_HEIGHT)
	player.global_position = Vector3(x, y, player.plane_z)
	player.velocity = Vector3.ZERO
	player.facing = 1.0
	player.reset_fall_metrics()
	if player.machine != null:
		player.machine.transition_to(PlayerState.IDLE)
	if _level.camera != null:
		_level.camera.snap_to_target()
