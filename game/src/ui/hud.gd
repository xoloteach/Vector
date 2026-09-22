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

var _timer_label: Label
var _speed_bar: ProgressBar
var _progress_bar: ProgressBar
var _state_label: Label
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

	_timer_label = Label.new()
	_timer_label.text = "0:00.000"
	_timer_label.add_theme_font_size_override("font_size", 30)
	_timer_label.add_theme_color_override("font_color", INK)
	box.add_child(_timer_label)


func _build_bottom() -> void:
	# Bottom-left: speed. Bottom edge keeps it clear of the action band, and the
	# left side means it sits *behind* the runner in reading order.
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(MARGIN, -76)
	box.custom_minimum_size = Vector2(190, 0)
	box.add_theme_constant_override("separation", 3)
	add_child(box)

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
	return bar


func _build_banner() -> void:
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
	_timer_label.text = Game.format_time(Game.run_time)

	if _player == null:
		return

	_speed_bar.value = _player.speed_ratio()

	if _level != null and _level.course_length > 0.0:
		_progress_bar.value = clampf(_player.global_position.x / _level.course_length, 0.0, 1.0)

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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle"):
		_debug_visible = not _debug_visible
		_state_label.visible = _debug_visible


# ------------------------------------------------------------------------ events

func _on_run_started() -> void:
	_banner.visible = false


func _on_run_failed(reason: String) -> void:
	_show_banner(_fail_title(reason), "Press  R  to run it again")


func _on_run_completed(elapsed: float) -> void:
	_show_banner("ROUTE CLEAR", "%s      Press  R  to run it again" % Game.format_time(elapsed))


func _show_banner(title: String, hint: String) -> void:
	_banner_title.text = title
	_banner_hint.text = hint
	_banner.visible = true


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
