class_name Dungeon
extends Node2D
## Fixed dungeon run: shows one Room at a time and moves the persistent Mage
## between rooms through linked doors.
##
## Expected children: "Mage" (Mage), "RoomHud" (RoomHud), "RunState" (RunState)
## and "RunHud" (RunHud). Defeated enemies grant their rewards to RunState;
## level-ups raise the Mage's max HP. Rooms are
## instanced from `rooms` on first visit and cached afterwards, so a cleared
## room stays cleared when revisited. Doors without a link are sealed.
## The Mage node is kept across rooms, so its HP carries over. Restart
## (reloading the scene) starts a fresh run in `start_room` with a fresh RunState.

signal room_changed(room: Room, index: int)

## Room scenes; links refer to them by index.
@export var rooms: Array[PackedScene] = []
## Two-way door links as "<room>:<door> - <room>:<door>", e.g. "0:DoorRight - 1:DoorLeft".
@export var links: PackedStringArray = []
@export var start_room: int = 0
## How far inside the destination door the Mage arrives (pixels).
@export var arrival_distance: float = 72.0
## How far past a door's centre (outwards) the Mage must walk to leave the room.
@export var exit_distance: float = 8.0

var current_room: Room
var current_index: int = -1

## "<room>:<door>" -> [room index, door name]
var _link_map := {}
var _room_cache := {}
var _transitioning := false

@onready var mage: Mage = $Mage
@onready var _hud: RoomHud = $RoomHud
@onready var run_state: RunState = $RunState
@onready var _run_hud: RunHud = $RunHud


func _ready() -> void:
	for link in links:
		var ends := link.split(" - ")
		if ends.size() != 2:
			push_error("Bad dungeon link: %s" % link)
			continue
		_link_map[ends[0].strip_edges()] = _parse_end(ends[1])
		_link_map[ends[1].strip_edges()] = _parse_end(ends[0])
	run_state.leveled_up.connect(_on_leveled_up)
	_run_hud.set_run_state(run_state)
	enter_room(start_room)


## Shows room `index`. With `from_door` (a door name in that room) the Mage
## arrives just inside that door facing inwards and an uncleared room starts
## its encounter at once; otherwise the Mage is placed at PlayerSpawn.
func enter_room(index: int, from_door: StringName = &"") -> void:
	if current_room:
		remove_child(current_room)
	_clear_projectiles()
	current_index = index
	current_room = _get_room(index)
	add_child(current_room)
	move_child(current_room, 0)

	if from_door.is_empty():
		mage.global_position = (current_room.get_node(^"PlayerSpawn") as Node2D).global_position
	else:
		var door := current_room.get_node(NodePath("Doors/" + from_door)) as Door
		var inward := -_outward(door)
		mage.global_position = door.global_position + inward * arrival_distance
		mage.facing = Mage.direction_name(inward)
		# Doors lock behind the Mage: an IDLE room's open doors lead nowhere yet.
		current_room.start_encounter()
	mage.velocity = Vector2.ZERO
	_hud.set_room(current_room)
	room_changed.emit(current_room, index)


func _physics_process(_delta: float) -> void:
	# Exits only work after victory (doors are also open while a room is IDLE).
	if _transitioning or current_room == null or mage.is_dead() or current_room.state != Room.State.CLEARED:
		return
	for door in current_room.get_doors():
		if not door.is_open():
			continue
		var offset := mage.global_position - door.global_position
		var outward := _outward(door)
		# Past the doorway's centre, going out, within the doorway's width.
		if offset.dot(outward) > exit_distance and absf(offset.dot(outward.orthogonal())) < door.size.x / 2.0:
			var target: Array = _link_map[_key(current_index, door.name)]
			_transition.call_deferred(target[0], target[1])
			_transitioning = true
			return


func _transition(index: int, door_name: StringName) -> void:
	enter_room(index, door_name)
	# Let physics settle in the new room before checking doors again.
	await get_tree().physics_frame
	_transitioning = false


func _get_room(index: int) -> Room:
	if not _room_cache.has(index):
		var room := rooms[index].instantiate() as Room
		# get_doors() needs the room to be ready; read the Doors node directly.
		for door: Door in room.get_node(^"Doors").get_children():
			door.sealed = not _link_map.has(_key(index, door.name))
		# Connected once per room instance (rooms are cached), so rewards cannot repeat.
		room.enemy_defeated.connect(_on_enemy_defeated)
		_room_cache[index] = room
	return _room_cache[index]


## Unit vector from the room's interior out through `door` (doors sit on walls).
func _outward(door: Door) -> Vector2:
	var visuals := current_room.get_node(^"Visuals") as RoomVisuals
	var center := current_room.to_global(visuals.floor_rect.get_center())
	var v := door.global_position - center
	return Vector2(signf(v.x), 0.0) if absf(v.x) / visuals.floor_rect.size.x > absf(v.y) / visuals.floor_rect.size.y \
		else Vector2(0.0, signf(v.y))


func _on_enemy_defeated(enemy: Enemy) -> void:
	run_state.add_rewards(enemy.xp_reward, enemy.currency_reward)


func _on_leveled_up(_level: int) -> void:
	mage.health.increase_max_health(run_state.max_health_per_level, run_state.heal_per_level)


func _clear_projectiles() -> void:
	for child in get_children():
		if child is Projectile:
			child.queue_free()


func _key(index: int, door_name: StringName) -> String:
	return "%d:%s" % [index, door_name]


func _parse_end(end: String) -> Array:
	var parts := end.strip_edges().split(":")
	return [int(parts[0]), StringName(parts[1])]


func _exit_tree() -> void:
	# Cached rooms outside the tree are not freed with the scene.
	for room: Room in _room_cache.values():
		if room != current_room and is_instance_valid(room):
			room.free()
