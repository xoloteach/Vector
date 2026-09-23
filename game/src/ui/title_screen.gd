class_name TitleScreen
extends CanvasLayer

## Title screen: play, controls, settings.
##
## Deliberately a single screen with swap-in panels rather than a menu tree. The game
## is one level long; anything more elaborate would be scaffolding for content that
## does not exist, and every extra click is a click between the player and running.
##
## The play button takes focus on open, so Enter or Space starts the game without
## touching the mouse — and a gamepad or keyboard player never has to find a cursor.

signal play_requested

var _menu: Control
var _controls: Control
var _settings: SettingsPanel
var _play_button: Button


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS

	add_child(UITheme.scrim(0.55))
	_build_menu()
	_build_controls()
	_build_settings()
	_show(_menu)


func _build_menu() -> void:
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(
		UITheme.content_width(320.0, viewport, 0.0), 0
	)

	# Title scales down on a short screen, where a 62 px headline plus three buttons
	# does not fit.
	var heading := UITheme.title("ROOFLINE", 62 if viewport.y > 460.0 else 42)
	column.add_child(heading)

	var tagline := UITheme.body(
		"Keep moving. Something is behind you.", 15, UITheme.DIM
	)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(tagline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 22)
	column.add_child(spacer)

	_play_button = UITheme.button("RUN", true, true)
	_play_button.pressed.connect(func() -> void:
		play_requested.emit()
	)
	column.add_child(_play_button)

	var controls_button := UITheme.button("Controls")
	controls_button.pressed.connect(func() -> void: _show(_controls))
	column.add_child(controls_button)

	var settings_button := UITheme.button("Settings")
	settings_button.pressed.connect(func() -> void: _show(_settings))
	column.add_child(settings_button)

	var footer := UITheme.caption("An original game. No commercial game's assets are used.")
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer)

	_menu = UITheme.centre(column)
	add_child(_menu)


func _build_controls() -> void:
	const PADDING: float = 22.0
	# Chrome outside the scroll view: heading, Back button, separations and padding.
	const CHROME: float = 150.0
	var viewport: Vector2 = get_viewport().get_visible_rect().size

	var panel: PanelContainer = UITheme.panel(int(PADDING))
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	outer.custom_minimum_size = Vector2(
		UITheme.content_width(420.0, viewport, PADDING), 0
	)
	panel.add_child(outer)

	outer.add_child(UITheme.heading("CONTROLS", 22))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	column.add_child(UITheme.body(
		"Movement is contextual. There is no vault button — run at an obstacle and the "
		+ "runner picks the move that fits its height, your speed and the space on the "
		+ "far side.",
		13, UITheme.DIM
	))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	column.add_child(spacer)

	# Plain ASCII key names. Arrow glyphs rendered as missing-character boxes in the
	# engine's default font, so the panel listed controls the player could not read.
	for pair: Array in [
		["Run", "A / D   or  Left / Right"],
		["Jump  (hold for height)", "Space / W / Up"],
		["Slide, and roll on landing", "S / Down / Shift"],
		["Restart", "R"],
		["Pause", "Esc / P"],
		["Debug overlay", "F1"],
	]:
		column.add_child(UITheme.key_row(pair[0], pair[1]))

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 8)
	column.add_child(spacer2)

	column.add_child(UITheme.body(
		"Time a slide as you land a big drop to roll out of it and keep your speed. "
		+ "Eating the landing standing up costs most of it.",
		13, UITheme.ACCENT
	))
	column.add_child(UITheme.body(
		"On a phone or tablet the on-screen controls appear automatically. Landscape "
		+ "gives a much wider view.",
		12, UITheme.FAINT
	))

	# Scrolled, and the Back button stays outside the scroll view so it is always
	# reachable however short the screen is.
	outer.add_child(UITheme.scrollable(column, UITheme.scroll_height(viewport, CHROME)))

	var back := UITheme.button("Back")
	back.pressed.connect(func() -> void: _show(_menu))
	outer.add_child(back)

	_controls = UITheme.centre(panel)
	add_child(_controls)


func _build_settings() -> void:
	_settings = SettingsPanel.new()
	_settings.closed.connect(func() -> void: _show(_menu))
	var wrapper: Control = UITheme.centre(_settings)
	add_child(wrapper)
	# The panel is what gets shown/hidden, but the wrapper is what positions it.
	_settings.set_meta("wrapper", wrapper)


## Shows a named panel. Public so the UI harness can photograph each one directly
## rather than by clicking at guessed pixel coordinates — which was unreliable enough
## that a panel overflowing off the bottom of the screen went unnoticed.
func show_panel(which: String) -> void:
	match which:
		"controls":
			_show(_controls)
		"settings":
			_show(_settings)
		_:
			_show(_menu)


func _show(which: Control) -> void:
	for candidate: Control in [_menu, _controls, _settings.get_meta("wrapper")]:
		candidate.visible = candidate == which or candidate == which.get_parent()
	# Settings is wrapped, so match on either the panel or its wrapper.
	if which == _settings:
		(_settings.get_meta("wrapper") as Control).visible = true

	if which == _menu and _play_button != null:
		# Focus so Enter/Space starts the run with no pointer involved.
		_play_button.grab_focus()
