extends SceneTree
## Headless check of the Issue #53 audio system.
## Stage 1: the bus layout (Master, Music, SFX), the SoundLibrary catalog (every
## stream loads, music loops, missing events are silent and documented, planned
## room-object events are registered) and the tracked/local-only file selection
## (every tracked audio file is in the catalog, no local-only file is).
## Stage 2: the AudioManager autoload (one instance, survives scene changes,
## always processes), music crossfades without restarts or overlaps, the
## bus volume and SFX APIs (cooldown, voice limit, variants, missing and unknown
## ids), and the music flow of a run: Main Menu -> Dungeon (same track continues),
## ordinary room changes, miniboss and boss encounters (battle music until the
## room clears, then normal music at once), Victory (music keeps playing while
## paused), Game Over (fade-out) and Restart (one fresh normal track).
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_audio.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const AUDIO_DIR := "res://assets/audio/"
const PLANNED: Array[StringName] = [&"chest_close", &"crate_open", &"sack_open"]
const ROOM_OBJECTS: Array[StringName] = [&"chest_open", &"chest_close", &"crate_open", &"sack_open",
		&"door_open", &"door_close", &"item_pickup"]

const SEED := 5353
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const DUNGEON_SCENE := "res://scenes/dungeon/dungeon.tscn"
const NORMAL := SoundLibrary.MUSIC_NORMAL
const BATTLE := SoundLibrary.MUSIC_BATTLE

var _failures := 0
var _audio: AudioManager
var _dungeon: Dungeon


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	RunState.seed_override = SEED
	_test_buses()
	_test_music()
	_test_events()
	_test_file_selection()
	_test_manager()
	_test_bus_api()
	await _test_sfx_api()
	await _test_music_api()
	await _test_run_music()
	_check(_audio_nodes() == 1 and AudioManager.instance(self) == _audio, "still one AudioManager after every scene change")
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	RunState.seed_override = 0
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


# --- Stage 2: AudioManager --------------------------------------------------------

func _test_manager() -> void:
	_audio = AudioManager.instance(self)
	_check(_audio != null and _audio == root.get_node_or_null(^"Audio") and AudioManager.instance(self) == _audio,
			"AudioManager.instance() is the 'Audio' autoload, every time")
	_check(_audio_nodes() == 1, "exactly one AudioManager in the tree")
	_check(_audio.process_mode == Node.PROCESS_MODE_ALWAYS, "AudioManager processes while paused")
	var buses := _audio.get_children().map(func(p: AudioStreamPlayer) -> StringName: return p.bus)
	_check(buses.count(&"Music") == 2 and buses.count(&"SFX") == AudioManager.SFX_POOL_SIZE,
			"two music players on Music, %d SFX players on SFX" % AudioManager.SFX_POOL_SIZE)


func _test_bus_api() -> void:
	var before := _audio.bus_volume(&"Music")
	_check(_audio.set_bus_volume(&"Music", -20.0) and is_equal_approx(_audio.bus_volume(&"Music"), -20.0)
			and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), -20.0),
			"set_bus_volume() changes the bus")
	_audio.set_bus_volume(&"Music", before)
	_check(not _audio.set_bus_volume(&"Nope", 0.0) and is_nan(_audio.bus_volume(&"Nope")), "unknown bus is rejected")
	_check(_audio.set_bus_volume(&"Master", 0.0) and _audio.set_bus_volume(&"SFX", _audio.bus_volume(&"SFX")),
			"Master and SFX buses are adjustable")


func _test_sfx_api() -> void:
	_check(not _audio.play_sfx(&"nope"), "unknown sound event plays nothing")
	_check(not _audio.play_sfx(&"blood_blast_warning"), "missing sound event plays nothing (silent)")
	_check(_audio.play_sfx(&"mage_hurt") and not _audio.play_sfx(&"mage_hurt") and _audio.sfx_voices(&"mage_hurt") == 1,
			"cooldown drops an immediate repeat")
	# chest_open: 4 variants, 2 voices, 0.05 s cooldown, ~0.67 s long.
	var played := [_audio.play_sfx(&"chest_open")]
	await _seconds(0.08)
	played.append(_audio.play_sfx(&"chest_open"))
	await _seconds(0.08)
	played.append(_audio.play_sfx(&"chest_open"))
	_check(played == [true, true, false] and _audio.sfx_voices(&"chest_open") == 2, "voice limit caps simultaneous plays")
	var repeats := 0
	var last := ""
	for i in 12:
		_audio.stop_all_sfx()
		_audio.play_sfx(&"chest_open")
		var path := _sfx_path(&"chest_open")
		repeats += 1 if path == last else 0
		last = path
	_check(repeats == 0, "variants never repeat back to back")
	_audio.stop_all_sfx()
	_check(_audio.sfx_voices(&"chest_open") == 0 and _audio.sfx_voices(&"mage_hurt") == 0, "stop_all_sfx() silences the pool")
	_check(_audio.get_children().all(func(p: AudioStreamPlayer) -> bool: return p.bus != &"Music" or not p.playing),
			"sound effects never use the music players")


func _test_music_api() -> void:
	_check(not _audio.play_music(&"nope") and _audio.current_music() == &"", "unknown music track is rejected, nothing plays")
	_check(_audio.play_music(NORMAL, 0.0) and _audio.current_music() == NORMAL and _audio.playing_music_players() == 1,
			"play_music() starts the normal track")
	var player := _audio.active_music_player()
	await _seconds(0.3)
	var pos := player.get_playback_position()
	_check(_audio.play_music(NORMAL) and _audio.active_music_player() == player
			and player.get_playback_position() >= pos and _audio.playing_music_players() == 1,
			"requesting the playing track does not restart it")
	_audio.play_music(BATTLE, 0.4)
	await _seconds(0.1)
	_check(_audio.current_music() == BATTLE and _audio.playing_music_players() == 2, "crossfade: both tracks during the fade")
	await _seconds(0.5)
	_check(_audio.playing_music_players() == 1 and is_equal_approx(_audio.active_music_player().volume_linear, 1.0)
			and _audio.active_music_player().stream == SoundLibrary.music(BATTLE), "crossfade ends with only the battle track")
	_audio.play_music(NORMAL, 0.2)
	await _seconds(0.4)
	_check(_audio.current_music() == NORMAL and _audio.playing_music_players() == 1
			and _audio.active_music_player().get_playback_position() >= pos, "normal track resumes where it left off")
	# A quick back-and-forth never leaves more than two players.
	_audio.play_music(BATTLE, 0.3)
	_audio.play_music(NORMAL, 0.3)
	_audio.play_music(BATTLE, 0.3)
	_check(_audio.playing_music_players() <= 2, "rapid switches use at most two players")
	await _seconds(0.5)
	_check(_audio.playing_music_players() == 1 and _audio.current_music() == BATTLE, "rapid switches settle on the last track")
	_audio.stop_music(0.3)
	await _seconds(0.1)
	_check(_audio.current_music() == &"" and _audio.playing_music_players() == 1, "stop_music() fades out")
	await _seconds(0.4)
	_check(_audio.playing_music_players() == 0, "stop_music() ends silent")
	_audio.stop_music()
	_check(_audio.playing_music_players() == 0, "stop_music() without music is harmless")
	# Paused tree (victory screen): music and fades keep running.
	_audio.play_music(NORMAL, 0.2)
	paused = true
	await _seconds(0.4)
	_check(_audio.active_music_player().playing and is_equal_approx(_audio.active_music_player().volume_linear, 1.0)
			and _audio.active_music_player().get_playback_position() > 0.2, "music and fades continue while paused")
	paused = false
	_audio.stop_music(0.0)


# --- Stage 2: music through a run ------------------------------------------------

func _test_run_music() -> void:
	await _change_scene(MENU_SCENE)
	_check(_audio.current_music() == NORMAL and _audio.playing_music_players() == 1, "Main Menu plays the normal track")
	await _seconds(1.4)
	var player := _audio.active_music_player()
	var pos := player.get_playback_position()
	await _change_scene(DUNGEON_SCENE)
	_dungeon = current_scene as Dungeon
	_dungeon.mage.health.increase_max_health(1000000.0, 1000000.0)
	_check(_audio.current_music() == NORMAL and _audio.active_music_player() == player
			and player.get_playback_position() >= pos and _audio.playing_music_players() == 1,
			"starting a run keeps the menu's normal track playing (no restart)")
	_check(_dungeon.music != null and _dungeon.music.wanted_track() == NORMAL, "start room wants normal music")

	# Ordinary room changes.
	var ordinary := _ordinary_neighbour(_dungeon.start_room)
	_check(ordinary >= 0, "found an ordinary neighbour room")
	pos = player.get_playback_position()
	_dungeon.enter_room(ordinary, _dungeon.door_to(ordinary, _dungeon.start_room))
	await _frames(3)
	_dungeon.enter_room(_dungeon.start_room, _dungeon.door_to(_dungeon.start_room, ordinary))
	await _frames(3)
	_check(_audio.current_music() == NORMAL and _audio.active_music_player() == player
			and player.get_playback_position() >= pos and _audio.playing_music_players() == 1,
			"ordinary room changes keep the normal track (no restart)")

	# Miniboss encounter.
	var minis := _dungeon.miniboss_room_indexes()
	_check(not minis.is_empty(), "level has a miniboss room")
	var mini: int = minis[0]
	_dungeon.enter_room(mini, _dungeon.entry_door(mini))
	await _frames(2)
	_check(_dungeon.current_room.state == Room.State.COMBAT and _audio.current_music() == BATTLE,
			"entering a miniboss encounter switches to battle music")
	await _seconds(_audio.crossfade_time + 0.2)
	var battle := _audio.active_music_player()
	pos = battle.get_playback_position()
	_check(_audio.playing_music_players() == 1 and battle.stream == SoundLibrary.music(BATTLE),
			"after the crossfade only the battle track plays")
	await _seconds(0.3)
	_dungeon.music._update()
	_check(_audio.active_music_player() == battle and battle.get_playback_position() > pos,
			"battle music does not restart during the encounter")
	await _clear_room(_dungeon.current_room)
	_check(_dungeon.current_room.state == Room.State.CLEARED and _audio.current_music() == NORMAL,
			"clearing the miniboss room switches back to normal music at once (Mage still inside)")
	var normal := _audio.active_music_player()
	await _seconds(_audio.crossfade_time + 0.2)
	_check(_audio.playing_music_players() == 1 and _audio.active_music_player() == normal and normal.playing,
			"normal music resumes once, without restarting")
	_dungeon.enter_room(_dungeon.start_room)
	await _frames(2)
	_dungeon.enter_room(mini, _dungeon.entry_door(mini))
	await _frames(2)
	_check(_audio.current_music() == NORMAL and _audio.active_music_player() == normal,
			"revisiting the cleared miniboss room keeps normal music")

	# Boss encounter and Victory.
	var boss := _dungeon.boss_index()
	_dungeon.enter_room(boss, _dungeon.entry_door(boss))
	await _frames(2)
	_check(_dungeon.current_room.state == Room.State.COMBAT and _audio.current_music() == BATTLE,
			"entering the boss encounter switches to battle music")
	await _seconds(_audio.crossfade_time + 0.2)
	await _clear_room(_dungeon.current_room)
	_check(_audio.current_music() == NORMAL and _dungeon.victory, "boss defeated: normal music at once, victory started")
	await _wait_until(func() -> bool: return paused, 600)
	normal = _audio.active_music_player()
	pos = normal.get_playback_position()
	await _seconds(0.5)
	_check(paused and normal.playing and normal.get_playback_position() > pos and _audio.current_music() == NORMAL,
			"victory screen pauses the game, the music keeps playing")
	paused = false

	# Game Over and Restart.
	await _change_scene(DUNGEON_SCENE)
	_dungeon = current_scene as Dungeon
	_check(_audio.current_music() == NORMAL and _audio.playing_music_players() == 1, "new run: one normal track")
	_dungeon.mage.health.take_damage(999999.0)
	await _frames(2)
	_check(_dungeon.mage.is_dead() and _audio.current_music() == &"" and _audio.playing_music_players() == 1,
			"Game Over starts the music fade-out")
	_dungeon.enter_room(_dungeon.start_room)
	await _frames(2)
	_check(_audio.current_music() == &"", "no music returns after Game Over")
	await _seconds(_audio.fade_out_time + 0.3)
	_check(_audio.playing_music_players() == 0, "Game Over fade-out ends silent")
	var overlay := current_scene.get_node(^"GameOverOverlay") as GameOverOverlay
	overlay.restart()
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene != _dungeon and current_scene.is_node_ready(), 600)
	await _frames(2)
	_dungeon = current_scene as Dungeon
	await _seconds(0.2)
	_check(_audio.current_music() == NORMAL and _audio.playing_music_players() == 1
			and _audio.active_music_player().get_playback_position() < 1.0, "Restart starts one fresh normal track")
	# Game Over -> Main Menu: the menu starts the normal track again, once.
	_dungeon.mage.health.take_damage(999999.0)
	await _frames(1)
	(current_scene.get_node(^"GameOverOverlay") as GameOverOverlay).main_menu()
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.scene_file_path == MENU_SCENE and current_scene.is_node_ready(), 600)
	await _seconds(_audio.fade_out_time + 0.3)
	_check(_audio.current_music() == NORMAL and _audio.playing_music_players() == 1, "Main Menu after Game Over: one normal track")
	_audio.stop_music(0.0)


## A neighbour of `index` that is neither the boss room nor a miniboss room.
func _ordinary_neighbour(index: int) -> int:
	for j: int in _dungeon.get_neighbours(index):
		if not _dungeon.music.is_encounter_room(j):
			return j
	return -1


## Kills the room's encounter enemies until it is cleared.
func _clear_room(room: Room) -> void:
	for i in 60:
		if room.state == Room.State.CLEARED:
			return
		for enemy in room.get_node(^"Enemies").get_children():
			if enemy is Enemy and (enemy as Enemy).health.current > 0.0:
				(enemy as Enemy).take_damage(999999.0)
		await _frames(5)


func _audio_nodes() -> int:
	return root.get_children().filter(func(n: Node) -> bool: return n is AudioManager).size()


func _sfx_path(id: StringName) -> String:
	for player: AudioStreamPlayer in _audio.get_children():
		if player.playing and player.get_meta(&"sound_id", &"") == id:
			return player.stream.resource_path
	return ""


func _change_scene(path: String) -> void:
	var old_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(path)
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)


func _wait_until(condition: Callable, max_frames: int = 240) -> void:
	for i in max_frames:
		if condition.call():
			return
		await process_frame


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _seconds(time: float) -> void:
	var end := Time.get_ticks_msec() + int(time * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


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
