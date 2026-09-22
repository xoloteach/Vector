extends Node

## Headless entry point for the autopilot. Run with:
##
##   godot --headless --path game res://tests/autopilot_harness.tscn
##
## Prints a machine-readable verdict and sets the process exit code, so CI and
## the dev scripts can treat "the level is completable" as a hard gate.

const LEVEL_PATH: String = "res://scenes/levels/level_01.tscn"

var _level: Level
var _bot: Autopilot


func _ready() -> void:
	print("=== Roofline autopilot ===")
	var packed: PackedScene = load(LEVEL_PATH) as PackedScene
	if packed == null:
		_fail("could not load %s" % LEVEL_PATH)
		return

	_level = packed.instantiate() as Level
	if _level == null:
		_fail("%s is not a Level" % LEVEL_PATH)
		return
	add_child(_level)

	if _level.player == null:
		_fail("level has no player")
		return

	print("course length: %.1f m" % _level.course_length)

	_bot = Autopilot.new()
	_bot.name = "Autopilot"
	add_child(_bot)
	_bot.finished.connect(_on_finished)
	_bot.setup(_level.player, _level)


func _on_finished(report: Dictionary) -> void:
	print("")
	print("--- result ---")
	print("outcome      : %s" % ("PASS" if report["success"] else "FAIL"))
	print("summary      : %s" % report["summary"])
	print("elapsed      : %.2f s" % report["elapsed"])
	print("furthest x   : %.1f / %.1f m (%.0f%%)" % [
		report["max_x"], report["course_length"], report["completion"] * 100.0
	])
	print("jumps        : %d" % report["jumps"])
	print("hard landings: %d" % report["hard_landings"])
	var fps: float = report["min_fps"]
	print("min fps      : %s" % ("n/a (headless)" if fps == INF else "%.0f" % fps))
	print("states       : %s" % _format_states(report["states"]))
	print("")

	if report["success"]:
		print("AUTOPILOT: PASS")
		_quit(0)
	else:
		print("AUTOPILOT: FAIL")
		_quit(1)


func _format_states(states: Dictionary) -> String:
	var parts: Array[String] = []
	for key: StringName in states:
		parts.append("%s=%d" % [key, states[key]])
	parts.sort()
	return ", ".join(parts)


func _fail(message: String) -> void:
	printerr("harness error: %s" % message)
	print("AUTOPILOT: FAIL")
	_quit(2)


func _quit(code: int) -> void:
	# Deferred so the final prints flush before the engine tears down.
	get_tree().call_deferred("quit", code)
