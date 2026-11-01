extends Node
## Background music. Tracks live in Audio/music/ (.ogg, .mp3 or .wav; letter case doesn't matter):
##   Home.* / Homepage.*    - the Home screen (and the starter pick)
##   <ChapterName>.*        - battles in that chapter, named like its background: "Poppy Street" -> PoppyStreet.ogg
##   battle.*               - battles in chapters without their own track
## Asking for the track that's already playing does nothing, so replaying a map keeps the song going instead of
## restarting it. Coming back to a track picks it up where it left off (e.g. Home after a battle). A missing
## track keeps whatever is playing. Every track loops; switching crossfades.
## The player's music volume (Settings) is kept in the save as "music_volume" (0-1).

const LEVELS := preload("res://Scripts/autoload/music_levels.gd")  # per-track volume correction (level_music.ps1)
const MUSIC_DIR := "res://Audio/music/"
const EXTENSIONS := ["ogg", "mp3", "wav"]
const DEFAULT_VOLUME := 0.5
const SILENT_DB := -40.0
const FADE_SEC := 1.0

var _players: Array[AudioStreamPlayer] = []
var _active := 0  # index in _players of the one playing (or fading in)
var _current := ""  # path of the current track
var _index := {}  # lowercase file name / bare name -> path
var _positions := {}  # path -> seconds into the track when it was switched away from
var _fade: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)
	for file in ResourceLoader.list_directory(MUSIC_DIR):
		if file.get_extension().to_lower() in EXTENSIONS:
			_index[file.to_lower()] = MUSIC_DIR + file
			_index[file.get_basename().to_lower()] = MUSIC_DIR + file
	_apply_volume()

func has_track(track: String) -> bool:
	return _index.has(track.to_lower())

## Plays the first of `tracks` that exists (e.g. ["PoppyStreet", "battle"]); keeps the current song if it's
## already that track or if none of them exist
func play(tracks: Array) -> void:
	for track: String in tracks:
		var path: String = _index.get(track.to_lower(), "")
		if path.is_empty():
			continue
		if path != _current:
			_switch_to(path)
		return

func play_home() -> void:
	play(["home", "homepage", "homebgm"])

func play_chapter(chapter: int) -> void:
	play([Terms.chapter_name(chapter).replace(" ", ""), "battle"])

## 0 (off) to 1 (full)
func get_volume() -> float:
	return clampf(float(GameState.data.get("music_volume", DEFAULT_VOLUME)), 0.0, 1.0)

func set_volume(volume: float) -> void:
	GameState.data["music_volume"] = clampf(volume, 0.0, 1.0)
	GameState.request_save()
	_apply_volume()

func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	var volume := get_volume()
	AudioServer.set_bus_mute(bus, volume <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.001)))

func _switch_to(path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	if "loop" in stream:  # Ogg / MP3
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	var old := _players[_active]
	if old.playing and not _current.is_empty():
		_positions[_current] = old.get_playback_position()
	_current = path
	_active = 1 - _active
	var new := _players[_active]
	new.stream = stream
	new.volume_db = SILENT_DB
	var resume_at: float = _positions.get(path, 0.0)
	new.play(resume_at if resume_at < stream.get_length() else 0.0)
	if _fade:
		_fade.kill()
	_fade = create_tween().set_parallel()
	_fade.tween_property(new, "volume_db", float(LEVELS.GAIN_DB.get(path.get_file().get_basename().to_lower(), 0.0)), FADE_SEC)
	if old.playing:
		_fade.tween_property(old, "volume_db", SILENT_DB, FADE_SEC)
		_fade.chain().tween_callback(old.stop)
