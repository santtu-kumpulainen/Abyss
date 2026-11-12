class_name AudioManager
extends Node
## Autoload "Audio" (Issue #53). Access it with AudioManager.instance(get_tree()),
## which also works in --script test runs where the global name cannot be
## compiled. Plays everything listed in SoundLibrary: music on the Music bus,
## sound effects on the SFX bus. Gameplay code asks for ids and never creates
## audio players itself.
##
## Music: two players crossfade, so at most one track is audible outside a fade.
## play_music() with the track that is already playing does nothing (no restart).
## The normal track resumes where it left off after the battle track; the battle
## track starts from its beginning each encounter. stop_music() fades out and
## forgets the resume positions (Game Over, so a restart starts fresh).
## The node always processes, so music and fades continue while the tree is
## paused (victory screen) and across scene changes (it is not part of a scene).
##
## SFX: a fixed pool of players. Each id plays a random variant (never the same
## one twice in a row) with its catalog volume and pitch spread, at most
## `max_voices` at once and not again within its `cooldown`; extra requests are
## dropped. Missing catalog events play nothing; unknown ids warn.
##
## Volume: set_bus_volume() / bus_volume() change the Master, Music and SFX
## buses at runtime (defaults: default_bus_layout.tres; nothing is saved).

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
## Simultaneous sound effects across all ids.
const SFX_POOL_SIZE := 16
## Tracks that resume from where they were faded out.
const RESUMING_TRACKS: Array[StringName] = [SoundLibrary.MUSIC_NORMAL]

## Seconds of a crossfade between tracks.
var crossfade_time := 1.2
## Seconds of stop_music()'s fade-out (Game Over).
var fade_out_time := 2.0
## Volume of a music track at full fade (on top of the Music bus).
var music_volume_db := 0.0

static var _fallback: AudioManager

var _music: Array[AudioStreamPlayer] = []
var _music_tweens: Array[Tween] = [null, null]
## Index into _music of the player holding the current track.
var _active := 0
var _current: StringName = &""
## Track -> playback position to resume from (RESUMING_TRACKS only).
var _positions := {}

var _sfx: Array[AudioStreamPlayer] = []
## Sound id -> Time.get_ticks_msec() of its last play.
var _last_played := {}
## Sound id -> index of the variant it played last.
var _last_variant := {}


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % i
		player.bus = MUSIC_BUS
		_music.append(player)
		add_child(player)
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % i
		player.bus = SFX_BUS
		_sfx.append(player)
		add_child(player)


## The "Audio" autoload, or (if it is missing) a shared stand-in that is added
## to the root at the end of the frame (it plays nothing until then).
static func instance(tree: SceneTree) -> AudioManager:
	if tree == null:
		return null
	var node := tree.root.get_node_or_null(^"Audio") as AudioManager
	if node:
		return node
	if _fallback == null or not is_instance_valid(_fallback):
		_fallback = AudioManager.new()
		_fallback.name = &"Audio"
		tree.root.add_child.call_deferred(_fallback)
	return _fallback


# --- Music ------------------------------------------------------------------------

## Crossfades to `track` (a SoundLibrary.MUSIC id) over `fade` seconds (< 0 =
## crossfade_time, 0 = cut). Returns false for an unknown track (nothing changes).
func play_music(track: StringName, fade: float = -1.0) -> bool:
	var stream := SoundLibrary.music(track)
	if stream == null:
		push_warning("AudioManager: unknown music track '%s'" % track)
		return false
	if track == _current and _music[_active].playing:
		return true
	if not is_inside_tree():
		return false
	if fade < 0.0:
		fade = crossfade_time
	_fade_out_active(fade)
	_active = 1 - _active
	var player := _music[_active]
	_kill_music_tween(_active)
	player.stream = stream
	var target := db_to_linear(music_volume_db)
	player.volume_linear = 0.0 if fade > 0.0 else target
	player.play(_positions.get(track, 0.0))
	_current = track
	if fade > 0.0:
		_music_tweens[_active] = _fade(player, target, fade, false)
	return true


## Fades the current track out over `fade` seconds (< 0 = fade_out_time) and
## forgets the resume positions. Does nothing without music.
func stop_music(fade: float = -1.0) -> void:
	_fade_out_active(fade_out_time if fade < 0.0 else fade)
	_current = &""
	_positions.clear()


## The track playing (or fading in), or &"" after stop_music().
func current_music() -> StringName:
	return _current


## Music players currently playing (2 only during a crossfade or fade-out).
func playing_music_players() -> int:
	return _music.filter(func(p: AudioStreamPlayer) -> bool: return p.playing).size()


## The player of the current track (tests and debugging).
func active_music_player() -> AudioStreamPlayer:
	return _music[_active]


func _fade_out_active(fade: float) -> void:
	var player := _music[_active]
	_kill_music_tween(_active)
	if not player.playing:
		return
	if RESUMING_TRACKS.has(_current):
		_positions[_current] = player.get_playback_position()
	if fade <= 0.0:
		player.stop()
	else:
		_music_tweens[_active] = _fade(player, 0.0, fade, true)


func _fade(player: AudioStreamPlayer, to: float, time: float, stop_after: bool) -> Tween:
	var tween := create_tween()
	tween.tween_property(player, ^"volume_linear", to, time)
	if stop_after:
		tween.tween_callback(player.stop)
	return tween


func _kill_music_tween(index: int) -> void:
	if _music_tweens[index] and _music_tweens[index].is_valid():
		_music_tweens[index].kill()
	_music_tweens[index] = null


# --- Sound effects ----------------------------------------------------------------

## Plays a variant of sound event `id`. Returns false if nothing was played: an
## unknown id (warns), a missing event (silent), the cooldown or voice limit.
func play_sfx(id: StringName) -> bool:
	if not SoundLibrary.has(id):
		push_warning("AudioManager: unknown sound event '%s'" % id)
		return false
	var variants := SoundLibrary.streams(id)
	if variants.is_empty() or not is_inside_tree():
		return false
	var now := Time.get_ticks_msec()
	var cooldown_ms := float(SoundLibrary.setting(id, "cooldown")) * 1000.0
	if _last_played.has(id) and now - int(_last_played[id]) < cooldown_ms:
		return false
	if sfx_voices(id) >= int(SoundLibrary.setting(id, "max_voices")):
		return false
	var player := _free_sfx_player()
	if player == null:
		return false
	var index := randi() % variants.size()
	if variants.size() > 1 and index == int(_last_variant.get(id, -1)):
		index = (index + 1) % variants.size()
	var spread := float(SoundLibrary.setting(id, "pitch"))
	player.stream = variants[index]
	player.volume_db = float(SoundLibrary.setting(id, "volume_db"))
	player.pitch_scale = 1.0 + randf_range(-spread, spread)
	player.set_meta(&"sound_id", id)
	player.play()
	_last_played[id] = now
	_last_variant[id] = index
	return true


## Plays of sound event `id` still sounding.
func sfx_voices(id: StringName) -> int:
	return _sfx.filter(func(p: AudioStreamPlayer) -> bool:
		return p.playing and p.get_meta(&"sound_id", &"") == id).size()


## Stops every sound effect (music is not affected) and resets the cooldowns.
func stop_all_sfx() -> void:
	for player in _sfx:
		player.stop()
	_last_played.clear()


func _free_sfx_player() -> AudioStreamPlayer:
	for player in _sfx:
		if not player.playing:
			return player
	return null


# --- Volume -----------------------------------------------------------------------

## Sets bus `bus` ("Master", "Music" or "SFX") to `db`. Returns false for an unknown bus.
func set_bus_volume(bus: StringName, db: float) -> bool:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		push_warning("AudioManager: unknown audio bus '%s'" % bus)
		return false
	AudioServer.set_bus_volume_db(index, db)
	return true


## Volume of bus `bus` in dB, or NAN for an unknown bus.
func bus_volume(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	return AudioServer.get_bus_volume_db(index) if index >= 0 else NAN
