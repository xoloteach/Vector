extends Node

## Loads every GDScript in the project and reports any that fail to compile.
##
## Run with:
##   godot --headless --path game res://tests/parse_check.tscn
##
## Why this rather than `--check-only --script`: that flag compiles a file in
## isolation, with no autoloads registered, so every script that touches the
## `Game` singleton reports "Identifier not found: Game" and the check becomes
## pure noise. Running as a scene means the project is fully initialised —
## autoloads present, global class names registered — so a failure here is a real
## failure.
##
## This exists because `--import` does not parse script bodies at all. A
## duplicate local variable once sailed through import, through export, and only
## surfaced as a blank canvas in a browser.

## Directories that are not part of the shipped project.
const SKIP_DIRS: PackedStringArray = [".godot", "addons"]

var _checked: int = 0
var _failed: Array[String] = []


func _ready() -> void:
	print("=== Roofline parse check ===")
	_walk("res://")

	print("")
	print("scripts checked: %d" % _checked)
	if _failed.is_empty():
		print("PARSE CHECK: PASS")
		get_tree().call_deferred("quit", 0)
		return

	print("failed (%d):" % _failed.size())
	for path: String in _failed:
		print("  %s" % path)
	print("PARSE CHECK: FAIL")
	get_tree().call_deferred("quit", 1)


func _walk(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			if not SKIP_DIRS.has(entry):
				_walk(full)
		elif entry.ends_with(".gd"):
			_check(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _check(path: String) -> void:
	_checked += 1
	# Default cache mode on purpose. CACHE_MODE_IGNORE force-reloads scripts that
	# are already live — including the autoload and this script's own
	# dependencies — and the engine aborts with "Bad address index". Reusing the
	# cache is still a complete check: a script either compiled when something
	# first referenced it, or it gets compiled here.
	var script: Resource = ResourceLoader.load(path, "Script")
	if script == null:
		_failed.append(path)
