class_name ResultsPanel
extends CanvasLayer

## End-of-run screen, for both death and completion.
##
## One panel for both outcomes rather than two. They share their entire structure —
## a headline, a reason or a time, and the same two choices — and splitting them
## would mean maintaining two nearly identical screens that drift apart.
##
## ### Why it has buttons and not just "press R"
##
## The HUD's earlier banner said "Press R to run it again", which is unusable on a
## touch device: there is no R. Real buttons work for keyboard, pointer and touch
## alike, and the keyboard shortcut still works alongside them for players who never
## want to leave the keys.
##
## A short delay before the buttons become active stops a player who was mashing
## jump at the moment of death from instantly skipping past the result.

signal retry_requested
signal title_requested

## How long before input is accepted, in seconds.
const ARM_DELAY: float = 0.35

var _root: Control
var _headline: Label
var _detail: Label
var _hint: Label
var _retry: Button
var _armed: bool = false


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.add_child(UITheme.scrim(0.6))

	var panel: PanelContainer = UITheme.panel(32)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.custom_minimum_size = Vector2(320, 0)
	panel.add_child(column)

	_headline = UITheme.title("", 44)
	column.add_child(_headline)

	_detail = UITheme.body("", 16, UITheme.DIM)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_detail)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	column.add_child(spacer)

	_retry = UITheme.button("Run it again", true, true)
	_retry.pressed.connect(_on_retry)
	column.add_child(_retry)

	var title_button := UITheme.button("Quit to title")
	title_button.pressed.connect(func() -> void:
		if _armed:
			title_requested.emit()
	)
	column.add_child(title_button)

	_hint = UITheme.caption("R to restart")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)

	_root.add_child(UITheme.centre(panel))

	Game.run_failed.connect(_on_run_failed)
	Game.run_completed.connect(_on_run_completed)
	Game.run_started.connect(_on_run_started)


func _on_run_started() -> void:
	visible = false
	_armed = false


func _on_run_failed(reason: String) -> void:
	_show(_fail_headline(reason), _fail_detail(reason))


func _on_run_completed(elapsed: float) -> void:
	_show(
		"ROUTE CLEAR",
		"%s   ·   %d attempt%s" % [
			Game.format_time(elapsed),
			Game.attempts,
			"" if Game.attempts == 1 else "s",
		]
	)


## Public entry point for the UI harness, so the results screen can be photographed
## without having to actually die.
func show_result(headline: String, detail: String) -> void:
	_show(headline, detail)


func _show(headline: String, detail: String) -> void:
	_headline.text = headline
	_detail.text = detail
	visible = true
	_armed = false
	# Arm after a beat, so a death during a jump-mash does not skip the screen.
	await get_tree().create_timer(ARM_DELAY).timeout
	if visible:
		_armed = true
		_retry.grab_focus()


func _on_retry() -> void:
	if _armed:
		retry_requested.emit()


func _process(_delta: float) -> void:
	# Polled rather than event-driven, so touch, keyboard and gamepad all work — see
	# the input rules in AGENTS.md.
	if visible and _armed and Input.is_action_just_pressed(&"restart"):
		retry_requested.emit()


func _fail_headline(reason: String) -> String:
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


## The detail line is coaching, not flavour. Each failure gets the one piece of
## advice that would actually have prevented it.
func _fail_detail(reason: String) -> String:
	match reason:
		Game.FAIL_FELL:
			return "Carry more speed into the gap — a running jump goes much further."
		Game.FAIL_IMPACT:
			return "Time a slide as you touch down to roll out of a long drop."
		Game.FAIL_CAUGHT:
			return "Keep moving. Stalling is what lets the drone close."
		_:
			return "Try a different line."
