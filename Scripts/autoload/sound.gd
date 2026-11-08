extends Node
## Sound effects, played by name: Sound.play("hit"). A file Audio/sfx/<name>.ogg / .wav / .mp3 (letter case doesn't
## matter) replaces the built-in placeholder made in code (sfx_synth.gd), so real sounds can be dropped in without
## touching code. Names in use: see make() in sfx_synth.gd.
## Effects play on their own "SFX" bus; the player's volume for it (Settings) is kept in the save as "sfx_volume" (0-1).

const SYNTH := preload("res://Scripts/autoload/sfx_synth.gd")
const SFX_DIR := "res://Audio/sfx/"
const EXTENSIONS := ["ogg", "mp3", "wav"]
const BUS := &"SFX"
const DEFAULT_VOLUME := 0.7
const VOICES := 12
const MIN_GAP_MS := 50  # the same sound at most this often (one hit sound for a multi-target attack, not five)
const STEADY := ["ultimate", "wave", "jumpscare", "victory", "defeat"]  # never pitch-varied
const BATTLE := ["swing", "shoot", "hit", "crit", "miss", "heal", "knockout", "ultimate", "wave", "jumpscare", "puke",
	"victory", "defeat"]

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _files := {}  # lowercase bare name -> path
var _streams := {}  # name -> AudioStream (null if neither a file nor a placeholder exists)
var _last_ms := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Music.ensure_bus(BUS)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_players.append(p)
	if DirAccess.dir_exists_absolute(SFX_DIR):
		for file in ResourceLoader.list_directory(SFX_DIR):
			if file.get_extension().to_lower() in EXTENSIONS:
				_files[file.get_basename().to_lower()] = SFX_DIR + file
	_apply_volume()

## Plays a sound; `volume_db` and `pitch` adjust this one play. Short sounds vary their pitch a little so repeats
## don't sound mechanical.
func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(sound, -100000)) < MIN_GAP_MS:
		return
	_last_ms[sound] = now
	var stream := _stream(sound)
	if stream == null:
		return
	var p := _players[_next]  # round robin: the oldest voice gives way when all are busy
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch * (1.0 if sound in STEADY else randf_range(0.95, 1.05))
	p.play()

## Builds the placeholders ahead of time, one per frame, so the first hit doesn't hitch
func prepare(sounds: Array = BATTLE) -> void:
	for sound: String in sounds:
		if not _streams.has(sound):
			_stream(sound)
			await get_tree().process_frame

func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var stream: AudioStream = null
		var path: String = _files.get(sound.to_lower(), "")
		if not path.is_empty():
			stream = load(path) as AudioStream
		if stream == null:
			var samples := SYNTH.make(sound)
			if not samples.is_empty():
				stream = SYNTH.to_wav(samples)
		_streams[sound] = stream
	return _streams[sound]

## 0 (off) to 1 (full)
func get_volume() -> float:
	return clampf(float(GameState.data.get("sfx_volume", DEFAULT_VOLUME)), 0.0, 1.0)

func set_volume(volume: float) -> void:
	GameState.data["sfx_volume"] = clampf(volume, 0.0, 1.0)
	GameState.request_save()
	_apply_volume()

func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index(BUS)
	var volume := get_volume()
	AudioServer.set_bus_mute(bus, volume <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.001)))
