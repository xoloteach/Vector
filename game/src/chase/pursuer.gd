class_name Pursuer
extends Node3D

## The security drone that chases the runner.
##
## Motion only — all difficulty decisions come from `ChaseDirector`. This script's
## job is to make the drone's movement look like a machine tracking a target, and
## to make its *position* honest.
##
## ### Why it flies over the terrain
##
## It samples the ground below itself and hovers a fixed height above it, rather
## than pathfinding or following the runner's exact trajectory. Consequences, all
## intentional:
##
##  - **It cannot be blocked, and it cannot cheat.** There is no navigation to fail
##    and no geometry to clip through. What the player sees is what the rules are.
##  - **Vertical routes cost it nothing, and that is visible.** When the runner
##    drops five metres and the drone simply descends after them, the player can see
##    why the gap did not change. A running pursuer keeping pace over the same drop
##    would look like cheating even if it were not.
##  - **The runner's advantage is horizontal.** The drone is capped below the
##    runner's top speed, so the way to escape is to keep moving — which is the
##    behaviour the whole game is trying to encourage.
##
## Readability is the other half of the job: the sensor eye pulses, rotors spin
## faster under load, and the whole hull banks into acceleration, so the drone's
## state is legible from the corner of the eye without the player ever looking at it.

const MODEL_PATH: String = "res://assets/characters/drone.glb"

@export_group("Flight")
## Height above the terrain the drone tries to hold.
@export var hover_height: float = 2.35
## How quickly it settles onto its hover height. Loose, so it drifts over terrain
## rather than snapping to it — a machine with mass, not a cursor.
@export var vertical_smoothing: float = 2.6
## Horizontal acceleration toward the speed the director asks for.
@export var acceleration: float = 9.0
## Bob amplitude and rate, so it never looks frozen in the air.
@export var bob_amplitude: float = 0.16
@export var bob_rate: float = 1.7

@export_group("Presentation")
## Peak bank angle when accelerating hard, degrees.
@export var bank_degrees: float = 18.0
## Rotor spin rate at cruise and at full load, turns per second.
@export var rotor_rate_cruise: float = 7.0
@export var rotor_rate_max: float = 16.0
## Sensor eye pulse rate at low and high intensity, Hz.
@export var pulse_rate_calm: float = 0.8
@export var pulse_rate_danger: float = 3.4

## How far behind the runner the drone spawns.
@export var start_offset: float = 16.0

var _player: Player
var _director: ChaseDirector
var _model: Node3D
var _rotors: Array[Node3D] = []
var _eye_material: StandardMaterial3D
var _light: OmniLight3D

var _speed: float = 0.0
var _hover_y: float = 0.0
var _bob_phase: float = 0.0
var _rotor_angle: float = 0.0
var _initialised: bool = false


func setup(player: Player, director: ChaseDirector) -> void:
	_player = player
	_director = director


func _ready() -> void:
	_build()


func _build() -> void:
	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("Pursuer could not load %s. Run ./scripts/build_assets.sh." % MODEL_PATH)
		return

	_model = packed.instantiate() as Node3D
	add_child(_model)
	_collect_parts(_model)
	_apply_materials(_model)

	# A small omni light on the drone, tinted to the eye. Does the work a searchlight
	# would without a spot cone: it grazes nearby geometry as the drone closes, so the
	# runner gets a warning in their peripheral vision from the *environment* changing
	# rather than from a UI element.
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.22)
	_light.light_energy = 1.6
	_light.omni_range = 7.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.7, 0.0, 0.0)
	add_child(_light)


## Rotor nodes are named in the GLB so they can be found and spun.
func _collect_parts(node: Node) -> void:
	if node.name.begins_with("Rotor") and node is Node3D:
		_rotors.append(node)
	for child: Node in node.get_children():
		_collect_parts(child)


func _apply_materials(node: Node) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		for surface: int in mesh_instance.mesh.get_surface_count():
			var source: Material = mesh_instance.mesh.surface_get_material(surface)
			var key: String = source.resource_name if source != null else ""
			if key.begins_with("kit_accent"):
				_eye_material = _make_eye_material()
				mesh_instance.set_surface_override_material(surface, _eye_material)
			else:
				# Body stays dark and cool. The drone must never out-read the runner:
				# it is identified by its eye, not by its mass.
				mesh_instance.set_surface_override_material(surface, _make_body_material(key))
	for child: Node in node.get_children():
		_apply_materials(child)


func _make_body_material(key: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = (
		Color(0.16, 0.175, 0.21) if key.begins_with("kit_metal")
		else Color(0.1, 0.11, 0.14)
	)
	mat.roughness = 0.62
	mat.metallic = 0.3
	mat.rim_enabled = true
	mat.rim = 0.5
	return mat


func _make_eye_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.52, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.16)
	mat.emission_energy_multiplier = 2.4
	return mat


func _physics_process(delta: float) -> void:
	if _player == null or _director == null:
		return

	if not _initialised:
		# Spawn behind the runner at hover height, so the chase starts already
		# established rather than materialising next to the player.
		global_position = Vector3(
			_player.global_position.x - start_offset,
			_player.global_position.y + hover_height,
			_player.plane_z
		)
		_hover_y = global_position.y
		_initialised = true

	var distance: float = _player.global_position.x - global_position.x
	_director.report_distance(distance)

	if not _director.is_active():
		# Run is over. Keep flying so the drone does not freeze mid-air, but stop
		# chasing.
		_drift(delta)
		return

	_advance(delta, distance)


func _advance(delta: float, distance: float) -> void:
	var wanted: float = _director.target_speed(distance)
	var previous: float = _speed
	_speed = move_toward(_speed, wanted, acceleration * delta)

	global_position.x += _speed * delta

	# Follow the terrain rather than the runner's exact height: the drone should look
	# like it is flying over the level, not like it is welded to the player.
	var ground: float = _sample_ground()
	var target_y: float = maxf(ground, _player.global_position.y) + hover_height
	_hover_y = lerpf(_hover_y, target_y, 1.0 - exp(-vertical_smoothing * delta))

	_bob_phase += bob_rate * TAU * delta
	global_position.y = _hover_y + sin(_bob_phase) * bob_amplitude
	global_position.z = _player.plane_z

	_present(delta, (_speed - previous) / maxf(delta, 0.0001))


## Keeps the drone airborne after the run ends, decelerating.
func _drift(delta: float) -> void:
	_speed = move_toward(_speed, 0.0, acceleration * 0.6 * delta)
	global_position.x += _speed * delta
	_bob_phase += bob_rate * 0.6 * TAU * delta
	global_position.y = _hover_y + sin(_bob_phase) * bob_amplitude
	_present(delta, 0.0)


## Raycast down to find the terrain the drone is flying over.
func _sample_ground() -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return _player.global_position.y
	var from: Vector3 = Vector3(global_position.x, global_position.y, _player.plane_z)
	var params := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0)
	params.collision_mask = ParkourSensor.SOLID_MASK
	var hit: Dictionary = space.intersect_ray(params)
	return float(hit["position"].y) if not hit.is_empty() else _player.global_position.y


## Rotors, bank and eye pulse. All of it exists so the drone's state is legible in
## peripheral vision, which is the only place the player will ever see it.
func _present(delta: float, acceleration_now: float) -> void:
	var intensity: float = _director.intensity()

	var load_ratio: float = clampf(
		_speed / maxf(1.0, _player.profile.max_run_speed), 0.0, 1.0
	)
	_rotor_angle += lerpf(rotor_rate_cruise, rotor_rate_max, load_ratio) * TAU * delta
	for i: int in _rotors.size():
		# Alternate direction per rotor, as a real quad would.
		var sign_flip: float = 1.0 if i % 2 == 0 else -1.0
		_rotors[i].rotation.y = _rotor_angle * sign_flip

	if _model != null:
		# Nose down into acceleration, up when braking.
		var bank: float = clampf(acceleration_now / 18.0, -1.0, 1.0) * deg_to_rad(bank_degrees)
		_model.rotation.z = lerp_angle(_model.rotation.z, -bank, minf(1.0, 6.0 * delta))

	if _eye_material != null:
		var rate: float = lerpf(pulse_rate_calm, pulse_rate_danger, intensity)
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * rate * TAU)
		_eye_material.emission_energy_multiplier = lerpf(1.4, 5.5, intensity * pulse)

	if _light != null:
		_light.light_energy = lerpf(0.9, 3.6, intensity)
		_light.omni_range = lerpf(5.0, 10.0, intensity)
