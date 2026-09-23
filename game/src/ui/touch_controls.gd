class_name TouchControls
extends CanvasLayer

## On-screen controls for phones and tablets.
##
## Feeds the same `Input` actions the keyboard uses, so nothing downstream — the
## state machine, the input buffer, coyote time, jump cutting — knows or cares
## which one the player is using. Touch gets the full movement vocabulary, not a
## reduced one.
##
## ### Design decisions
##
## **True multi-touch, tracked per finger.** A parkour game is unplayable if you
## cannot hold a direction and jump at the same time, so each touch index owns its
## own button and is tracked independently in `_touch_owner`. Godot's
## `TouchScreenButton` exists but is `Node2D`-based and awkward to lay out
## responsively, so the buttons are `Control` rects driven by raw
## `InputEventScreenTouch` / `InputEventScreenDrag`.
##
## **Sliding between buttons works.** Thumbs roll rather than tap. A drag that
## leaves one button and enters another releases the first and presses the second,
## which is what makes fast direction changes and jump-to-slide chains feel right
## instead of dropping inputs.
##
## **Hit areas are bigger than they look.** Every button has an invisible margin
## (`TOUCH_PADDING`) around its artwork. Fingers are imprecise and occluded by
## their own hand; a control that is exactly as big as its graphic feels like it
## is missing presses.
##
## **Variable jump height survives.** Jump is press-and-hold, released on lift,
## so tapping gives a short hop and holding gives a full jump exactly as on
## keyboard. This is why the buttons drive actions rather than firing one-shot
## events.
##
## **Layout scales with the screen, not with pixels.** Sizes are derived from the
## viewport's short edge so a 6" phone and a 13" tablet both get controls sized
## for a human thumb. Landscape and portrait get different arrangements.
##
## **Auto-reveal, not a setting.** Shown when a touchscreen is reported, or the
## instant a real touch event arrives (which covers desktop browsers on
## touch-capable hardware, where feature detection lies). Hidden again on
## keyboard input, so a laptop with a touchscreen does not permanently carry a
## thumb UI.

## Extra invisible hit area around each button, as a fraction of its size.
const TOUCH_PADDING: float = 0.22

## Button diameter as a fraction of the viewport's short edge, clamped to a
## sensible pixel range so tiny and huge screens both stay usable.
const ACTION_SIZE_RATIO: float = 0.19
const ACTION_SIZE_MIN: float = 84.0
const ACTION_SIZE_MAX: float = 168.0

const DPAD_SIZE_RATIO: float = 0.17
const DPAD_SIZE_MIN: float = 76.0
const DPAD_SIZE_MAX: float = 150.0

## Distance from the screen edges, as a fraction of the short edge. Generous:
## phone gesture bars and rounded corners eat the outermost band.
const EDGE_MARGIN_RATIO: float = 0.07
const EDGE_MARGIN_MIN: float = 22.0

const IDLE_ALPHA: float = 0.30
const PRESSED_ALPHA: float = 0.82

const INK: Color = Color(0.93, 0.95, 0.98)
const ACCENT: Color = Color(0.94, 0.62, 0.22)

## Emitted when the controls appear or disappear, so the HUD can move anything
## that would end up underneath a thumb.
signal enabled_changed(enabled: bool)

## One on-screen control: an action, a glyph, and its hit rect.
class TouchButton:
	extends Control

	var action: StringName
	var glyph: String = ""
	var accent: Color = TouchControls.INK
	var pressed: bool = false
	## Number of fingers currently on this button. A count rather than a flag so
		## a second finger landing on an already-held button cannot release it when
	## it lifts.
	var holders: int = 0

	var _alpha: float = TouchControls.IDLE_ALPHA
	var _pad: float = 0.0

	func setup(a: StringName, g: String, tint: Color, pad: float) -> void:
		action = a
		glyph = g
		accent = tint
		_pad = pad
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Hit test in global coordinates, expanded by the invisible padding.
	func contains(point: Vector2) -> bool:
		return get_global_rect().grow(_pad).has_point(point)

	func _process(delta: float) -> void:
		var target: float = TouchControls.PRESSED_ALPHA if pressed else TouchControls.IDLE_ALPHA
		var next: float = lerpf(_alpha, target, minf(1.0, 16.0 * delta))
		if not is_equal_approx(next, _alpha):
			_alpha = next
			queue_redraw()

	func _draw() -> void:
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		var centre: Vector2 = size * 0.5
		var radius: float = minf(size.x, size.y) * 0.5

		# Filled disc plus a brighter ring. The ring keeps the control readable
		# against both the pale sky and the dark rooftops without needing a
		# drop shadow.
		draw_circle(centre, radius, Color(0.04, 0.05, 0.07, _alpha * 0.66))
		draw_arc(centre, radius - 1.5, 0.0, TAU, 48, Color(accent, _alpha), 2.5, true)

		if pressed:
			draw_circle(centre, radius * 0.82, Color(accent, _alpha * 0.22))

		_draw_glyph(r, Color(accent, minf(1.0, _alpha + 0.35)))

	## Vector glyphs rather than a font, so the controls carry no text asset, need
	## no translation, and stay crisp at any size.
	func _draw_glyph(r: Rect2, colour: Color) -> void:
		var c: Vector2 = r.size * 0.5
		var s: float = minf(r.size.x, r.size.y)
		var w: float = maxf(2.5, s * 0.075)

		match glyph:
			"left":
				_chevron(c + Vector2(s * 0.04, 0.0), s * 0.2, PI, colour, w)
			"right":
				_chevron(c - Vector2(s * 0.04, 0.0), s * 0.2, 0.0, colour, w)
			"jump":
				# Upward chevron with a ground line: "leave the ground".
				_chevron(c - Vector2(0.0, s * 0.1), s * 0.19, -PI * 0.5, colour, w)
				draw_line(
					c + Vector2(-s * 0.2, s * 0.22),
					c + Vector2(s * 0.2, s * 0.22),
					colour, w, true
				)
			"slide":
				# Downward chevron over a ground line: "get low".
				_chevron(c - Vector2(0.0, s * 0.02), s * 0.19, PI * 0.5, colour, w)
				draw_line(
					c + Vector2(-s * 0.2, s * 0.26),
					c + Vector2(s * 0.2, s * 0.26),
					colour, w, true
				)
			"pause":
				var bar: float = s * 0.09
				var h: float = s * 0.3
				draw_rect(Rect2(c + Vector2(-bar * 1.9, -h * 0.5), Vector2(bar, h)), colour)
				draw_rect(Rect2(c + Vector2(bar * 0.9, -h * 0.5), Vector2(bar, h)), colour)
			"restart":
				draw_arc(c, s * 0.2, PI * 0.35, PI * 1.85, 28, colour, w, true)
				var tip: Vector2 = c + Vector2(cos(PI * 0.35), sin(PI * 0.35)) * s * 0.2
				draw_line(tip, tip + Vector2(-s * 0.1, -s * 0.05), colour, w, true)
				draw_line(tip, tip + Vector2(s * 0.02, -s * 0.11), colour, w, true)

	func _chevron(tip: Vector2, reach: float, angle: float, colour: Color, w: float) -> void:
		var dir: Vector2 = Vector2.RIGHT.rotated(angle)
		var back: Vector2 = -dir * reach
		var spread: Vector2 = dir.orthogonal() * reach * 0.92
		draw_line(tip + back + spread, tip, colour, w, true)
		draw_line(tip + back - spread, tip, colour, w, true)


# ------------------------------------------------------------------------ state

var _buttons: Array[TouchButton] = []
## Which button each active finger is currently on, keyed by touch index.
var _touch_owner: Dictionary[int, TouchButton] = {}
var _root: Control
var _enabled: bool = false


func _ready() -> void:
	layer = 20
	# Must keep drawing and accepting input while the tree is paused, or the
	# pause button becomes a trap with no way back out on a touch device.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build()
	_layout()

	get_viewport().size_changed.connect(_layout)
	set_enabled(_should_start_enabled())


## True when the platform reports a touchscreen.
##
## Deliberately optimistic, and paired with the mouse check in `_input`. Browsers
## report touch capability inconsistently — a desktop Chromium claims a touchscreen
## is available, which put a full thumb UI over the game on a machine that has no
## touchscreen at all. Rather than guess harder up front, the controls appear when
## touch is *plausible* and retreat the moment a mouse or keyboard is actually used.
## Guessing wrong in this direction is recoverable in one mouse movement; guessing
## wrong the other way leaves a tablet player with no controls at all.
func _should_start_enabled() -> bool:
	match Game.touch_mode:
		Game.TouchMode.ALWAYS:
			return true
		Game.TouchMode.NEVER:
			return false
		_:
			pass

	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return true
	if OS.has_feature("web"):
		return _browser_is_mobile()
	return DisplayServer.is_touchscreen_available()


## User-agent check, used only on web.
##
## `DisplayServer.is_touchscreen_available()` is not usable as the primary signal in
## a browser — desktop Chromium answers yes. The user agent is the conventional
## answer to "is this a phone or tablet" on the web precisely because capability
## detection does not distinguish a touchscreen laptop from a tablet.
func _browser_is_mobile() -> bool:
	var agent: Variant = JavaScriptBridge.eval("navigator.userAgent", true)
	if typeof(agent) != TYPE_STRING:
		return false
	var text: String = String(agent).to_lower()
	for token: String in ["android", "iphone", "ipad", "ipod", "mobile", "silk", "kindle"]:
		if text.contains(token):
			return true
	return false


func set_enabled(value: bool) -> void:
	if _enabled == value:
		return
	_enabled = value
	_root.visible = value
	if not value:
		_release_all()
	enabled_changed.emit(value)


func is_enabled() -> bool:
	return _enabled


# --------------------------------------------------------------------- building

func _build() -> void:
	# Left thumb: direction. Right thumb: actions. Standard for a reason — it
	# matches how players already hold a phone.
	_add_button(&"move_left", "left", INK)
	_add_button(&"move_right", "right", INK)
	_add_button(&"jump", "jump", ACCENT)
	_add_button(&"slide", "slide", INK)
	_add_button(&"pause", "pause", INK)
	_add_button(&"restart", "restart", INK)


func _add_button(action: StringName, glyph: String, tint: Color) -> TouchButton:
	var button := TouchButton.new()
	button.name = String(action)
	button.setup(action, glyph, tint, 0.0)
	_root.add_child(button)
	_buttons.append(button)
	return button


func _get(action: StringName) -> TouchButton:
	for b: TouchButton in _buttons:
		if b.action == action:
			return b
	return null


# ---------------------------------------------------------------------- layout

## Positions every control from the current viewport size.
##
## Recomputed on every resize rather than anchored, because the *arrangement*
## changes with orientation, not just the positions: in portrait there is height
## to spare and the thumbs sit lower and wider apart; in landscape the controls
## hug the bottom corners so they stay out of the action band.
func _layout() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return

	var short_edge: float = minf(view.x, view.y)
	var portrait: bool = view.y > view.x

	var action_size: float = clampf(short_edge * ACTION_SIZE_RATIO, ACTION_SIZE_MIN, ACTION_SIZE_MAX)
	var dpad_size: float = clampf(short_edge * DPAD_SIZE_RATIO, DPAD_SIZE_MIN, DPAD_SIZE_MAX)
	var margin: float = maxf(short_edge * EDGE_MARGIN_RATIO, EDGE_MARGIN_MIN)

	# In portrait the controls sit further up from the bottom edge, clear of the
	# system gesture area, and there is room to separate them more.
	var bottom: float = view.y - margin - (short_edge * 0.06 if portrait else 0.0)
	var gap: float = dpad_size * (0.34 if portrait else 0.22)

	# --- left cluster: direction, side by side -------------------------------
	var left_x: float = margin
	_place(_get(&"move_left"), Vector2(left_x, bottom - dpad_size), Vector2(dpad_size, dpad_size))
	_place(
		_get(&"move_right"),
		Vector2(left_x + dpad_size + gap, bottom - dpad_size),
		Vector2(dpad_size, dpad_size)
	)

	# --- right cluster: jump high, slide low and inboard ----------------------
	# Staggered diagonally rather than stacked: a thumb arcs, so the two most
	# used actions are placed along that arc. Jump is the larger of the two and
	# sits outermost where the thumb rests.
	var jump_size: float = action_size
	var slide_size: float = action_size * 0.86
	var right_x: float = view.x - margin - jump_size
	_place(_get(&"jump"), Vector2(right_x, bottom - jump_size), Vector2(jump_size, jump_size))
	_place(
		_get(&"slide"),
		Vector2(
			right_x - slide_size - gap * 0.7,
			bottom - slide_size - jump_size * (0.34 if portrait else 0.28)
		),
		Vector2(slide_size, slide_size)
	)

	# --- top-right: pause and restart, small and out of the way --------------
	var small: float = clampf(short_edge * 0.1, 44.0, 72.0)
	_place(_get(&"pause"), Vector2(view.x - margin - small, margin), Vector2(small, small))
	_place(
		_get(&"restart"),
		Vector2(view.x - margin - small * 2.0 - gap * 0.4, margin),
		Vector2(small, small)
	)


func _place(button: TouchButton, pos: Vector2, size: Vector2) -> void:
	if button == null:
		return
	button.position = pos
	button.size = size
	# Padding scales with the button so big controls get proportionally generous
	# hit areas rather than a fixed halo.
	button.setup(button.action, button.glyph, button.accent, minf(size.x, size.y) * TOUCH_PADDING)
	button.queue_redraw()


# ----------------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		# First real touch reveals the controls, covering platforms whose feature
		# detection claims there is no touchscreen.
		#
		# Only in AUTO. An explicit NEVER has to win, and this is exactly where it
		# failed to: desktop Chromium delivers *mouse clicks* as screen-touch events
		# when it reports touch capability, so a single click re-enabled a UI the
		# player had switched off.
		if not _enabled and Game.touch_mode == Game.TouchMode.AUTO:
			set_enabled(true)
		elif not _enabled:
			return
		if touch.pressed:
			_begin_touch(touch.index, touch.position)
		else:
			_end_touch(touch.index)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenDrag and _enabled:
		var drag: InputEventScreenDrag = event
		_move_touch(drag.index, drag.position)
		return

	# Real keyboard, mouse or gamepad use means this is not a touch session; get the
	# thumb UI out of the way.
	#
	# Mouse *motion* is included because it is the only reliable signal that a
	# desktop browser's claim of touch capability was wrong. Emulated touch-from-mouse
	# is off, so a genuine motion event cannot have come from a finger.
	if not _enabled:
		return
	if event is InputEventMouseMotion:
		set_enabled(false)
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton:
		if event.is_pressed():
			set_enabled(false)


func _begin_touch(index: int, position: Vector2) -> void:
	var button: TouchButton = _button_at(position)
	if button == null:
		return
	_touch_owner[index] = button
	_press(button)


## Handles a finger sliding from one control to another mid-hold.
func _move_touch(index: int, position: Vector2) -> void:
	var previous: TouchButton = _touch_owner.get(index)
	var current: TouchButton = _button_at(position)
	if previous == current:
		return
	if previous != null:
		_release(previous)
	if current != null:
		_touch_owner[index] = current
		_press(current)
	else:
		_touch_owner.erase(index)


func _end_touch(index: int) -> void:
	var button: TouchButton = _touch_owner.get(index)
	if button != null:
		_release(button)
	_touch_owner.erase(index)


## Topmost control under a point. Later children win, so the small top-right
## controls cannot be stolen by a larger overlapping rect.
func _button_at(position: Vector2) -> TouchButton:
	for i: int in range(_buttons.size() - 1, -1, -1):
		if _buttons[i].contains(position):
			return _buttons[i]
	return null


func _press(button: TouchButton) -> void:
	button.holders += 1
	if button.holders > 1:
		return
	button.pressed = true
	button.queue_redraw()
	# Held, not pulsed. Holding is what preserves variable jump height and
	# sustained slides, and it is what the rest of the input system expects.
	Input.action_press(button.action)


func _release(button: TouchButton) -> void:
	button.holders = maxi(0, button.holders - 1)
	if button.holders > 0:
		return
	button.pressed = false
	button.queue_redraw()
	Input.action_release(button.action)


## Drops every held action. Used when hiding the controls, so a direction cannot
## be left latched on with no visible control to release it.
func _release_all() -> void:
	for button: TouchButton in _buttons:
		if button.holders > 0 or button.pressed:
			button.holders = 0
			button.pressed = false
			button.queue_redraw()
			Input.action_release(button.action)
	_touch_owner.clear()


func _notification(what: int) -> void:
	# Losing focus mid-hold (a call, a notification shade, tab switch) must not
	# leave the runner sprinting into a wall forever.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()
