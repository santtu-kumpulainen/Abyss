extends SceneTree
## Headless check of the Issue #53 audio system.
## Stage 1: the bus layout (Master, Music, SFX), the SoundLibrary catalog (every
## stream loads, music loops, missing events are silent and documented, planned
## room-object events are registered) and the tracked/local-only file selection
## (every tracked audio file is in the catalog, no local-only file is).
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_audio.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const AUDIO_DIR := "res://assets/audio/"
const PLANNED: Array[StringName] = [&"chest_close", &"crate_open", &"sack_open"]
const ROOM_OBJECTS: Array[StringName] = [&"chest_open", &"chest_close", &"crate_open", &"sack_open",
		&"door_open", &"door_close", &"item_pickup"]

var _failures := 0


func _initialize() -> void:
	_test_buses()
	_test_music()
	_test_events()
	_test_file_selection()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_buses() -> void:
	var music := AudioServer.get_bus_index(&"Music")
	var sfx := AudioServer.get_bus_index(&"SFX")
	_check(AudioServer.bus_count == 3 and AudioServer.get_bus_name(0) == "Master", "bus layout is Master, Music, SFX")
	_check(music > 0 and AudioServer.get_bus_send(music) == &"Master", "Music bus sends to Master")
	_check(sfx > 0 and AudioServer.get_bus_send(sfx) == &"Master", "SFX bus sends to Master")
	_check(AudioServer.get_bus_volume_db(music) < 0.0 and AudioServer.get_bus_volume_db(sfx) < 0.0,
			"Music and SFX default below 0 dB")


func _test_music() -> void:
	_check(SoundLibrary.MUSIC.keys() == [SoundLibrary.MUSIC_NORMAL, SoundLibrary.MUSIC_BATTLE], "two music tracks: normal, battle")
	for track: StringName in SoundLibrary.MUSIC:
		var stream := SoundLibrary.music(track) as AudioStreamWAV
		_check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.get_length() > 50.0,
				"music '%s' loads and loops forward" % track)
	_check(String(SoundLibrary.music(SoundLibrary.MUSIC_NORMAL).resource_path).ends_with("Goblins_Den_(Regular).wav"),
			"normal track is Goblins_Den_(Regular)")
	_check(String(SoundLibrary.music(SoundLibrary.MUSIC_BATTLE).resource_path).ends_with("Goblins_Dance_(Battle).wav"),
			"battle track is Goblins_Dance_(Battle)")
	_check(SoundLibrary.music(&"nope") == null, "unknown music track is null")


func _test_events() -> void:
	var keys := ["streams", "volume_db", "pitch", "cooldown", "max_voices", "planned", "missing"]
	for id: StringName in SoundLibrary.EVENTS:
		var event: Dictionary = SoundLibrary.EVENTS[id]
		var streams: Array = event["streams"]
		var ok := event.keys().all(func(k: String) -> bool: return keys.has(k))
		ok = ok and streams.all(func(s: Variant) -> bool: return s is AudioStream and (s as AudioStream).get_length() > 0.0)
		ok = ok and int(SoundLibrary.setting(id, "max_voices")) >= 1 and float(SoundLibrary.setting(id, "cooldown")) >= 0.0
		# A missing event is silent and says why; a sounding one has no "missing" note.
		ok = ok and (event.has("missing") == streams.is_empty())
		_check(ok, "event '%s' is well-formed (%s)" % [id, "missing" if streams.is_empty() else "%d variant(s)" % streams.size()])
	for id in ROOM_OBJECTS:
		_check(SoundLibrary.has(id), "room-object event '%s' registered" % id)
	for id in PLANNED:
		_check(SoundLibrary.setting(id, "planned") == true and not SoundLibrary.is_missing(id), "planned event '%s' has sounds" % id)
	_check(SoundLibrary.missing_ids().has(&"blood_blast_warning"), "Blood Monster warning stays silent (missing)")
	_check(not SoundLibrary.has(&"nope") and SoundLibrary.streams(&"nope").is_empty() and not SoundLibrary.is_missing(&"nope"),
			"unknown event fails gracefully")
	_check(SoundLibrary.setting(&"nope", "cooldown") == SoundLibrary.DEFAULTS["cooldown"], "unknown event settings use defaults")


## Every tracked (not .gitignore'd) audio file is in the catalog and no local-only one is.
func _test_file_selection() -> void:
	var ignored := _ignored_audio()
	var used := {}
	for event: Dictionary in SoundLibrary.EVENTS.values():
		for stream: AudioStream in event["streams"]:
			used[stream.resource_path] = true
	for stream: AudioStream in SoundLibrary.MUSIC.values():
		used[stream.resource_path] = true
	var tracked := _audio_files(AUDIO_DIR).filter(func(p: String) -> bool: return not ignored.has(p))
	var unused := tracked.filter(func(p: String) -> bool: return not used.has(p))
	var local := used.keys().filter(func(p: String) -> bool: return ignored.has(p))
	_check(unused.is_empty(), "every tracked audio file is used by the catalog %s" % [unused])
	_check(local.is_empty(), "the catalog uses no local-only file %s" % [local])
	_check(tracked.size() == 52, "52 tracked audio files: 2 music + 33 Dungeon SFX + 17 Magic Spells (got %d)" % tracked.size())
	_check(not ignored.is_empty() and ignored.has(AUDIO_DIR + "magic_spells_sfx_lite/wav/blood_cast_01.wav"),
			".gitignore lists the local-only files")


## res:// paths of the audio files listed in the root .gitignore (`/path.wav*` lines).
func _ignored_audio() -> Dictionary:
	var result := {}
	var file := FileAccess.open("res://.gitignore", FileAccess.READ)
	if file == null:
		return result
	for line in file.get_as_text().split("\n"):
		line = line.strip_edges()
		if line.begins_with("/assets/audio/") and line.ends_with("*"):
			result["res:/" + line.trim_suffix("*")] = true
	return result


## Audio files under `dir`, skipping folders with a .gdignore (e.g. the OGG duplicates).
func _audio_files(dir: String) -> Array:
	var files := []
	if FileAccess.file_exists(dir.path_join(".gdignore")):
		return files
	for name in DirAccess.get_files_at(dir):
		if name.get_extension() in ["wav", "mp3", "ogg"]:
			files.append(dir.path_join(name))
	for sub in DirAccess.get_directories_at(dir):
		files.append_array(_audio_files(dir.path_join(sub)))
	return files


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		_failures += 1
