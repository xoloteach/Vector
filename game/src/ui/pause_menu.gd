class_name PauseMenu
extends CanvasLayer

## Pause overlay: resume, restart, settings, quit to title.
##
## Shown and hidden in response to `Game.paused_changed`, so pausing works
## identically from the keyboard, the on-screen pause button, or anything added later.
## It does not decide *when* to pause; it only reflects that state.

signal quit_to_title_requested

var _root: Control
var _menu: Control
var _settings: SettingsPanel


func _ready() -> void:
	# Above the HUD and touch controls: while paused, this is the only thing the
	# player should be able to interact with.
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.add_child(UITheme.scrim(0.68))

	_build_menu()
	_build_settings()

	Game.paused_changed.connect(_on_paused_changed)


func _build_menu() -> void:
	var panel: PanelContainer = UITheme.panel(30)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(300, 0)
	panel.add_child(column)

	column.add_child(UITheme.title("PAUSED", 38))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	column.add_child(spacer)

	var resume := UITheme.button("Resume", true)
	resume.pressed.connect(func() -> void: Game.set_paused(false))
	column.add_child(resume)

	var restart := UITheme.button("Restart run")
	restart.pressed.connect(func() -> void: Game.restart_level())
	column.add_child(restart)

	var settings := UITheme.button("Settings")
	settings.pressed.connect(func() -> void: _show_settings(true))
	column.add_child(settings)

	var quit := UITheme.button("Quit to title")
	quit.pressed.connect(func() -> void:
		Game.set_paused(false)
		quit_to_title_requested.emit()
	)
	column.add_child(quit)

	_menu = UITheme.centre(panel)
	_root.add_child(_menu)


func _build_settings() -> void:
	_settings = SettingsPanel.new()
	_settings.closed.connect(func() -> void: _show_settings(false))
	var wrapper: Control = UITheme.centre(_settings)
	wrapper.visible = false
	_root.add_child(wrapper)
	_settings.set_meta("wrapper", wrapper)


func _show_settings(showing: bool) -> void:
	(_settings.get_meta("wrapper") as Control).visible = showing
	_menu.visible = not showing


func _on_paused_changed(is_paused: bool) -> void:
	visible = is_paused
	if is_paused:
		_show_settings(false)
