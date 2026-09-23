extends Node

## Application root.
##
## Loads whichever level `Game` currently points at and attaches the HUD to it.
## Keeping the level as a *child* rather than as the scene root means restarting
## reloads this scene, which resets the world and the HUD together and guarantees
## no state survives a retry — the single most common source of "it only breaks
## on the second attempt" bugs.

## Query flag / CLI argument that hands control to the autopilot.
##
## This is a first-class feature, not leftover test code. The screenshots that
## the milestone reviews are based on have to show *real gameplay*, and a capture
## script driving blind timed key presses cannot play a parkour level — the first
## attempt died at the third gap and produced eight frames of a corpse. Letting
## the already-proven bot drive the shipped build means every capture shows the
## game being played competently, all the way to the finish.
const AUTOPILOT_FLAG: String = "bot"

var _level: Level
var _hud: HUD
var _speed_overlay: SpeedOverlay
var _touch: TouchControls
var _bot: Autopilot


func _ready() -> void:
	# Overrides first: the level and UI read settings as they build.
	_apply_launch_overrides()
	_load_level(Game.current_level_path)


func _load_level(path: String) -> void:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("Main could not load level at '%s'." % path)
		return

	_level = packed.instantiate() as Level
	if _level == null:
		push_error("Scene '%s' is not a Level." % path)
		return
	add_child(_level)

	_hud = HUD.new()
	_hud.name = "HUD"
	add_child(_hud)
	# Bound after both exist so the HUD never reads a half-built level.
	_hud.bind(_level.player, _level)

	# Added after the HUD so touch controls sit on top of it. They reveal
	# themselves only on a touch device or after a real touch event.
	# Motion streaks and the threat vignette. Added before the touch controls so it
	# sits beneath them, and beneath the HUD.
	_speed_overlay = SpeedOverlay.new()
	_speed_overlay.name = "SpeedOverlay"
	add_child(_speed_overlay)
	_speed_overlay.setup(_level.player, _level.director)

	_touch = TouchControls.new()
	_touch.name = "TouchControls"
	add_child(_touch)
	# The HUD's meters occupy the same corner as the left thumb cluster, so they
	# move whenever the controls appear or disappear.
	_touch.enabled_changed.connect(_hud.set_touch_mode)
	_hud.set_touch_mode(_touch.is_enabled())

	if _autopilot_requested():
		_attach_autopilot()


## Reads settings overrides from the URL query on web, or the command line.
##
## `?touch=0` / `?touch=1` force the on-screen controls off or on. These exist
## because browser touch detection is unreliable, and because deterministic captures
## need to be able to pin the UI state.
func _apply_launch_overrides() -> void:
	var query: String = ""
	if OS.has_feature("web"):
		var raw: Variant = JavaScriptBridge.eval("window.location.search", true)
		if typeof(raw) == TYPE_STRING:
			query = String(raw)
	for arg: String in OS.get_cmdline_user_args():
		query += "&" + arg.trim_prefix("--")

	if query.contains("touch=0"):
		Game.touch_mode = Game.TouchMode.NEVER
	elif query.contains("touch=1"):
		Game.touch_mode = Game.TouchMode.ALWAYS


func _attach_autopilot() -> void:
	if _level.player == null:
		return
	print("Main: autopilot engaged.")
	_bot = Autopilot.new()
	_bot.name = "Autopilot"
	add_child(_bot)
	_bot.setup(_level.player, _level)
	# Loop forever rather than quitting, so a capture session can keep shooting.
	_bot.finished.connect(func(report: Dictionary) -> void:
		print("Autopilot: %s — %s" % [
			"PASS" if report["success"] else "FAIL", report["summary"]
		])
		_restart_for_autopilot()
	)


## Reloads and re-engages the bot, so an unattended capture or attract-mode
## session never ends up staring at a death screen.
func _restart_for_autopilot() -> void:
	await get_tree().create_timer(2.0).timeout
	if is_inside_tree():
		get_tree().reload_current_scene()


## True when the build was asked to play itself, either by `--bot` on the command
## line or by `?bot=1` in the page URL on web.
func _autopilot_requested() -> bool:
	for a: String in OS.get_cmdline_user_args():
		if a == "--" + AUTOPILOT_FLAG or a == "--" + AUTOPILOT_FLAG + "=1":
			return true

	if OS.has_feature("web"):
		var query: Variant = JavaScriptBridge.eval("window.location.search", true)
		if typeof(query) == TYPE_STRING and String(query).contains(AUTOPILOT_FLAG + "=1"):
			return true

	return false
