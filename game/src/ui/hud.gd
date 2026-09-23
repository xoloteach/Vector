class_name HUD
extends CanvasLayer

## In-run interface: timer, speed, progress, and the retry prompt.
##
## Built in code rather than as a scene tree. UI this simple is easier to read,
## diff and reason about as a constructor than as a wall of anchor values, and it
## keeps every layout decision next to the reason for it.
##
## Design rule: the HUD must never occupy the middle band of the screen. In a
## side-scroller the player's eye lives slightly ahead of the character, dead
## centre-right, and anything drawn there competes with the obstacle they are
## about to hit.

const MARGIN: int = 22
const ACCENT: Color = Color(0.94, 0.62, 0.22)
const INK: Color = Color(0.93, 0.95, 0.98)
const DIM: Color = Color(0.62, 0.67, 0.76)
const THREAT_CALM: Color = Color(0.45, 0.55, 0.68)
const THREAT_DANGER: Color = Color(0.92, 0.32, 0.22)

var _timer_label: Label
var _speed_bar: ProgressBar
var _progress_bar: ProgressBar
var _meters: VBoxContainer
var _state_label: Label
var _rotate_hint: Label
var _threat_box: VBoxContainer
var _threat_bar: ProgressBar
var _threat_label: Label
var _threat_fill: StyleBoxFlat
var _touch_mode: bool = false
var _banner: PanelContainer
var _banner_title: Label
var _banner_hint: Label
var _debug_visible: bool = false

var _player: Player
var _level: Level


func _ready() -> void:
	layer = 10
	# The HUD must keep updating while the tree is paused, otherwise the death
	# and pause overlays freeze along with the world.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_top_left()
	_build_bottom()
	_build_banner()
	_build_debug()

	Game.run_failed.connect(_on_run_failed)
	Game.run_completed.connect(_on_run_completed)
	Game.run_started.connect(_on_run_started)


func bind(player: Player, level: Level) -> void:
	_player = player
	_level = level

	# The threat meter only exists when something is actually chasing. A permanent
	# alarm on a calm run devalues the cue.
	if _level != null and _level.director != null:
		_threat_box.visible = true
		_level.director.danger_changed.connect(_on_danger_changed)


# ------------------------------------------------------------------ construction

func _build_top_left() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	box.position = Vector2(MARGIN, MARGIN)
	box.add_theme_constant_override("separation", 2)
	add_child(box)

	var caption := Label.new()
	caption.text = "TIME"
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", DIM)
	box.add_child(caption)
	_build_rotate_hint()

	_timer_label = Label.new()
	_timer_label.text = "0:00.000"
	_timer_label.add_theme_font_size_override("font_size", 30)
	_timer_label.add_theme_color_override("font_color", INK)
	box.add_child(_timer_label)


func _build_bottom() -> void:
	# Speed and route sit **top-left, directly under the timer** — permanently.
	#
	# They started in the bottom-left corner, which meant they had to move out of the
	# way whenever the touch controls appeared. That conditional layout was wrong in
	# practice and resisted two attempts to fix it, so it is gone: a single position
	# that is always correct beats a clever one that is sometimes correct. Stacked
	# under the timer they read as one information column, which is arguably better
	# than the original anyway, and nothing can ever end up under a thumb.
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	box.position = Vector2(MARGIN, MARGIN + 62)
	box.custom_minimum_size = Vector2(190, 0)
	box.add_theme_constant_override("separation", 3)
	add_child(box)
	_meters = box

	var caption := Label.new()
	caption.text = "SPEED"
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", DIM)
	box.add_child(caption)

	_speed_bar = _make_bar(ACCENT)
	box.add_child(_speed_bar)

	var progress_caption := Label.new()
	progress_caption.text = "ROUTE"
	progress_caption.add_theme_font_size_override("font_size", 11)
	progress_caption.add_theme_color_override("font_color", DIM)
	box.add_child(progress_caption)

	_progress_bar = _make_bar(Color(0.45, 0.78, 0.92))
	box.add_child(_progress_bar)

	# Threat meter. Bottom-centre rather than in the corner cluster, because unlike
	# speed and route this is information the player must react to, and it needs to
	# be inside the area their eyes already cover. Hidden entirely when nothing is
	# chasing, so a calm run has no permanent alarm on screen.
	_threat_box = VBoxContainer.new()
	_threat_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_threat_box.anchor_left = 0.5
	_threat_box.anchor_right = 0.5
	_threat_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_threat_box.offset_top = -54
	_threat_box.custom_minimum_size = Vector2(240, 0)
	_threat_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_threat_box.add_theme_constant_override("separation", 3)
	_threat_box.visible = false
	add_child(_threat_box)

	_threat_label = Label.new()
	_threat_label.text = "PURSUIT"
	_threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_threat_label.add_theme_font_size_override("font_size", 11)
	_threat_label.add_theme_color_override("font_color", DIM)
	_threat_box.add_child(_threat_label)

	_threat_bar = _make_bar(THREAT_CALM)
	_threat_bar.custom_minimum_size = Vector2(240, 6)
	_threat_fill = _last_fill_style
	_threat_box.add_child(_threat_bar)


## Keeps a reference to the last fill stylebox created, so the threat bar can
## recolour itself as danger rises.
var _last_fill_style: StyleBoxFlat


func _make_bar(fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	bar.custom_minimum_size = Vector2(180, 7)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.1)
	bg.corner_radius_top_left = 3
	bg.corner_radius_top_right = 3
	bg.corner_radius_bottom_left = 3
	bg.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("background", bg)

	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.corner_radius_top_left = 3
	fg.corner_radius_top_right = 3
	fg.corner_radius_bottom_left = 3
	fg.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("fill", fg)
	_last_fill_style = fg
	return bar


func _build_banner() -> void:
	# The HUD no longer draws an end-of-run banner. `ResultsPanel` owns that, because
	# a banner saying "press R" is unusable on a touch device and the outcome screen
	# needs real buttons.
	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	# Sits slightly above centre so the runner's body stays visible underneath it.
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.28
	_banner.anchor_bottom = 0.28
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.86)
	style.border_color = Color(1, 1, 1, 0.09)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	_banner.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	_banner.add_child(box)

	_banner_title = Label.new()
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_font_size_override("font_size", 34)
	_banner_title.add_theme_color_override("font_color", INK)
	box.add_child(_banner_title)

	_banner_hint = Label.new()
	_banner_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_hint.add_theme_font_size_override("font_size", 15)
	_banner_hint.add_theme_color_override("font_color", DIM)
	box.add_child(_banner_hint)

	add_child(_banner)


## A quiet suggestion to rotate, shown only on screens too narrow to frame the
## game well.
##
## The camera already adapts to portrait so the game stays playable, but a side-view
## runner genuinely wants a wide screen: in portrait there is far less track
## visible ahead, which costs reaction time. Rather than silently serving the worse
## experience, say so — once, unobtrusively, and never as a blocking overlay,
## because being unable to play at all is worse than playing in portrait.
func _build_rotate_hint() -> void:
	_rotate_hint = Label.new()
	_rotate_hint.text = "↻  Rotate for a wider view"
	_rotate_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_rotate_hint.anchor_left = 0.5
	_rotate_hint.anchor_right = 0.5
	_rotate_hint.anchor_top = 0.0
	_rotate_hint.anchor_bottom = 0.0
	_rotate_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_rotate_hint.offset_top = 14
	_rotate_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rotate_hint.add_theme_font_size_override("font_size", 14)
	_rotate_hint.add_theme_color_override("font_color", Color(INK, 0.72))
	_rotate_hint.visible = false
	add_child(_rotate_hint)

	get_viewport().size_changed.connect(_update_rotate_hint)
	_update_rotate_hint()


func _update_rotate_hint() -> void:
	if _rotate_hint == null:
		return
	# Only worth saying on a device that can actually be rotated.
	var touch_device: bool = _touch_mode or DisplayServer.is_touchscreen_available()
	var camera: ParkourCamera = _level.camera if _level != null else null
	var cramped: bool = camera.is_aspect_cramped() if camera != null else false
	_rotate_hint.visible = touch_device and cramped


func _build_debug() -> void:
	_state_label = Label.new()
	_state_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_state_label.position = Vector2(-320, MARGIN)
	_state_label.custom_minimum_size = Vector2(300, 0)
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_state_label.add_theme_font_size_override("font_size", 13)
	_state_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.65))
	_state_label.visible = false
	add_child(_state_label)


# ----------------------------------------------------------------------- updates

func _process(_delta: float) -> void:
	_check_debug_toggle()
	_timer_label.text = Game.format_time(Game.run_time)

	if _player == null:
		return

	_speed_bar.value = _player.speed_ratio()

	if _level != null and _level.course_length > 0.0:
		_progress_bar.value = clampf(_player.global_position.x / _level.course_length, 0.0, 1.0)

	if _level != null and _level.director != null and _threat_box.visible:
		var intensity: float = _level.director.intensity()
		_threat_bar.value = intensity
		# Colour carries the same information as length, so the cue survives being
		# seen only out of the corner of the eye.
		if _threat_fill != null:
			_threat_fill.bg_color = THREAT_CALM.lerp(THREAT_DANGER, intensity)

	if _debug_visible:
		_state_label.text = _debug_text()


func _debug_text() -> String:
	var sensor: ParkourSensor = _player.sensor
	var lines: Array[String] = [
		"state   %s" % _player.state_name(),
		"vel     %5.1f, %5.1f" % [_player.velocity.x, _player.velocity.y],
		"floor   %s   coyote %.2f" % [_player.is_on_floor(), _player.coyote_timer],
		"pos     %6.1f, %5.1f" % [_player.global_position.x, _player.global_position.y],
		"fps     %d" % Engine.get_frames_per_second(),
	]
	if sensor != null:
		lines.append("obst    %s  h=%.2f d=%.2f" % [
			sensor.obstacle_name(), sensor.obstacle_height, sensor.obstacle_distance
		])
		lines.append("gap     %s  depth=%.1f" % [sensor.gap_ahead, sensor.gap_depth])
	return "\n".join(lines)


func _check_debug_toggle() -> void:
	# Polled rather than event-driven, for the same reason as the level's restart
	# and pause: synthetic actions from the touch controls have no InputEvent.
	if Input.is_action_just_pressed(&"debug_toggle"):
		_debug_visible = not _debug_visible
		_state_label.visible = _debug_visible


## Notes whether the on-screen controls are showing.
##
## No longer moves anything — the meters live permanently top-left, clear of both
## thumbs. Retained because the rotate hint should only appear on a device that can
## actually be rotated.
func set_touch_mode(active: bool) -> void:
	if _touch_mode == active:
		return
	_touch_mode = active
	_update_rotate_hint()


# ------------------------------------------------------------------------ events

func _on_danger_changed(in_danger: bool) -> void:
	_threat_label.text = "PURSUIT — CLOSE" if in_danger else "PURSUIT"
	_threat_label.add_theme_color_override(
		"font_color", THREAT_DANGER if in_danger else DIM
	)


func _on_run_started() -> void:
	_banner.visible = false


func _on_run_failed(reason: String) -> void:
	_show_banner(_fail_title(reason), "Press  R  to run it again")


func _on_run_completed(elapsed: float) -> void:
	_show_banner("ROUTE CLEAR", "%s      Press  R  to run it again" % Game.format_time(elapsed))


func _show_banner(title: String, hint: String) -> void:
	# Intentionally inert. `ResultsPanel` presents outcomes now, with real buttons that
	# work on touch. The builders are kept because the debug overlay still reuses the
	# styling, but the banner must never appear alongside the results panel.
	_banner_title.text = title
	_banner_hint.text = hint
	_banner.visible = false


func _fail_title(reason: String) -> String:
	match reason:
		Game.FAIL_FELL:
			return "FELL"
		Game.FAIL_IMPACT:
			return "BAD LANDING"
		Game.FAIL_CAUGHT:
			return "CAUGHT"
		Game.FAIL_HAZARD:
			return "DOWN"
		_:
			return "RUN ENDED"
