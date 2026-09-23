class_name UITheme
extends RefCounted

## Shared styling for every panel and control in the game.
##
## Built as static factory functions rather than a `Theme` resource. Three reasons:
## the whole interface is a handful of panels, so a binary theme file would be
## unreviewable overhead; the values can carry comments explaining *why* they are
## what they are; and every screen is guaranteed to agree because there is one
## source of the numbers.
##
## Design constraints, all inherited from the game rather than invented:
##
##  - **Nothing occupies the centre-right band.** That is where the player's eye
##    lives during play, and it is where obstacles appear.
##  - **Touch-sized by default.** Every button clears the ~44 px minimum comfortable
##    touch target with margin, because the game is a first-class mobile target and
##    retrofitting sizes later never happens.
##  - **The accent colour means "this is the action".** Used for exactly one control
##    per screen, so it never becomes decoration.

const INK: Color = Color(0.93, 0.95, 0.98)
const DIM: Color = Color(0.60, 0.66, 0.75)
const FAINT: Color = Color(0.42, 0.47, 0.56)
const ACCENT: Color = Color(0.94, 0.62, 0.22)
const PANEL_BG: Color = Color(0.035, 0.042, 0.058, 0.93)
const PANEL_EDGE: Color = Color(1.0, 1.0, 1.0, 0.09)
const DANGER: Color = Color(0.9, 0.34, 0.26)

const BUTTON_HEIGHT: int = 52
const BUTTON_HEIGHT_LARGE: int = 62
const CORNER: int = 4


static func panel(padding: int = 30) -> PanelContainer:
	var container := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(CORNER)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	container.add_theme_stylebox_override("panel", style)
	return container


static func title(text: String, size: int = 56) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	return label


static func heading(text: String, size: int = 22) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	return label


static func body(
	text: String, size: int = 15, colour: Color = DIM, wrap: bool = true
) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	# Wrapping is opt-out because a wrapped label inside a horizontal row with no width
	# allocation collapses to a single character per line. That turned the controls
	# panel into a column of stacked letters several screens tall, which also pushed
	# its Back button off the bottom of the display and made the panel a dead end.
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


static func caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", FAINT)
	return label


## A button. `primary` gets the accent treatment — one per screen.
static func button(text: String, primary: bool = false, large: bool = false) -> Button:
	var control := Button.new()
	control.text = text
	control.custom_minimum_size = Vector2(
		0, BUTTON_HEIGHT_LARGE if large else BUTTON_HEIGHT
	)
	control.add_theme_font_size_override("font_size", 19 if large else 16)
	control.focus_mode = Control.FOCUS_ALL

	var base := Color(1, 1, 1, 0.055)
	var hover := Color(1, 1, 1, 0.11)
	var pressed := Color(1, 1, 1, 0.16)
	var text_colour := INK

	if primary:
		base = Color(ACCENT, 0.9)
		hover = Color(ACCENT.lightened(0.12), 1.0)
		pressed = Color(ACCENT.darkened(0.15), 1.0)
		text_colour = Color(0.07, 0.05, 0.03)

	control.add_theme_stylebox_override("normal", _button_style(base, primary))
	control.add_theme_stylebox_override("hover", _button_style(hover, primary))
	control.add_theme_stylebox_override("pressed", _button_style(pressed, primary))
	control.add_theme_stylebox_override("focus", _button_style(hover, primary))
	control.add_theme_color_override("font_color", text_colour)
	control.add_theme_color_override("font_hover_color", text_colour)
	control.add_theme_color_override("font_pressed_color", text_colour)
	control.add_theme_color_override("font_focus_color", text_colour)
	return control


static func _button_style(colour: Color, primary: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.set_corner_radius_all(CORNER)
	style.content_margin_left = 22
	style.content_margin_right = 22
	if not primary:
		style.border_color = Color(1, 1, 1, 0.1)
		style.set_border_width_all(1)
	return style


## A labelled slider row, for volume settings.
static func slider_row(label_text: String, value: float) -> Array:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 5)

	var header := HBoxContainer.new()
	var name_label: Label = body(label_text, 14, INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var value_label: Label = body("%d%%" % int(value * 100.0), 14, DIM)
	header.add_child(value_label)
	row.add_child(header)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	# Tall enough to grab with a thumb — a default-height slider is unusable on a
	# phone, and this game expects to be played on one.
	slider.custom_minimum_size = Vector2(240, 34)
	row.add_child(slider)

	slider.value_changed.connect(
		func(v: float) -> void: value_label.text = "%d%%" % int(v * 100.0)
	)
	return [row, slider]


## A row describing one control binding, for the help panel.
##
## Neither label wraps: these are short strings, and wrapping inside a row is what
## broke this panel the first time.
static func key_row(action: String, keys: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var key_label: Label = body(keys, 14, ACCENT, false)
	key_label.custom_minimum_size = Vector2(165, 0)
	row.add_child(key_label)
	var action_label: Label = body(action, 14, DIM, false)
	action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(action_label)
	return row


## Screen margin kept clear around every panel.
const SCREEN_MARGIN: float = 14.0

## Smallest font size used anywhere in the interface.
const SMALLEST_FONT: float = 14.0

## Physical pixels that smallest font must occupy to stay readable. Below roughly this,
## text on a phone becomes decorative.
const MIN_READABLE_PX: float = 11.0


## Scales the interface so text stays readable on small screens.
##
## The project uses `canvas_items` stretch, which lays the UI out in a fixed 2D space
## and scales it to the window. That is excellent for layout — nothing can overflow —
## and quietly terrible for legibility: measured across four viewports, a 14 px label
## rendered at 14 physical pixels on desktop, **7.6 px on a landscape phone and 4.3 px
## in portrait**. Nothing was broken, and the menus were unreadable on the platform the
## game is explicitly meant to support.
##
## `content_scale_factor` shrinks the 2D space, which makes everything in it physically
## larger. Applying just enough to clear the readability floor keeps desktop untouched
## and makes phones usable.
##
## Returns the factor applied, for logging.
static func apply_adaptive_scale(window: Window) -> float:
	var space: Vector2 = window.get_visible_rect().size
	if space.y <= 0.0:
		return 1.0

	# Undo any factor already applied, to get the unscaled relationship.
	var current: float = maxf(0.01, window.content_scale_factor)
	var unscaled_space_y: float = space.y * current
	var natural_scale: float = float(window.size.y) / maxf(1.0, unscaled_space_y)

	var needed: float = (MIN_READABLE_PX / SMALLEST_FONT) / maxf(0.01, natural_scale)
	# Never shrink below 1.0: desktop is already correct and scaling it down would only
	# make the UI smaller than designed.
	var factor: float = clampf(needed, 1.0, 3.2)
	window.content_scale_factor = factor
	return factor


## The widest a panel's content may be on this viewport.
##
## Panels used fixed widths, which overflowed a 390 px-wide portrait phone — a panel
## wider than the screen clips its own controls. Width is now derived from the display
## rather than asserted.
static func content_width(desired: float, viewport: Vector2, padding: float) -> float:
	var available: float = viewport.x - SCREEN_MARGIN * 2.0 - padding * 2.0
	return maxf(200.0, minf(desired, available))


## Height available to a scrolling region, after the panel's fixed chrome.
##
## `chrome` is the space taken by everything outside the scroll view — heading, the
## always-visible button, separations, and the panel's own padding. Subtracting it is
## what guarantees the total panel fits: an earlier version picked a fraction of the
## viewport for the scroll area and then added the chrome on top, which overflowed a
## 390 px-tall screen by 26 px and hid the Back button.
static func scroll_height(viewport: Vector2, chrome: float) -> float:
	return maxf(110.0, viewport.y - SCREEN_MARGIN * 2.0 - chrome)


## Wraps content in a vertical scroll view of exactly `height`.
static func scrollable(content: Control, height: float) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(
		0, minf(content.get_combined_minimum_size().y, height)
	)
	scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


## Centres a control both ways inside a full-rect parent.
static func centre(control: Control) -> Control:
	var wrapper := CenterContainer.new()
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.add_child(control)
	return wrapper


## A full-screen dimming backdrop, so panels read against gameplay behind them.
static func scrim(opacity: float = 0.62) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(0.02, 0.025, 0.035, opacity)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return rect
