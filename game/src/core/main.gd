extends Node

## Application root and scene router.
##
## Owns two states: the title screen, and a running level. Everything that must
## outlive a level reload — the audio director, the pause menu, the results panel —
## lives here as a persistent child; everything that belongs to one attempt is torn
## down and rebuilt.
##
## Restarting rebuilds the level rather than reloading the whole scene. Reloading
## worked, but it also destroyed and recreated the audio director, which restarted the
## music and re-faded the ambience on every single retry — in a game where retrying is
## the main verb, that is unacceptable. Rebuilding only the level keeps the soundscape
## continuous across attempts.

## Query flag / CLI argument that hands control to the autopilot.
##
## A first-class feature, not leftover test code. The screenshots the milestone
## reviews are based on have to show *real gameplay*, and a capture script driving
## blind timed key presses cannot play a parkour level — the first attempt died at the
## third gap and produced eight frames of a corpse. Letting the tested bot drive the
## shipped build means every capture shows the game played competently.
const AUTOPILOT_FLAG: String = "bot"

var _level: Level
var _hud: HUD
var _speed_overlay: SpeedOverlay
var _audio: AudioDirector
var _touch: TouchControls
var _pause_menu: PauseMenu
var _results: ResultsPanel
var _title: TitleScreen
var _bot: Autopilot

## True once the player has started a run, so the title is not shown again on retry.
var _in_game: bool = false
var _query_cache: Variant = null


func _ready() -> void:
	# Overrides first: the level and UI read settings as they build.
	_apply_launch_overrides()
	# Printed so the browser console shows what was actually detected. Launch-flag
	# problems are otherwise invisible: the game simply behaves as though the flag was
	# never passed, which looks identical to the feature being broken.
	print("Main: launch query=%s touch_mode=%d quality=%d" % [
		_launch_query(), Game.touch_mode, Game.quality
	])

	_audio = AudioDirector.new()
	_audio.name = "AudioDirector"
	add_child(_audio)

	_touch = TouchControls.new()
	_touch.name = "TouchControls"
	add_child(_touch)

	_pause_menu = PauseMenu.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.quit_to_title_requested.connect(_return_to_title)
	add_child(_pause_menu)
	# Thumb controls off while paused: they are not usable there and their padded hit
	# areas would sit on top of the menu's buttons.
	Game.paused_changed.connect(func(paused: bool) -> void:
		if _in_game:
			_touch.set_suppressed(paused)
	)

	_results = ResultsPanel.new()
	_results.name = "ResultsPanel"
	_results.retry_requested.connect(_restart_level)
	_results.title_requested.connect(_return_to_title)
	add_child(_results)
	Game.run_failed.connect(func(_r: String) -> void: _touch.set_suppressed(true))
	Game.run_completed.connect(func(_t: float) -> void: _touch.set_suppressed(true))
	Game.run_started.connect(func() -> void:
		if _in_game:
			_touch.set_suppressed(false)
	)

	Game.quality_changed.connect(_on_quality_changed)

	# Interface scale, before any UI is built and again whenever the window changes.
	# Without this the menus render at 4–8 physical pixels on a phone.
	_apply_ui_scale()
	get_window().size_changed.connect(_apply_ui_scale)

	# The autopilot skips the title entirely: a capture session wants gameplay, not a
	# menu, and a bot cannot press a button.
	if _autopilot_requested():
		_start_game()
	else:
		_show_title()


# ------------------------------------------------------------------ title flow

func _show_title() -> void:
	_in_game = false

	# The level is built behind the title, with the runner inert and no chase.
	#
	# Without it the title sits on a black rectangle, which tells a new player nothing
	# about what they are about to play. Showing the actual rooftop costs a level build
	# — a few milliseconds, since levels are procedural — and turns the title into an
	# attract screen.
	_build_level(true)

	_title = TitleScreen.new()
	_title.name = "TitleScreen"
	_title.play_requested.connect(_start_game)
	add_child(_title)
	_set_menu_open(true)


func _start_game() -> void:
	if _title != null:
		_title.queue_free()
		_title = null
	_in_game = true
	_set_menu_open(false)
	# Rebuilt rather than un-frozen, so the run always starts from a clean level.
	_build_level()


func _apply_ui_scale() -> void:
	var factor: float = UITheme.apply_adaptive_scale(get_window())
	# Panels size themselves from the viewport at build time, so they have to be
	# rebuilt when the coordinate space changes underneath them.
	if _title != null:
		_title.queue_free()
		_title = null
		_title = TitleScreen.new()
		_title.name = "TitleScreen"
		_title.play_requested.connect(_start_game)
		add_child(_title)
	if not is_equal_approx(factor, 1.0):
		print("Main: UI scale %.2f for window %s" % [factor, get_window().size])


## Suppresses the on-screen controls and the HUD while a menu is up.
func _set_menu_open(open: bool) -> void:
	_touch.set_suppressed(open)
	if _hud != null:
		_hud.visible = not open
	if _speed_overlay != null:
		_speed_overlay.visible = not open


func _return_to_title() -> void:
	Game.set_paused(false)
	_results.visible = false
	_show_title()


func _restart_level() -> void:
	Game.set_paused(false)
	_results.visible = false
	_build_level()


# ----------------------------------------------------------------- level flow

## Builds the level. In `attract` mode the runner does not respond to input and no
## pursuer spawns — used as a backdrop for the title screen.
func _build_level(attract: bool = false) -> void:
	_teardown_level()

	var packed: PackedScene = load(Game.current_level_path) as PackedScene
	if packed == null:
		push_error("Main could not load level at '%s'." % Game.current_level_path)
		return
	_level = packed.instantiate() as Level
	if _level == null:
		push_error("Scene '%s' is not a Level." % Game.current_level_path)
		return
	if attract:
		_level.chase_enabled = false
		_level.attract_mode = true
	# Inserted below the persistent UI layers so nothing overlaps them.
	add_child(_level)
	move_child(_level, 0)

	_hud = HUD.new()
	_hud.name = "HUD"
	add_child(_hud)
	_hud.bind(_level.player, _level)

	_speed_overlay = SpeedOverlay.new()
	_speed_overlay.name = "SpeedOverlay"
	add_child(_speed_overlay)
	_speed_overlay.setup(_level.player, _level.director)

	_audio.setup(_level.player, _level.director)

	_touch.enabled_changed.connect(_hud.set_touch_mode)
	_hud.set_touch_mode(_touch.is_enabled())

	_apply_quality()

	if attract:
		# No HUD or streaks over the title.
		_hud.visible = false
		_speed_overlay.visible = false
		return

	if _autopilot_requested():
		_attach_autopilot()


## Frees everything belonging to one attempt. The audio director, touch controls,
## pause menu and results panel deliberately survive.
func _teardown_level() -> void:
	if _bot != null:
		_bot.queue_free()
		_bot = null
	if _hud != null:
		if _touch.enabled_changed.is_connected(_hud.set_touch_mode):
			_touch.enabled_changed.disconnect(_hud.set_touch_mode)
		_hud.queue_free()
		_hud = null
	if _speed_overlay != null:
		_speed_overlay.queue_free()
		_speed_overlay = null
	if _level != null:
		_level.queue_free()
		_level = null
	_audio.teardown()


# -------------------------------------------------------------------- quality

func _on_quality_changed(_level_value: Game.Quality) -> void:
	_apply_quality()


func _apply_quality() -> void:
	if _level == null:
		return
	var lighting := _level.get_node_or_null("Lighting") as SceneLighting
	if lighting != null:
		lighting.key_shadows = Game.shadows_enabled()
	if _level.fx != null:
		_level.fx.set_enabled(Game.particles_enabled())


# ------------------------------------------------------------------- autopilot

func _attach_autopilot() -> void:
	if _level.player == null:
		return
	print("Main: autopilot engaged.")
	_bot = Autopilot.new()
	_bot.name = "Autopilot"
	_bot.stall_test = _flag("stall")
	add_child(_bot)
	_bot.setup(_level.player, _level)
	# Loop forever rather than quitting, so a capture session keeps shooting.
	_bot.finished.connect(func(report: Dictionary) -> void:
		print("Autopilot: %s — %s" % [
			"PASS" if report["success"] else "FAIL", report["summary"]
		])
		_restart_for_autopilot()
	)


func _restart_for_autopilot() -> void:
	await get_tree().create_timer(2.0).timeout
	if is_inside_tree():
		_build_level()


# --------------------------------------------------------------------- launch

## Reads settings overrides from the URL query on web, or the command line.
##
## `?touch=0` / `?touch=1` force the on-screen controls off or on. These exist because
## browser touch detection is unreliable, and because deterministic captures need to
## pin the UI state.
func _apply_launch_overrides() -> void:
	if _flag("touch=0"):
		Game.touch_mode = Game.TouchMode.NEVER
	elif _flag("touch=1"):
		Game.touch_mode = Game.TouchMode.ALWAYS
	if _flag("quality=low"):
		Game.quality = Game.Quality.PERFORMANCE


## The launch query string: the URL query on web, or the joined command line.
##
## Read once and cached. `JavaScriptBridge.eval` returning null would otherwise make
## every flag silently false, and calling it per flag made that failure mode harder to
## see rather than easier.
func _launch_query() -> String:
	if _query_cache != null:
		return _query_cache

	var parts: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		parts.append(arg.trim_prefix("--"))

	if OS.has_feature("web"):
		var raw: Variant = JavaScriptBridge.eval("window.location.search", true)
		if typeof(raw) == TYPE_STRING:
			parts.append(String(raw).trim_prefix("?"))

	_query_cache = "&".join(parts)
	return _query_cache


## True when a flag is present in the launch query.
func _flag(name: String) -> bool:
	return _launch_query().contains(name)


func _autopilot_requested() -> bool:
	return _flag(AUTOPILOT_FLAG + "=1") or _flag(AUTOPILOT_FLAG)
