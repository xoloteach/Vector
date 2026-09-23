extends Node

## Global run state and scene flow. Autoloaded as `Game`.
##
## Deliberately thin: it owns the things that must outlive a scene reload
## (which level we are in, run statistics, whether we are paused) and nothing
## else. Gameplay logic belongs in the systems that own it.

signal run_started
signal run_failed(reason: String)
signal run_completed(elapsed: float)
signal paused_changed(is_paused: bool)

## Reason strings passed with `run_failed`, so UI can show a specific message
## instead of a generic "you died".
const FAIL_FELL: String = "fell"
const FAIL_IMPACT: String = "impact"
const FAIL_CAUGHT: String = "caught"
const FAIL_HAZARD: String = "hazard"

var current_level_path: String = "res://scenes/levels/level_01.tscn"

## Seconds of gameplay in the current run. Stops on death or completion.
var run_time: float = 0.0
var run_active: bool = false
var attempts: int = 0

## Furthest X the runner reached this run, for progress UI.
var furthest_x: float = 0.0

var _paused: bool = false

# ------------------------------------------------------------------- settings

## How the on-screen touch controls behave.
##
## A real setting rather than pure auto-detection, because detection cannot be made
## reliable in a browser: desktop Chromium reports a touchscreen as available and
## delivers mouse clicks as screen-touch events, which put a full thumb UI over the
## game on a machine with no touchscreen. Auto does its best and retreats on mouse
## or keyboard use; the explicit modes exist because some player, somewhere, will
## need them.
enum TouchMode { AUTO, ALWAYS, NEVER }

var touch_mode: TouchMode = TouchMode.AUTO:
	set(value):
		touch_mode = value
		touch_mode_changed.emit(value)

signal touch_mode_changed(mode: TouchMode)

## Master and bus volumes, 0..1. Applied by the audio system.
var master_volume: float = 0.85
var music_volume: float = 0.6
var sfx_volume: float = 0.9

signal volumes_changed


func _ready() -> void:
	# The pause menu and death screen still need to process while the world is
	# frozen, so this node never pauses.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if run_active and not _paused:
		run_time += delta


func start_run() -> void:
	run_time = 0.0
	furthest_x = 0.0
	run_active = true
	attempts += 1
	run_started.emit()


func fail_run(reason: String) -> void:
	if not run_active:
		return
	run_active = false
	run_failed.emit(reason)


func complete_run() -> void:
	if not run_active:
		return
	run_active = false
	run_completed.emit(run_time)


func report_progress(x: float) -> void:
	furthest_x = maxf(furthest_x, x)


# ------------------------------------------------------------------ scene flow

func restart_level() -> void:
	set_paused(false)
	# Deferred so we never free the tree from inside a physics callback.
	get_tree().call_deferred("reload_current_scene")


func load_level(path: String) -> void:
	current_level_path = path
	set_paused(false)
	get_tree().call_deferred("change_scene_to_file", path)


func is_paused() -> bool:
	return _paused


func set_paused(value: bool) -> void:
	if _paused == value:
		return
	_paused = value
	get_tree().paused = value
	paused_changed.emit(value)


func toggle_pause() -> void:
	set_paused(not _paused)


## Formats a duration as M:SS.mmm for the HUD and results screen.
static func format_time(seconds: float) -> String:
	var minutes: int = int(seconds) / 60
	var secs: int = int(seconds) % 60
	var millis: int = int(fposmod(seconds, 1.0) * 1000.0)
	return "%d:%02d.%03d" % [minutes, secs, millis]
