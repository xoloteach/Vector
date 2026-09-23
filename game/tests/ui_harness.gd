extends Node

## Photographs every interface screen at several resolutions.
##
##   ./scripts/ui_sheet.sh
##
## Built because driving menus with pixel clicks in a browser proved unreliable, and
## the failure was silent: a panel grew taller than the screen, pushed its own Back
## button off the bottom, and the capture simply photographed the same frame seven
## times. Nothing in the logs said anything was wrong.
##
## Here each panel is shown directly by name and rendered at a range of viewport sizes,
## including the shortest one the game realistically has to survive — a phone in
## landscape at 390 px tall, which is shorter than most of these panels want to be.

## Viewport sizes to test. The last two are the ones that actually break layouts.
const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1024, 600),
	Vector2i(844, 390),
	Vector2i(390, 844),
]

const SCREENS: PackedStringArray = ["title", "controls", "settings", "paused", "results"]

var _out_dir: String = "res://../captures/ui_sheet"
var _title: TitleScreen
var _pause: PauseMenu
var _results: ResultsPanel


func _ready() -> void:
	_parse_args()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	print("=== UI sheet -> %s ===" % _out_dir)

	# A backdrop, so panels are judged against something rather than pure black —
	# contrast against gameplay is the whole reason the scrim exists.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.13, 0.16, 0.23)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = -10
	layer.add_child(backdrop)
	add_child(layer)

	await _shoot_all()


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			_out_dir = args[i + 1]


func _shoot_all() -> void:
	var failures: int = 0

	for size: Vector2i in SIZES:
		DisplayServer.window_set_size(size)
		get_viewport().size = size
		await get_tree().process_frame
		await get_tree().process_frame
		# Same adaptive scale the game applies, so the sheet measures what ships.
		UITheme.apply_adaptive_scale(get_window())
		await get_tree().process_frame

		_rebuild_ui()
		await get_tree().process_frame

		var space: Vector2 = get_viewport().get_visible_rect().size
		var ui_scale: float = float(size.y) / maxf(1.0, space.y)
		# A 14 px label is the smallest text in the interface. Below roughly 9 physical
		# pixels it stops being readable on a phone, which is a usability failure even
		# though nothing overflows.
		var smallest_px: float = 14.0 * ui_scale
		print("  %dx%d: 2D space %.0fx%.0f, ui scale %.2f, smallest text %.1f px%s" % [
			size.x, size.y, space.x, space.y, ui_scale, smallest_px,
			"  <-- TOO SMALL" if smallest_px < 9.0 else "",
		])

		for screen: String in SCREENS:
			_show(screen)
			for _i: int in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw

			var overflow: String = _check_overflow(screen, get_viewport().get_visible_rect().size)
			if overflow != "":
				print("  OVERFLOW %s @ %dx%d: %s" % [screen, size.x, size.y, overflow])
				failures += 1

			var image: Image = get_viewport().get_texture().get_image()
			var path: String = "%s/%dx%d-%s.png" % [_out_dir, size.x, size.y, screen]
			if image.save_png(path) != OK:
				printerr("failed to write %s" % path)
			else:
				print("  wrote %dx%d-%s.png" % [size.x, size.y, screen])

	print("")
	if failures > 0:
		print("UI SHEET: FAIL (%d panel(s) larger than the screen)" % failures)
		get_tree().call_deferred("quit", 1)
		return
	print("UI SHEET: DONE")
	get_tree().call_deferred("quit", 0)


func _rebuild_ui() -> void:
	for node: Node in [_title, _pause, _results]:
		if node != null:
			node.free()

	_title = TitleScreen.new()
	add_child(_title)
	_pause = PauseMenu.new()
	add_child(_pause)
	_results = ResultsPanel.new()
	add_child(_results)


func _show(screen: String) -> void:
	_title.visible = screen in ["title", "controls", "settings"]
	_pause.visible = screen == "paused"
	_results.visible = screen == "results"

	match screen:
		"title":
			_title.show_panel("menu")
		"controls":
			_title.show_panel("controls")
		"settings":
			_title.show_panel("settings")
		"results":
			_results.show_result("CAUGHT", "Keep moving. Stalling is what lets the drone close.")


## Reports any visible panel larger than the **2D coordinate space**.
##
## Measuring against the window's pixel size is wrong, and produced four phantom
## failures before this was understood. The project uses `canvas_items` stretch, so the
## interface is laid out in a fixed 2D space (720 units tall) and then scaled to
## whatever the window is. A 566-unit-tall panel on a 390 px screen is not overflowing —
## it is being scaled to 79% of the display.
##
## What *is* worth checking is the layout against its own coordinate space, which is
## what this now does. The genuine small-screen risk is legibility, reported separately.
func _check_overflow(screen: String, size: Vector2) -> String:
	var roots: Array[Node] = []
	match screen:
		"paused":
			roots.append(_pause)
		"results":
			roots.append(_results)
		_:
			roots.append(_title)

	var worst: String = ""
	for root: Node in roots:
		for panel: PanelContainer in _find_panels(root):
			if not panel.is_visible_in_tree():
				continue
			var rect: Rect2 = panel.get_global_rect()
			if rect.size.y > size.y + 1.0:
				worst = "height %.0f > %.0f (2D space)" % [rect.size.y, size.y]
			elif rect.size.x > size.x + 1.0:
				worst = "width %.0f > %.0f (2D space)" % [rect.size.x, size.x]
	return worst


func _find_panels(node: Node) -> Array[PanelContainer]:
	var found: Array[PanelContainer] = []
	if node is PanelContainer:
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(_find_panels(child))
	return found
