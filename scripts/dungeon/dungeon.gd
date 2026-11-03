class_name Dungeon
extends Node2D
## Fixed dungeon run: shows one Room at a time and moves the persistent Mage
## between rooms through linked doors.
##
## Expected children: "Mage" (Mage), "RoomHud" (RoomHud), "RunState" (RunState)
## and "RunHud" (RunHud). Defeated enemies grant their rewards to RunState;
## level-ups and the Vitality upgrade raise the Mage's max HP, and the Mage's
## spell modifiers follow RunState (level + upgrades). UpgradeStations inside
## rooms are given the RunState. Rooms are
## instanced from `rooms` (RoomSpecs on a grid) on first visit and cached
## afterwards, so a cleared room stays cleared (and grants no more rewards)
## when revisited. Doors without a link are sealed. Doors leading to a room
## whose `required_level` is above the Mage's level are level-locked and
## labelled; they open when the level is reached. An optional "DungeonMap/Map"
## child is given this Dungeon to draw the explored rooms.
## Rooms whose RoomSpec has an `item` get an ItemPickup (`item_pickup_scene`);
## collected items raise max HP / speed / damage through RunState. Defeating a
## Boss marks RunState.boss_defeated and announces the victory; its phase
## changes are announced too. Once every non-boss room is cleared, one extra
## UpgradeStation (`upgrade_station_scene`) is added to the room at
## `final_anvil_cell` (the room outside the boss gate), so the Mage can spend
## gold before the boss without walking back to the start.
## Victory: the first Boss death (while the Mage lives) ends the run once:
## the Mage stops and ignores damage, projectiles are removed, and after
## `victory_delay` seconds the optional "VictoryOverlay" child opens (relic
## choice, then run_summary()). The chosen relic's max HP bonus is applied
## once through RunState.relic_chosen; its other bonuses follow RunState.
## The Mage node is kept across rooms, so its HP carries over. Restart
## (reloading the scene) starts a fresh run in `start_room` with a fresh RunState.

signal room_changed(room: Room, index: int)
## Something the map shows changed (room entered or cleared, level gates).
signal map_changed
## Emitted once when the boss is defeated and the run is won.
signal victory_started

const DOOR_BY_DIRECTION := {
	Vector2i.RIGHT: &"DoorRight", Vector2i.LEFT: &"DoorLeft",
	Vector2i.UP: &"DoorTop", Vector2i.DOWN: &"DoorBottom",
}

## Rooms of the dungeon; indexes are used by enter_room()/start_room.
@export var rooms: Array[RoomSpec] = []
## Two-way door links between neighbouring cells as "x,y - x,y", e.g. "2,4 - 3,4"
## (the door names follow from the direction).
@export var links: PackedStringArray = []
@export var start_room: int = 0
## How far inside the destination door the Mage arrives (pixels).
@export var arrival_distance: float = 72.0
## How far past a door's centre (outwards) the Mage must walk to leave the room.
@export var exit_distance: float = 8.0
## Scene instanced for RoomSpec.item pickups (root must be an ItemPickup).
@export var item_pickup_scene: PackedScene
## Anvil added once all non-boss rooms are cleared (root must be an UpgradeStation).
@export var upgrade_station_scene: PackedScene
## Cell of the (non-boss) room that receives that anvil.
@export var final_anvil_cell := Vector2i(2, 1)
## Its position in room coordinates (clear of doors and spawn points).
@export var final_anvil_position := Vector2(760, 150)
## Seconds between the boss's death and the victory screen.
@export var victory_delay: float = 1.2

var current_room: Room
var current_index: int = -1
## The anvil added after the full clear (null until then).
var final_anvil: UpgradeStation
## True once the run is won (set once, on the boss's death).
var victory := false

## "<room>:<door>" -> [room index, door name]
var _link_map := {}
## Room index -> linked room indexes.
var _neighbours := {}
var _room_cache := {}
var _transitioning := false

@onready var mage: Mage = $Mage
@onready var _hud: RoomHud = $RoomHud
@onready var run_state: RunState = $RunState
@onready var _run_hud: RunHud = $RunHud
@onready var _map: DungeonMap = get_node_or_null(^"DungeonMap/Map")
@onready var _victory_overlay: VictoryOverlay = get_node_or_null(^"VictoryOverlay")


func _ready() -> void:
	_build_links()
	run_state.leveled_up.connect(_on_leveled_up)
	run_state.upgrade_purchased.connect(_on_upgrade_purchased)
	run_state.item_collected.connect(_on_item_collected)
	run_state.relic_chosen.connect(_on_relic_chosen)
	run_state.changed.connect(_apply_spell_modifiers)
	_apply_spell_modifiers()
	_run_hud.set_run_state(run_state)
	if _map:
		_map.set_dungeon(self)
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
	_update_level_gates(index)
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
	map_changed.emit()


## True if room `index` has been entered this run.
func is_visited(index: int) -> bool:
	return _room_cache.has(index)


func is_cleared(index: int) -> bool:
	return is_visited(index) and (_room_cache[index] as Room).state == Room.State.CLEARED


## True when every non-boss room has been cleared this run.
func all_rooms_cleared() -> bool:
	for i in rooms.size():
		if not rooms[i].is_boss and not is_cleared(i):
			return false
	return true


## Number of rooms (boss room included) cleared this run.
func rooms_cleared_count() -> int:
	var count := 0
	for i in rooms.size():
		if is_cleared(i):
			count += 1
	return count


## Tracked run statistics for the victory screen. "items", "upgrades" are
## id lists in collection/purchase order; "relic" is &"" if none was chosen.
func run_summary() -> Dictionary:
	return {
		"level": run_state.level,
		"rooms_cleared": rooms_cleared_count(),
		"rooms_total": rooms.size(),
		"items": run_state.collected.keys(),
		"upgrades": run_state.purchased.keys(),
		"enemies_defeated": run_state.enemies_defeated,
		"relic": run_state.relic,
	}


## True if the Mage's level allows entering room `index`.
func can_enter(index: int) -> bool:
	return run_state.level >= rooms[index].required_level


## Indexes of the rooms linked to room `index`.
func get_neighbours(index: int) -> Array:
	return _neighbours.get(index, [])


## Room index at grid `cell`, or -1.
func index_at(cell: Vector2i) -> int:
	for i in rooms.size():
		if rooms[i].cell == cell:
			return i
	return -1


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
		var spec := rooms[index]
		var room := spec.scene.instantiate() as Room
		if not spec.enemies.is_empty():
			room.add_encounter_enemies(spec.enemies)
		if not spec.item.is_empty() and item_pickup_scene:
			var pickup := item_pickup_scene.instantiate() as ItemPickup
			pickup.item_id = spec.item
			pickup.position = spec.item_position
			room.get_node(^"Decor").add_child(pickup, true)
		# get_doors() needs the room to be ready; read the Doors node directly.
		for door: Door in room.get_node(^"Doors").get_children():
			door.sealed = not _link_map.has(_key(index, door.name))
		# Connected once per room instance (rooms are cached), so rewards cannot repeat.
		room.enemy_defeated.connect(_on_enemy_defeated)
		room.cleared.connect(_on_room_cleared)
		for node in room.find_children("*", "", true, false):
			if node is UpgradeStation:
				(node as UpgradeStation).run_state = run_state
			elif node is ItemPickup:
				(node as ItemPickup).run_state = run_state
			elif node is Boss:
				var boss := node as Boss
				boss.phase_changed.connect(func(p: int) -> void:
					_run_hud.show_message("%s grows stronger! Phase %d" % [boss.display_name, p]))
		_room_cache[index] = room
	return _room_cache[index]


## Unit vector from the room's interior out through `door` (doors sit on walls).
func _outward(door: Door) -> Vector2:
	var visuals := current_room.get_node(^"Visuals") as RoomVisuals
	var center := current_room.to_global(visuals.floor_rect.get_center())
	var v := door.global_position - center
	return Vector2(signf(v.x), 0.0) if absf(v.x) / visuals.floor_rect.size.x > absf(v.y) / visuals.floor_rect.size.y \
		else Vector2(0.0, signf(v.y))


func _on_room_cleared() -> void:
	map_changed.emit()
	_spawn_final_anvil()


## Adds the pre-boss anvil once, after the last non-boss room is cleared.
func _spawn_final_anvil() -> void:
	if final_anvil or upgrade_station_scene == null or not all_rooms_cleared():
		return
	var index := index_at(final_anvil_cell)
	if index < 0 or rooms[index].is_boss:
		push_error("Dungeon: final_anvil_cell %s is not a non-boss room" % final_anvil_cell)
		return
	final_anvil = upgrade_station_scene.instantiate() as UpgradeStation
	final_anvil.name = &"UpgradeStation"
	final_anvil.position = final_anvil_position
	final_anvil.run_state = run_state
	_get_room(index).get_node(^"Decor").add_child(final_anvil, true)
	_run_hud.show_message("Dungeon cleared! An anvil awaits before the boss gate.")


func _on_enemy_defeated(enemy: Enemy) -> void:
	run_state.enemies_defeated += 1
	run_state.add_rewards(enemy.xp_reward, enemy.currency_reward)
	if enemy is Boss and not run_state.boss_defeated:
		run_state.boss_defeated = true
		_run_hud.show_message("%s defeated! +%d gold. Victory!" % [(enemy as Boss).display_name, enemy.currency_reward])
		_start_victory()


## Ends the run once: freezes the Mage, removes projectiles, then opens the
## victory screen. Skipped if the Mage already died (Game Over wins).
func _start_victory() -> void:
	if victory or mage.is_dead():
		return
	victory = true
	mage.end_run()
	_clear_projectiles()
	victory_started.emit()
	if victory_delay <= 0.0:
		_open_victory_overlay()
		return
	# A child Timer is freed with the scene if the run is restarted first.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = victory_delay
	timer.timeout.connect(_open_victory_overlay)
	add_child(timer)
	timer.start()


func _open_victory_overlay() -> void:
	if _victory_overlay:
		_victory_overlay.open(self)


## RunState only emits this once per run.
func _on_relic_chosen(id: StringName) -> void:
	var bonus: float = RunState.RELICS[id].get("max_health", 0.0)
	if bonus > 0.0:
		mage.health.increase_max_health(bonus, bonus)


func _on_leveled_up(new_level: int) -> void:
	mage.health.increase_max_health(run_state.max_health_per_level, run_state.heal_per_level)
	if current_index >= 0:
		_update_level_gates(current_index)
	map_changed.emit()
	var unlocked := rooms.filter(func(r: RoomSpec) -> bool: return r.required_level == new_level)
	if unlocked.any(func(r: RoomSpec) -> bool: return r.is_boss):
		_run_hud.show_message("Level %d! The boss gate is open." % new_level)
	elif not unlocked.is_empty():
		_run_hud.show_message("Level %d! Deeper rooms unlocked." % new_level)
	else:
		_run_hud.show_message("Level %d!" % new_level)


## Level-locks the doors of room `index` that lead to rooms above the Mage's level.
func _update_level_gates(index: int) -> void:
	var room := _get_room(index)
	for door: Door in room.get_node(^"Doors").get_children():
		var key := _key(index, door.name)
		if not _link_map.has(key):
			continue
		var target: RoomSpec = rooms[_link_map[key][0]]
		door.level_locked = run_state.level < target.required_level
		door.lock_label = ("BOSS Lv %d" if target.is_boss else "Lv %d") % target.required_level


func _on_upgrade_purchased(id: StringName) -> void:
	var bonus: float = RunState.UPGRADES[id].get("max_health", 0.0)
	if bonus > 0.0:
		mage.health.increase_max_health(bonus, bonus)


## RunState only emits this once per item per run.
func _on_item_collected(id: StringName) -> void:
	var data: Dictionary = RunState.ITEMS[id]
	var bonus: float = data.get("max_health", 0.0)
	if bonus > 0.0:
		mage.health.increase_max_health(bonus, bonus)
	_run_hud.show_message("%s: %s" % [data["name"], data["effect"]])


## Idempotent: recomputed from RunState, so bonuses never stack twice.
func _apply_spell_modifiers() -> void:
	mage.caster.set_modifiers(run_state.spell_damage_multiplier(), run_state.spell_cooldown_multiplier())
	mage.speed_multiplier = run_state.move_speed_multiplier()


func _clear_projectiles() -> void:
	for child in get_children():
		if child is Projectile:
			child.queue_free()


func _key(index: int, door_name: StringName) -> String:
	return "%d:%s" % [index, door_name]


## Fills _link_map/_neighbours from `links`; door names follow from the cell offsets.
func _build_links() -> void:
	for link in links:
		var ends := link.split(" - ")
		var a := index_at(_parse_cell(ends[0])) if ends.size() == 2 else -1
		var b := index_at(_parse_cell(ends[1])) if ends.size() == 2 else -1
		if a < 0 or b < 0 or not DOOR_BY_DIRECTION.has(rooms[b].cell - rooms[a].cell):
			push_error("Bad dungeon link (needs two neighbouring room cells): %s" % link)
			continue
		var door_a: StringName = DOOR_BY_DIRECTION[rooms[b].cell - rooms[a].cell]
		var door_b: StringName = DOOR_BY_DIRECTION[rooms[a].cell - rooms[b].cell]
		_link_map[_key(a, door_a)] = [b, door_b]
		_link_map[_key(b, door_b)] = [a, door_a]
		_neighbours[a] = _neighbours.get(a, []) + [b]
		_neighbours[b] = _neighbours.get(b, []) + [a]


func _parse_cell(text: String) -> Vector2i:
	var parts := text.strip_edges().split(",")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(-99, -99)


func _exit_tree() -> void:
	# Cached rooms outside the tree are not freed with the scene.
	for room: Room in _room_cache.values():
		if room != current_room and is_instance_valid(room):
			room.free()
