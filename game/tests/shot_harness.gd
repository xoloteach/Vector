extends Node

## Renders the level from a list of fixed viewpoints and writes PNGs.
##
##   xvfb-run godot --path game res://tests/shot_harness.tscn -- --out /abs/dir
##
## Purpose: a fast visual iteration loop. The browser capture path is the honest
## end-to-end test, but it costs roughly four minutes per look (export, serve,
## SwiftShader boot, play, screenshot) which is far too slow to tune lighting and
## composition against. This runs in one process in a few seconds and produces
## deterministic, directly comparable frames.
##
## Determinism matters as much as speed: the runner is *teleported* to each
## station rather than driven there, and the camera is snapped rather than
## smoothed, so before/after images differ only by the change under test. That is
## what makes visual regression comparison actually mean something.

## Where to stand the runner, and what each station is meant to show.
const STATIONS: Array[Dictionary] = [
	{"name": "a-start-deck",   "x": 8.0,   "y": 0.6,  "air": false},
	{"name": "b-kerb",         "x": 23.0,  "y": 0.6,  "air": false},
	{"name": "c-gap-edge",     "x": 33.0,  "y": 0.6,  "air": false},
	{"name": "d-over-gap",     "x": 36.5,  "y": 2.6,  "air": true},
	{"name": "e-crate",        "x": 46.5,  "y": 0.6,  "air": false},
	{"name": "f-raised-deck",  "x": 72.0,  "y": 2.1,  "air": false},
	{"name": "g-duct",         "x": 84.0,  "y": 2.1,  "air": false},
	{"name": "h-drop-edge",    "x": 91.0,  "y": 2.1,  "air": false},
	{"name": "i-lower-deck",   "x": 104.0, "y": -2.9, "air": false},
	{"name": "j-wide-gap",     "x": 145.0, "y": -2.9, "air": false},
	{"name": "k-ascent",       "x": 163.0, "y": 0.1,  "air": false},
	{"name": "l-final-deck",   "x": 192.0, "y": 1.6,  "air": false},
]

const LEVEL_PATH: String = "res://scenes/levels/level_01.tscn"

var _out_dir: String = "res://../captures/shots"
var _level: Level
var _index: int = 0


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

	# Freeze the simulation. The runner is placed, not played, so physics must not
	# drag it off its mark between placement and capture.
	if _level.player != null:
		_level.player.controls_disabled = true
		_level.player.set_physics_process(false)

	_shoot_all()


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

	for station: Dictionary in STATIONS:
		player.global_position = Vector3(station["x"], station["y"], player.plane_z)
		player.velocity = Vector3(player.profile.max_run_speed, 0.0, 0.0)
		player.facing = 1.0
		# Snap so framing is identical run to run rather than wherever smoothing
		# happened to be.
		camera.snap_to_target()

		# Two physics ticks let the camera settle onto the snapped target, then
		# wait for a real drawn frame before reading the buffer back.
		for _i: int in 3:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw

		var image: Image = get_viewport().get_texture().get_image()
		var path: String = "%s/%s.png" % [_out_dir, station["name"]]
		var err: int = image.save_png(path)
		if err != OK:
			printerr("failed to write %s (error %d)" % [path, err])
		else:
			print("wrote %s" % path)

	print("SHOTS: DONE (%d)" % STATIONS.size())
	# Deferred so stdout flushes before the engine tears down; a direct quit()
	# here swallowed the verdict line and made the wrapper script report failure
	# on a run that had written every frame correctly.
	get_tree().call_deferred("quit", 0)
