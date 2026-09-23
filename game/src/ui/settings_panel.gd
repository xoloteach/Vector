class_name SettingsPanel
extends PanelContainer

## Audio, graphics and control settings.
##
## Used by both the title screen and the pause menu rather than duplicated, because
## a setting that exists in one place and not the other is the kind of inconsistency
## nobody notices until a player complains.
##
## Deliberately short. Every option here is one a player might actually need:
## volume because games are played alongside other things, quality because the
## browser target spans phones to desktops, and the touch-control override because
## browser touch detection is genuinely unreliable and someone will be on the wrong
## side of it.

signal closed

var _on_close: Callable


func _ready() -> void:
	_build()


func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.PANEL_BG
	style.border_color = UITheme.PANEL_EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(UITheme.CORNER)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 26
	style.content_margin_bottom = 26
	add_theme_stylebox_override("panel", style)

	# Heading and Back live outside the scroll view so they are always reachable; the
	# options scroll. On a 390 px-tall phone in landscape this panel is taller than the
	# screen, and a panel that hides its own close button strands the player.
	const PADDING: float = 24.0
	# Heading, Back button, separations and padding live outside the scroll view.
	const CHROME: float = 150.0
	var viewport: Vector2 = get_viewport().get_visible_rect().size

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	outer.custom_minimum_size = Vector2(
		UITheme.content_width(340.0, viewport, PADDING), 0
	)
	add_child(outer)
	outer.add_child(UITheme.heading("SETTINGS", 22))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)

	# --- audio ---------------------------------------------------------------
	column.add_child(UITheme.caption("AUDIO"))

	var master: Array = UITheme.slider_row("Master", Game.master_volume)
	column.add_child(master[0])
	(master[1] as HSlider).value_changed.connect(func(v: float) -> void:
		Game.master_volume = v
		Game.volumes_changed.emit()
	)

	var music: Array = UITheme.slider_row("Music", Game.music_volume)
	column.add_child(music[0])
	(music[1] as HSlider).value_changed.connect(func(v: float) -> void:
		Game.music_volume = v
		Game.volumes_changed.emit()
	)

	var sfx: Array = UITheme.slider_row("Effects", Game.sfx_volume)
	column.add_child(sfx[0])
	(sfx[1] as HSlider).value_changed.connect(func(v: float) -> void:
		Game.sfx_volume = v
		Game.volumes_changed.emit()
	)

	column.add_child(_separator())

	# --- graphics ------------------------------------------------------------
	column.add_child(UITheme.caption("GRAPHICS"))
	var quality := OptionButton.new()
	quality.custom_minimum_size = Vector2(0, 42)
	quality.add_item("High", Game.Quality.HIGH)
	quality.add_item("Balanced", Game.Quality.BALANCED)
	quality.add_item("Performance", Game.Quality.PERFORMANCE)
	quality.selected = int(Game.quality)
	quality.item_selected.connect(func(index: int) -> void:
		Game.quality = index as Game.Quality
	)
	column.add_child(quality)
	column.add_child(UITheme.body(
		"Performance disables shadows and particles. Try it if the frame rate dips.",
		12, UITheme.FAINT
	))

	column.add_child(_separator())

	# --- controls ------------------------------------------------------------
	column.add_child(UITheme.caption("ON-SCREEN CONTROLS"))
	var touch := OptionButton.new()
	touch.custom_minimum_size = Vector2(0, 42)
	touch.add_item("Automatic", Game.TouchMode.AUTO)
	touch.add_item("Always show", Game.TouchMode.ALWAYS)
	touch.add_item("Never show", Game.TouchMode.NEVER)
	touch.selected = int(Game.touch_mode)
	touch.item_selected.connect(func(index: int) -> void:
		Game.touch_mode = index as Game.TouchMode
	)
	column.add_child(touch)

	outer.add_child(UITheme.scrollable(column, UITheme.scroll_height(viewport, CHROME)))

	var close := UITheme.button("Back")
	close.pressed.connect(func() -> void: closed.emit())
	outer.add_child(close)


func _separator() -> HSeparator:
	var line := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.07)
	style.content_margin_top = 1
	line.add_theme_stylebox_override("separator", style)
	return line
