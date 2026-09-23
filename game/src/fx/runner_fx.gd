class_name RunnerFX
extends Node3D

## Particle effects for the runner: landing dust, slide grit, vault puffs, wall scuff.
##
## Every effect here exists to answer a gameplay question, not to decorate:
##
##  - **Landing dust** scales with impact speed, so the player learns to read how
##    expensive a drop was from the *world* rather than from a number. A soft hop
##    barely puffs; a roll-worthy drop throws a visible cloud.
##  - **Slide grit** marks the contact point, which is the one thing a slide's pose
##    cannot show — it makes the difference between sliding and hovering legible.
##  - **Vault puffs** fire at the hand/foot plant, confirming the runner actually
##    touched the obstacle rather than passing through it.
##  - **Wall scuff** does the same job for a wall run, where the contact is otherwise
##    entirely implied.
##
## `CPUParticles3D`, not `GPUParticles3D`. The target is WebGL2 through the
## compatibility renderer, where GPU particles carry caveats and CPU particles simply
## work. Counts are deliberately tiny — a dozen quads per burst — so there is nothing
## to gain from the GPU path anyway.

## Emitters are created once and re-triggered, rather than instanced per event.
## Allocation during gameplay is the one thing a browser build cannot afford to do
## casually, and these effects fire constantly.
var _land: CPUParticles3D
var _slide: CPUParticles3D
var _vault: CPUParticles3D
var _scuff: CPUParticles3D

var _player: Player


func setup(player: Player) -> void:
	_player = player
	player.landed.connect(_on_landed)
	player.slid.connect(_on_slid)
	player.vaulted.connect(_on_vaulted)
	player.climbed.connect(_on_climbed)
	player.wall_ran.connect(_on_wall_ran)
	player.rolled.connect(_on_rolled)


## Turned off by the Performance quality preset. Particles are one of the two things
## in this scene that actually cost frames on a weak device.
var _enabled: bool = true


func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		for emitter: CPUParticles3D in [_land, _slide, _vault, _scuff]:
			if emitter != null:
				emitter.emitting = false


func _ready() -> void:
	_land = _make_emitter("LandDust", 18, Color(0.72, 0.74, 0.8, 0.5), 0.13)
	_slide = _make_emitter("SlideGrit", 26, Color(0.78, 0.76, 0.72, 0.42), 0.075)
	_vault = _make_emitter("VaultPuff", 10, Color(0.7, 0.73, 0.79, 0.4), 0.09)
	_scuff = _make_emitter("WallScuff", 14, Color(0.68, 0.7, 0.76, 0.45), 0.08)

	# Slide grit runs continuously while sliding rather than as a burst.
	_slide.one_shot = false
	_slide.emitting = false
	_slide.lifetime = 0.5
	_slide.direction = Vector3(-1.0, 0.45, 0.0)
	_slide.spread = 26.0


func _make_emitter(
	emitter_name: String,
	amount: int,
	colour: Color,
	size: float
) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = emitter_name
	particles.emitting = false
	particles.one_shot = true
	particles.amount = amount
	particles.lifetime = 0.62
	particles.explosiveness = 0.85
	particles.local_coords = false

	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	particles.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = colour
	mat.vertex_color_use_as_albedo = true
	# Never occlude the runner or write depth: dust is atmosphere, and a puff that
	# hides the character defeats the point of a silhouette-led game.
	mat.no_depth_test = false
	mat.disable_receive_shadows = true
	particles.material_override = mat

	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 55.0
	particles.gravity = Vector3(0.0, -3.4, 0.0)
	particles.initial_velocity_min = 0.8
	particles.initial_velocity_max = 2.6
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.6
	# Fade and shrink over life, so dust dissipates instead of vanishing.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.25))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = curve

	add_child(particles)
	return particles


func _process(_delta: float) -> void:
	if _player == null:
		return

	if not _enabled:
		return

	# Slide grit follows the feet for as long as the slide lasts.
	var sliding: bool = _player.state_name() == PlayerState.SLIDE
	if sliding:
		_slide.global_position = _player.global_position + Vector3(
			-_player.facing * 0.3, 0.08, 0.0
		)
		# Grit is thrown backwards relative to travel.
		_slide.direction = Vector3(-_player.facing, 0.5, 0.0)
		_slide.initial_velocity_max = 1.4 + _player.horizontal_speed() * 0.22
	if _slide.emitting != sliding:
		_slide.emitting = sliding


func _burst(emitter: CPUParticles3D, position: Vector3, strength: float) -> void:
	if not _enabled:
		return
	emitter.global_position = position
	emitter.initial_velocity_max = lerpf(1.4, 5.0, strength)
	emitter.amount = int(lerpf(6.0, float(emitter.amount), maxf(0.3, strength)))
	emitter.restart()


func _on_landed(impact_speed: float, hard: bool) -> void:
	# Proportional to impact, so the world reports the cost of a drop.
	var strength: float = clampf(impact_speed / 30.0, 0.0, 1.0)
	if hard:
		strength = maxf(strength, 0.8)
	if strength < 0.12:
		return  # a gentle step does not kick up dust
	_burst(_land, _player.global_position + Vector3(0.0, 0.06, 0.0), strength)


func _on_rolled(_impact_speed: float) -> void:
	_burst(_land, _player.global_position + Vector3(0.0, 0.1, 0.0), 0.9)


func _on_slid() -> void:
	_burst(_vault, _player.global_position + Vector3(0.0, 0.1, 0.0), 0.5)


func _on_vaulted(high: bool) -> void:
	# At the plant point, slightly ahead and at hand height for a high vault.
	var offset := Vector3(
		_player.facing * 0.42,
		1.0 if high else 0.55,
		0.0
	)
	_burst(_vault, _player.global_position + offset, 0.55 if high else 0.4)


func _on_climbed(_height: float) -> void:
	_burst(_scuff, _player.global_position + Vector3(_player.facing * 0.4, 1.1, 0.0), 0.6)


func _on_wall_ran() -> void:
	_burst(_scuff, _player.global_position + Vector3(_player.facing * 0.4, 0.9, 0.0), 0.75)
