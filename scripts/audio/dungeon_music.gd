class_name DungeonMusic
extends Node
## Chooses the Dungeon's music (Issue #53) from the existing room state; it
## never changes gameplay. The battle track plays while the current room is a
## miniboss room (Dungeon.miniboss_room_indexes()) or the boss room
## (RoomSpec.is_boss) and its encounter is not cleared; otherwise the normal
## track plays. The track switches as soon as the room clears (Room.state_changed),
## even with the Mage still inside, and AudioManager.play_music() ignores repeats,
## so ordinary room changes never restart the music. When the Mage dies the music
## fades out (Game Over) and stays off until the scene is restarted or left.
## Victory needs nothing here: the AudioManager keeps playing while paused.
## The Dungeon creates it in _ready() and calls setup() before the first room.

var _dungeon: Dungeon
var _room: Room
var _audio: AudioManager


func setup(dungeon: Dungeon) -> void:
	_dungeon = dungeon
	_audio = AudioManager.instance(dungeon.get_tree())
	dungeon.room_changed.connect(_on_room_changed)
	dungeon.mage.died.connect(_on_mage_died)
	if dungeon.current_room:
		_on_room_changed(dungeon.current_room, dungeon.current_index)


## True if room `index` holds a miniboss or the boss encounter on this level.
func is_encounter_room(index: int) -> bool:
	if index < 0 or index >= _dungeon.rooms.size():
		return false
	return _dungeon.rooms[index].is_boss or _dungeon.miniboss_room_indexes().has(index)


## The track the current room calls for.
func wanted_track() -> StringName:
	if _room and is_encounter_room(_dungeon.current_index) and _room.state != Room.State.CLEARED:
		return SoundLibrary.MUSIC_BATTLE
	return SoundLibrary.MUSIC_NORMAL


func _on_room_changed(room: Room, _index: int) -> void:
	if _room and is_instance_valid(_room) and _room.state_changed.is_connected(_on_room_state_changed):
		_room.state_changed.disconnect(_on_room_state_changed)
	_room = room
	_room.state_changed.connect(_on_room_state_changed)
	_update()


func _on_room_state_changed(_state: Room.State) -> void:
	_update()


func _update() -> void:
	if _audio == null or _dungeon.mage.is_dead():
		return
	_audio.play_music(wanted_track())


func _on_mage_died() -> void:
	if _audio:
		_audio.stop_music()


func _exit_tree() -> void:
	# Cached rooms outlive a room change; never leave a connection behind.
	if _room and is_instance_valid(_room) and _room.state_changed.is_connected(_on_room_state_changed):
		_room.state_changed.disconnect(_on_room_state_changed)
