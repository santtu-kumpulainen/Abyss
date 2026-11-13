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
## Stage 3: every gameplay hook requests its catalog event once per event (Mage
## hurt / death / dash, spell launch / impact / bounce / burst, Goblin, Demon,
## Blood Monster, minibosses, Abyss Warden, level up, potions, seals, Home
## Teleport, room doors), volleys collapse into one sound, missing events stay
## silent and idle frames request nothing.
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
	await _test_gameplay_sfx()
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


# --- Stage 3: gameplay sound effects ---------------------------------------------

## Drives each gameplay hook and counts play_sfx() requests (every trigger) and
## plays (after cooldown / voice limits). Enemies are spawned far away with their
## AI disabled, so only the triggered event can request a sound.
func _test_gameplay_sfx() -> void:
	await _change_scene(DUNGEON_SCENE)
	_dungeon = current_scene as Dungeon
	var mage := _dungeon.mage
	var run := _dungeon.run_state
	mage.health.increase_max_health(1000000.0, 1000000.0)
	await _frames(5)
	_fresh()
	await _frames(30)
	_check(_audio.sfx_requests.is_empty(), "idle frames request no sound effects %s" % [_audio.sfx_requests])

	# Mage.
	mage.take_damage(1.0)
	await _frames(20)
	_check(_req(&"mage_hurt") == 1 and _plays(&"mage_hurt") == 1, "Mage hurt: once per hit, not per frame")
	_fresh()
	_check(mage.try_dash(Vector2.RIGHT), "Mage dash starts")
	await _frames(30)
	_check(_req(&"mage_dash") == 1 and _plays(&"mage_dash") == 1, "Mage dash: once per dash")

	# Projectiles: launch, impact (once), bounce splash, burst; lifetime end of a non-bouncing spell is silent.
	_fresh()
	var fire := _projectile("res://scenes/spells/fire_ball/fire_ball.tres", mage)
	_check(_plays(&"mage_cast") == 1, "Fire Ball launch plays mage_cast")
	var wall := StaticBody2D.new()
	current_scene.add_child(wall)
	fire._on_body_entered(wall)
	fire._on_body_entered(wall)
	_check(_req(&"mage_spell_impact") == 1 and _plays(&"mage_spell_impact") == 1, "Fire Ball impact: once per projectile")
	_fresh()
	var fizzle := _projectile("res://scenes/spells/fire_ball/fire_ball.tres", mage)
	fizzle._expire()
	_check(_req(&"mage_spell_impact") == 0, "Fire Ball lifetime end is silent (no impact shown)")
	_fresh()
	var cast := mage.caster.try_cast(mage.global_position + Vector2(200, 0))
	_check(cast != null and _plays(&"mage_cast") == 1, "Mage cast through SpellCaster plays one cast sound (Twin Cast pairs collapse)")
	_fresh()
	for i in 5:
		_projectile("res://scenes/spells/enemy_bolt/enemy_bolt.tres", null)
	_check(_req(&"enemy_bolt_cast") == 5 and _plays(&"enemy_bolt_cast") == 1, "a 5-bolt volley plays one violet cast sound")
	_fresh()
	var bolt := _projectile("res://scenes/spells/enemy_bolt/enemy_bolt.tres", null)
	bolt._on_body_entered(wall)
	_check(_plays(&"enemy_bolt_impact") == 1, "violet bolt impact")
	_fresh()
	var water := _projectile("res://scenes/spells/water_bolt/water_bolt.tres", null)
	water._on_body_entered(wall)
	_check(_plays(&"water_bolt_cast") == 1 and _plays(&"water_bolt_impact") == 1, "Water bolt launch and impact")
	_fresh()
	var big := _projectile("res://scenes/spells/water_bolt/big_water_bolt.tres", null)
	if big.bounces_left() > 0:
		big._bounce(Vector2.LEFT, big.global_position)
	_check(big.spell.max_bounces > 0 and _plays(&"water_bolt_impact") == 1, "big water bolt bounce splash")
	_fresh()
	big._expire()
	big._expire()
	_check(_req(&"water_bolt_impact") == 1, "big water bolt burst at its end: once")
	wall.queue_free()

	# Goblin.
	_fresh()
	var goblin := _spawn("res://scenes/enemies/giant_goblin.tscn") as Goblin
	goblin.take_damage(1.0)
	_check(_plays(&"goblin_hurt") == 1, "Goblin hurt")
	goblin._resolve_swing()
	_check(_plays(&"goblin_swing") == 1, "Goblin sword swing")
	goblin.phase = TelegraphedMelee.Phase.WINDUP
	goblin._phase_left = 0.0
	goblin.process_mode = Node.PROCESS_MODE_INHERIT
	await physics_frame
	await physics_frame
	goblin.process_mode = Node.PROCESS_MODE_DISABLED
	_check(goblin.phase != TelegraphedMelee.Phase.WINDUP and _plays(&"goblin_special") == 1,
			"Goblin special strike (phase %s, plays %d)" % [TelegraphedMelee.Phase.keys()[goblin.phase], _plays(&"goblin_special")])
	goblin.take_damage(1e9)
	goblin.take_damage(1e9)
	_check(_req(&"goblin_death") == 1 and _plays(&"goblin_death") == 1, "Goblin death: exactly once")

	# Demon: hurt and death are registered but missing (silent).
	_fresh()
	var demon := _spawn("res://scenes/enemies/enemy.tscn") as Enemy
	demon.take_damage(1.0)
	demon.take_damage(1e9)
	_check(_req(&"enemy_hurt") == 1 and _req(&"enemy_death") == 1 and _plays(&"enemy_hurt") == 0
			and _plays(&"enemy_death") == 0, "Demon hurt / death requested once each, silent (missing sounds)")

	# Blood Monster charge windup and death blast.
	_fresh()
	var monster := _spawn("res://scenes/enemies/blood_monster.tscn") as BloodMonster
	monster.target = mage
	_check(monster.begin_special() and _plays(&"blood_monster_charge") == 1, "Blood Monster charge windup")
	_fresh()
	BloodBlast.spawn_blast(current_scene, Vector2(5000, 5000), 30.0, 0.05, 0.0, 0.0)
	await _seconds(0.5)
	_check(_req(&"blood_blast") == 1 and _plays(&"blood_blast") == 1, "Blood Monster death blast: once")
	_check(_req(&"blood_blast_warning") == 0, "Blood Monster warning stays silent")

	# Minibosses.
	_fresh()
	var mother := _spawn("res://scenes/enemies/brood_mother.tscn") as BroodMother
	mother._begin(&"summon", 0.05, true)
	_check(_plays(&"brood_summon") == 1, "Brood Mother summon")
	mother._begin(&"charge", 0.05)
	_check(_req(&"brood_charge") == 1 and _plays(&"brood_charge") == 0, "Brood Mother charge: silent (missing)")
	_fresh()
	var hex := _spawn("res://scenes/enemies/hexcaller.tscn") as Hexcaller
	hex._begin(&"hex", 0.05)
	_check(_plays(&"hexcaller_hex") == 1 and _req(&"hexcaller_blink") == 0, "Hexcaller hex cast")
	hex._begin(&"blink", 0.0)
	_check(_req(&"hexcaller_blink") == 0, "Hexcaller blink is silent during its windup")
	hex.process_mode = Node.PROCESS_MODE_INHERIT
	await physics_frame
	await physics_frame
	hex.process_mode = Node.PROCESS_MODE_DISABLED
	_check(_plays(&"hexcaller_blink") == 1, "Hexcaller blink at the teleport")
	_fresh()
	var caster := _spawn("res://scenes/enemies/water_caster_boss.tscn") as WaterCasterBoss
	caster._begin(&"zones", 0.05)
	_check(_plays(&"water_boss_zones") == 1, "Water Caster Boss zones cast")

	# Abyss Warden.
	_fresh()
	var warden := _spawn("res://scenes/enemies/abyss_warden.tscn") as Boss
	warden.take_damage(warden.health.max_health * 0.4)
	_check(warden.phase >= 2 and _req(&"boss_phase") == warden.phase - 1 and _plays(&"boss_phase") == 1, "Abyss Warden phase change")
	warden.current_attack = &"slam"
	warden._resolve_attack()
	_check(_plays(&"boss_slam") == 1, "Abyss Warden slam impact")
	_check(_req(&"enemy_death") == 0, "no death sound while the boss lives")

	# Run events.
	_fresh()
	var level := run.level
	run.grant_enemy_rewards(100000, 0)
	_check(run.level > level and _plays(&"mage_level_up") == 1, "level up (several at once play once)")
	_fresh()
	run.currency = 100000
	run.buy_consumable(&"speed_potion")
	_check(_dungeon.use_speed_potion() and _plays(&"potion_speed") == 1, "Speed Potion")
	run.buy_consumable(&"health_potion")
	mage.health.take_damage(mage.health.max_health * 0.5)
	_check(_dungeon.use_health_potion() and _plays(&"potion_health") == 1, "Health Potion")
	_fresh()
	var seal_rooms := _dungeon.seal_rooms()
	_check(not seal_rooms.is_empty() and run.collect_seal(_dungeon.seal_id(seal_rooms.keys()[0]))
			and _plays(&"seal_collected") == 1, "Ancient Seal collected")
	_fresh()
	_dungeon.home_teleport._on_teleport_finished(true)
	_check(_plays(&"home_teleport_complete") == 1, "Home Teleport completed")
	_dungeon.home_teleport._on_teleport_finished(false)
	_check(_req(&"home_teleport_complete") == 1, "a failed Home Teleport is silent")

	# Room doors: lock on encounter start, unlock on clear; an empty room is silent.
	_fresh()
	var ordinary := _ordinary_neighbour(_dungeon.start_room)
	_dungeon.enter_room(ordinary, _dungeon.door_to(ordinary, _dungeon.start_room))
	await _frames(2)
	var fought := _dungeon.current_room.state == Room.State.COMBAT
	_check(fought and _plays(&"door_close") == 1 and _req(&"door_open") == 0, "doors lock audibly when the encounter starts")
	await _clear_room(_dungeon.current_room)
	_check(_dungeon.current_room.state == Room.State.CLEARED and _plays(&"door_open") == 1, "doors unlock audibly when the room clears")
	_dungeon.enter_room(_dungeon.start_room)
	await _frames(2)
	_fresh()
	_dungeon.enter_room(ordinary, _dungeon.door_to(ordinary, _dungeon.start_room))
	await _frames(5)
	_check(_req(&"door_close") == 0 and _req(&"door_open") == 0, "re-entering a cleared room plays no door sound")

	# Mage death: once, and music behaviour unchanged (fade-out).
	_fresh()
	mage.health.take_damage(1e12)
	mage.health.take_damage(1e12)
	await _frames(10)
	_check(_req(&"mage_death") == 1 and _plays(&"mage_death") == 1 and _req(&"mage_hurt") == 0,
			"Mage death: once, no hurt sound for the killing blow")
	_check(_audio.current_music() == &"", "Mage death still fades the music out")
	_check(_audio.sfx_requests.keys().all(func(id: StringName) -> bool: return SoundLibrary.has(id)),
			"every requested event is in the catalog")
	await _seconds(_audio.fade_out_time + 0.2)
	_audio.stop_all_sfx()


func _fresh() -> void:
	_audio.stop_all_sfx()
	_audio.reset_sfx_counters()


func _req(id: StringName) -> int:
	return int(_audio.sfx_requests.get(id, 0))


func _plays(id: StringName) -> int:
	return int(_audio.sfx_plays.get(id, 0))


## An enemy far from the Mage with its AI off (hooks are called directly).
func _spawn(path: String) -> Enemy:
	var enemy := (load(path) as PackedScene).instantiate() as Enemy
	enemy.position = Vector2(5000, 5000)
	current_scene.add_child(enemy)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	return enemy


## A projectile of the spell at `path`, launched far away (physics off).
func _projectile(path: String, source: Node) -> Projectile:
	var spell := load(path) as Spell
	var shot := spell.projectile_scene.instantiate() as Projectile
	shot.setup(spell, Vector2.RIGHT, source)
	shot.position = Vector2(-5000, -5000)
	current_scene.add_child(shot)
	shot.process_mode = Node.PROCESS_MODE_DISABLED
	return shot


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
