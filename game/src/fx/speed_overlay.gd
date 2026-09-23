class_name SpeedOverlay
extends CanvasLayer

## Screen-space motion streaks and a threat vignette.
##
## Solves the problem that a side-scroller's speed is genuinely hard to perceive:
## the runner stays in roughly the same place on screen, so the only cue is how fast
## the scenery slides past — and once the backdrop is deliberately low-contrast (as
## it must be, to keep the runner readable) that cue is weak. The critic note was
## blunt: momentum was correct in the numbers and invisible in the image.
##
## Streaks add the missing cue without touching the scene: they read as air moving
## past, they cost nothing, and they scale with actual speed so they never lie.
##
## Drawn in `_draw` rather than as particles or a shader, for three reasons:
##  - it is guaranteed to work on the compatibility renderer,
##  - lines can be placed to *avoid the centre band* where the player is reading
##    obstacles, which particles cannot be trusted to do,
##  - it is a few dozen line draws, which is cheaper than any alternative.
##
## The vignette carries chase pressure. Tying threat to a screen edge effect means
## the player feels the drone closing even while looking at the next gap — the same
## reason the drone's own light grazes nearby geometry.

## Speed fraction below which no streaks are drawn at all. Streaks at walking pace
## would be noise and would devalue them at speed.
const STREAK_THRESHOLD: float = 0.55

## How many streaks at full speed.
const STREAK_COUNT: int = 22

## Vertical band, as a fraction of screen height, kept clear of streaks.
## This is the band the player reads obstacles in; nothing decorative may enter it.
const CLEAR_BAND_TOP: float = 0.34
const CLEAR_BAND_BOTTOM: float = 0.72

const STREAK_COLOUR: Color = Color(0.86, 0.91, 1.0)
const VIGNETTE_COLOUR: Color = Color(0.62, 0.12, 0.08)

var _canvas: Control
var _player: Player
var _threat: float = 0.0
var _smoothed_speed: float = 0.0

## Deterministic streak layout, so captures are comparable between runs.
var _rng := RandomNumberGenerator.new()
var _streaks: Array[Vector3] = []


func setup(player: Player, director: ChaseDirector) -> void:
	_player = player
	if director != null:
		director.intensity_changed.connect(_on_intensity)


func _ready() -> void:
	# Below the HUD (layer 10) and touch controls (20): an atmospheric effect must
	# never sit on top of interface the player needs to read.
	layer = 5
	process_mode = Node.PROCESS_MODE_PAUSABLE

	_canvas = Control.new()
	_canvas.name = "Streaks"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_overlay)
	add_child(_canvas)

	_rng.seed = 90210
	_rebuild_streaks()
	get_viewport().size_changed.connect(_rebuild_streaks)


## Precomputes streak positions as (y_fraction, length_fraction, phase_offset).
func _rebuild_streaks() -> void:
	_streaks.clear()
	for i: int in STREAK_COUNT:
		var y: float = _rng.randf()
		# Push out of the reading band. Remapping rather than rejecting keeps the
		# count stable and the distribution even.
		if y > CLEAR_BAND_TOP and y < CLEAR_BAND_BOTTOM:
			y = CLEAR_BAND_TOP * (y - CLEAR_BAND_TOP) / (CLEAR_BAND_BOTTOM - CLEAR_BAND_TOP) \
				if _rng.randf() < 0.5 \
				else CLEAR_BAND_BOTTOM + (1.0 - CLEAR_BAND_BOTTOM) * _rng.randf()
		_streaks.append(Vector3(
			clampf(y, 0.02, 0.98),
			_rng.randf_range(0.05, 0.19),
			_rng.randf()
		))


func _process(delta: float) -> void:
	if _player == null:
		return
	# Smoothed, because streaks appearing and vanishing on every small speed change
	# flickers badly.
	_smoothed_speed = lerpf(
		_smoothed_speed, _player.speed_ratio(), minf(1.0, 5.0 * delta)
	)
	_canvas.queue_redraw()


func _on_intensity(intensity: float) -> void:
	_threat = intensity


func _draw_overlay() -> void:
	var size: Vector2 = _canvas.size
	if size.x <= 0.0:
		return

	_draw_streaks(size)
	_draw_vignette(size)


func _draw_streaks(size: Vector2) -> void:
	if _smoothed_speed <= STREAK_THRESHOLD:
		return

	# Remap so streaks ramp in from nothing at the threshold to full at top speed.
	var intensity: float = (_smoothed_speed - STREAK_THRESHOLD) / (1.0 - STREAK_THRESHOLD)
	intensity = clampf(intensity, 0.0, 1.0)

	var scroll: float = Time.get_ticks_msec() * 0.001 * (1.6 + 2.8 * intensity)
	var facing: float = _player.facing

	for streak: Vector3 in _streaks:
		var y: float = streak.x * size.y
		var length: float = streak.y * size.x * (0.4 + 0.6 * intensity)
		# Travel opposite the runner's facing: the air moves past them.
		var phase: float = fposmod(streak.z + scroll * 0.5, 1.0)
		var x: float = (1.0 - phase) * (size.x + length) - length * 0.5
		if facing < 0.0:
			x = size.x - x

		# Fade at both screen edges so streaks do not pop into existence.
		var edge_fade: float = minf(1.0, minf(x + length, size.x - x) / (size.x * 0.18))
		var alpha: float = 0.055 + 0.16 * intensity
		alpha *= clampf(edge_fade, 0.0, 1.0)

		var thickness: float = 1.0 + 1.4 * intensity
		_canvas.draw_line(
			Vector2(x, y),
			Vector2(x + length * facing, y),
			Color(STREAK_COLOUR, alpha),
			thickness,
			true
		)


## A soft red vignette that tightens with chase pressure.
##
## Built from concentric border rectangles rather than a shader: on the compatibility
## renderer this is guaranteed to work, and at four bands per edge the cost is
## irrelevant. Deliberately weak at low threat — an effect that is always present
## stops being information.
func _draw_vignette(size: Vector2) -> void:
	if _threat < 0.12:
		return
	var strength: float = pow(clampf((_threat - 0.12) / 0.88, 0.0, 1.0), 1.3)
	var bands: int = 5
	var depth: float = size.y * 0.16 * (0.6 + 0.4 * strength)

	for i: int in bands:
		var t: float = float(i) / float(bands)
		var inset: float = depth * t
		var alpha: float = strength * 0.075 * (1.0 - t)
		var colour := Color(VIGNETTE_COLOUR, alpha)
		var band: float = depth / float(bands)
		# Top, bottom, left, right.
		_canvas.draw_rect(Rect2(0.0, inset, size.x, band), colour)
		_canvas.draw_rect(Rect2(0.0, size.y - inset - band, size.x, band), colour)
		_canvas.draw_rect(Rect2(inset, 0.0, band, size.y), colour)
		_canvas.draw_rect(Rect2(size.x - inset - band, 0.0, band, size.y), colour)
