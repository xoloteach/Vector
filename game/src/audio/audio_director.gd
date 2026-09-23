class_name AudioDirector
extends Node

## Owns every sound in the game.
##
## One place, listening to signals, so no gameplay system ever has to know that audio
## exists. `Player` emits `vaulted`; it does not play a vault sound.
##
## ### Mix philosophy
##
## Sound here reinforces movement timing rather than filling space:
##
##  - **Footsteps are driven by distance travelled, not by a timer.** A step fires
##    every `STRIDE_DISTANCE` metres of ground covered, so the footfall rate tracks
##    speed exactly and automatically — no syncing to the animator, and it stays
##    correct if the movement profile is retuned. They are kept quiet: at any real
##    volume, footsteps become the loudest thing in a game where the player is
##    listening for impacts.
##  - **Impacts carry the information.** Soft and hard landings differ in weight and
##    length, not just level, so a mistake is audible before the camera shake or the
##    HUD reports it.
##  - **The drone is the only sound allowed to demand attention**, and its level is
##    driven directly by chase intensity, so it earns that by being the thing that
##    can kill you.
##
## ### Web constraints
##
## Browsers refuse to start an audio context before a user gesture. Godot resumes it
## on first input automatically, so nothing special is needed — but it does mean the
## first half-second of ambience may be silent on a fresh page load, which is why
## ambience fades in rather than starting at full level.

const AUDIO_PATH: String = "res://assets/audio/%s.wav"

## Metres of ground travel between footfalls at any speed. Derived from the animator's
## stride rate so audio and animation agree by construction rather than by tuning.
const STRIDE_DISTANCE: float = 2.45

## Simultaneous one-shot voices. Generous enough for a landing, a vault and a
## footstep to overlap; small enough to stay cheap on web.
const VOICE_COUNT: int = 12

## Per-sound level trims, in decibels, applied on top of the bus volumes.
## This is where the mix actually lives — the generated files are all normalised to
## similar peaks on purpose, so balance is decided here in one readable table.
const TRIM_DB: Dictionary[String, float] = {
	"footstep_01": -17.0,
	"footstep_02": -17.5,
	"footstep_03": -16.5,
	"footstep_04": -17.0,
	"jump": -11.0,
	"land_soft": -9.0,
	"land_hard": -4.0,
	"slide": -9.5,
	"vault_low": -10.0,
	"vault_high": -8.5,
	"roll": -7.0,
	"wall_scuff": -10.5,
	"ledge_grab": -9.0,
	"death": -4.0,
	"finish": -5.0,
	"drone_alert": -8.0,
	"ui_click": -12.0,
	"ui_confirm": -9.0,
}

var _streams: Dictionary[String, AudioStream] = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0

var _music: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _city: AudioStreamPlayer
var _drone: AudioStreamPlayer

var _player: Player
var _director: ChaseDirector

## Distance accumulator for footsteps.
var _stride_accumulator: float = 0.0
var _footstep_index: int = 0
var _last_x: float = 0.0

## Ambience fade-in, since a browser may not have an audio context for the first
## moments of a page load.
var _fade_in: float = 0.0


func _ready() -> void:
	# Keep running while paused so the pause menu's own sounds work and ambience can
	# duck rather than cutting out.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_load_streams()
	_create_voices()
	_create_beds()

	Game.volumes_changed.connect(_apply_volumes)
	Game.run_failed.connect(_on_run_failed)
	Game.run_completed.connect(_on_run_completed)
	_apply_volumes()


## Disconnects from a level being torn down, so the director survives a restart with
## its music and ambience still playing. Retrying is the main verb in this game; the
## soundtrack restarting on every attempt was intolerable.
func teardown() -> void:
	_player = null
	_director = null
	_stride_accumulator = 0.0
	if _drone != null:
		_drone.volume_db = -60.0


func setup(player: Player, director: ChaseDirector) -> void:
	_player = player
	_last_x = player.global_position.x

	player.jumped.connect(func(_r: float) -> void: play("jump"))
	player.landed.connect(_on_landed)
	player.slid.connect(func() -> void: play("slide"))
	player.vaulted.connect(func(high: bool) -> void: play("vault_high" if high else "vault_low"))
	player.climbed.connect(func(_h: float) -> void: play("wall_scuff"))
	player.wall_ran.connect(func() -> void: play("wall_scuff"))
	player.grabbed_ledge.connect(func() -> void: play("ledge_grab"))
	player.rolled.connect(func(_i: float) -> void: play("roll"))

	_director = director
	if director != null:
		director.danger_changed.connect(_on_danger_changed)
		if _drone != null:
			_drone.play()


## Creates Music and SFX buses routed to Master.
##
## Done in code rather than shipping a bus layout resource: three buses is not worth a
## binary file that cannot be diffed, and this way the routing is visible.
func _setup_buses() -> void:
	if AudioServer.get_bus_index("Music") >= 0:
		return
	AudioServer.add_bus(1)
	AudioServer.set_bus_name(1, "Music")
	AudioServer.set_bus_send(1, "Master")
	AudioServer.add_bus(2)
	AudioServer.set_bus_name(2, "SFX")
	AudioServer.set_bus_send(2, "Master")


func _load_streams() -> void:
	for name: String in [
		"footstep_01", "footstep_02", "footstep_03", "footstep_04",
		"jump", "land_soft", "land_hard", "slide",
		"vault_low", "vault_high", "roll", "wall_scuff", "ledge_grab",
		"death", "finish", "drone_hum", "drone_alert",
		"amb_wind", "amb_city", "music_pursuit",
		"ui_click", "ui_confirm",
	]:
		var path: String = AUDIO_PATH % name
		if not ResourceLoader.exists(path):
			push_warning("Missing audio '%s'. Run python3 audio/scripts/build_audio.py." % name)
			continue
		_streams[name] = load(path) as AudioStream


## Marks a stream as looping.
##
## Has to be done in code because the generated WAVs carry no loop metadata, and the
## alternative — hand-written `.import` files — would have to be regenerated every
## time the audio is rebuilt.
func _make_looping(name: String) -> AudioStream:
	var stream: AudioStream = _streams.get(name)
	var wav := stream as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / (4 if wav.stereo else 2)
	var ogg := stream as AudioStreamOggVorbis
	if ogg != null:
		ogg.loop = true
	return stream


func _create_voices() -> void:
	for i: int in VOICE_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.bus = "SFX"
		add_child(voice)
		_voices.append(voice)


func _create_beds() -> void:
	_music = _bed("music_pursuit", "Music", -10.0)
	_wind = _bed("amb_wind", "SFX", -19.0)
	_city = _bed("amb_city", "SFX", -22.0)
	# The drone's hum starts silent and is driven entirely by chase intensity.
	_drone = _bed("drone_hum", "SFX", -60.0, false)


func _bed(name: String, bus: String, volume_db: float, autoplay: bool = true) -> AudioStreamPlayer:
	if not _streams.has(name):
		return null
	var player := AudioStreamPlayer.new()
	player.name = name
	player.stream = _make_looping(name)
	player.bus = bus
	player.volume_db = volume_db
	add_child(player)
	if autoplay:
		player.play()
	return player


# ------------------------------------------------------------------- playback

## Fires a one-shot through the voice pool.
func play(name: String, extra_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(name):
		return
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = _streams[name]
	voice.volume_db = float(TRIM_DB.get(name, -8.0)) + extra_db
	voice.pitch_scale = pitch
	voice.play()


func _on_landed(impact_speed: float, hard: bool) -> void:
	if hard:
		play("land_hard")
		return
	# Quiet, low-impact landings should barely register, so the loud ones mean
	# something. A small hop is nearly silent.
	var strength: float = clampf(impact_speed / 26.0, 0.0, 1.0)
	if strength < 0.1:
		return
	play("land_soft", lerpf(-12.0, 0.0, strength), randf_range(0.96, 1.05))


func _on_danger_changed(in_danger: bool) -> void:
	if in_danger:
		play("drone_alert")


func _on_run_failed(reason: String) -> void:
	play("death")
	if reason == Game.FAIL_CAUGHT:
		play("drone_alert", 2.0)


func _on_run_completed(_elapsed: float) -> void:
	play("finish")


# -------------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	_fade_in = minf(1.0, _fade_in + delta * 0.5)
	if _player == null:
		return

	_update_footsteps()
	_update_drone(delta)
	_update_music()


## Footsteps from distance travelled, so the rate tracks speed with no syncing.
func _update_footsteps() -> void:
	var x: float = _player.global_position.x
	var travelled: float = absf(x - _last_x)
	_last_x = x

	var state: StringName = _player.state_name()
	var stepping: bool = (
		_player.is_on_floor()
		and (state == PlayerState.RUN or state == PlayerState.LAND)
		and _player.horizontal_speed() > 1.0
	)
	if not stepping:
		# Reset most of the accumulator so the first step after landing lands
		# promptly rather than on a stale remainder.
		_stride_accumulator = minf(_stride_accumulator, STRIDE_DISTANCE * 0.5)
		return

	_stride_accumulator += travelled
	if _stride_accumulator < STRIDE_DISTANCE:
		return
	_stride_accumulator -= STRIDE_DISTANCE

	_footstep_index = (_footstep_index + 1) % 4
	# Faster running lands harder and brighter.
	var ratio: float = _player.speed_ratio()
	play(
		"footstep_0%d" % (_footstep_index + 1),
		lerpf(-7.0, 1.0, ratio),
		randf_range(0.94, 1.07)
	)


## Drone level and pitch from chase intensity — the primary audible warning.
func _update_drone(delta: float) -> void:
	if _drone == null or _director == null:
		return
	var intensity: float = _director.intensity() if _director.is_active() else 0.0
	var target_db: float = -60.0 if intensity < 0.02 else lerpf(-32.0, -7.0, intensity)
	_drone.volume_db = lerpf(_drone.volume_db, target_db, minf(1.0, 3.0 * delta))
	# Rises slightly as it closes, which reads as the rotors working harder.
	_drone.pitch_scale = lerpf(_drone.pitch_scale, lerpf(0.92, 1.12, intensity), minf(1.0, 2.0 * delta))


## Music swells with chase pressure, and ambience fades in on load.
func _update_music() -> void:
	var intensity: float = _director.intensity() if _director != null and _director.is_active() else 0.0
	if _music != null:
		_music.volume_db = lerpf(-16.0, -7.0, intensity) - (1.0 - _fade_in) * 20.0
	if _wind != null:
		_wind.volume_db = -19.0 - (1.0 - _fade_in) * 20.0
	if _city != null:
		_city.volume_db = -22.0 - (1.0 - _fade_in) * 20.0


# --------------------------------------------------------------------- settings

func _apply_volumes() -> void:
	_set_bus_volume("Master", Game.master_volume)
	_set_bus_volume("Music", Game.music_volume)
	_set_bus_volume("SFX", Game.sfx_volume)


## Linear 0..1 to decibels, muting cleanly at zero.
func _set_bus_volume(bus: String, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0001, 1.0)))
