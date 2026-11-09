extends SceneTree
## Headless check of the 5x5 dungeon layout and its progression-gated tiers
## (scenes/dungeon/dungeon.tscn): room links, Level 2 / boss (Level 3) gates,
## tier XP totals, no duplicate rewards, minimap state and Restart. The layout
## is seeded (DungeonLayout, Issue #45); rooms are found by role under a fixed
## seed. Treasure rooms are checked in tools/test_treasure_rooms.gd and the
## layout generator over many seeds in tools/test_dungeon_layout.gd.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_room_progression.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENE := "res://scenes/dungeon/dungeon.tscn"
const SEED := 4242
const ACTIONS := {&"DoorTop": &"move_up", &"DoorBottom": &"move_down", &"DoorLeft": &"move_left", &"DoorRight": &"move_right"}
const OPPOSITE := {&"DoorTop": &"DoorBottom", &"DoorBottom": &"DoorTop", &"DoorLeft": &"DoorRight", &"DoorRight": &"DoorLeft"}

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState
var _gate_cell := Vector2i(-1, -1)


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	RunState.seed_override = SEED
	var scene_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(SCENE)
	await _wait_for_scene(scene_id)
	_bind()
	_test_layout()
	_test_xp_budget()
	await _test_gates()
	await _test_restart()
	RunState.seed_override = 0
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_layout() -> void:
	var cells := {}
	for spec in _dungeon.rooms:
		cells[spec.cell] = spec
	_check(cells.size() == _dungeon.rooms.size(), "all rooms on distinct cells")
	cells = {}
	for spec in _core():
		cells[spec.cell] = spec
	_check(_dungeon.rooms.size() == 25 and cells.size() == 23 and _dungeon.rooms.size() - _core().size() == 2,
			"25 rooms: 23 main rooms + 2 treasure rooms on distinct cells")
	_check(_dungeon.rooms.all(func(r: RoomSpec) -> bool: return r.cell.x >= 0 and r.cell.x < 5 and r.cell.y >= 0 and r.cell.y < 5),
			"all rooms inside the 5x5 grid")
	_check(_dungeon._link_map.size() == _dungeon.links.size() * 2, "every link joins two neighbouring rooms")
	var bad_degree := []
	for i in _dungeon.rooms.size():
		var degree := _dungeon.get_neighbours(i).size()
		var ok := degree == 1 if _dungeon.rooms[i].is_boss or _dungeon.rooms[i].is_treasure() else degree >= 1 and degree <= 4
		if not ok:
			bad_degree.append(_dungeon.rooms[i].cell)
	_check(bad_degree.is_empty(), "every room has 1-4 doors, boss and treasure rooms exactly 1 (bad: %s)" % [bad_degree])
	var tiers_ok := true
	for spec in _core():
		var expected := 3 if spec.is_boss else (1 if spec.cell.y >= 3 else 2)
		tiers_ok = tiers_ok and spec.required_level == expected
	_check(tiers_ok and _core().filter(func(r: RoomSpec) -> bool: return r.is_boss).size() == 1,
			"tiers: rows 3-4 Lv 1, rows 0-2 Lv 2, one boss room at Lv 3")
	# Reachability within each tier (only through rooms of that tier or lower).
	_check(_reachable(1, false).size() == 9, "all 9 Level 1 main rooms reachable at Lv 1 (%d)" % _reachable(1, false).size())
	_check(_reachable(2, false).size() == 22, "all 22 Level 1+2 main rooms reachable at Lv 2 (%d)" % _reachable(2, false).size())
	_check(_reachable(3, false).size() == 23, "boss room reachable at Lv 3 without treasure rooms")
	_check(_reachable(3).size() == _dungeon.rooms.size(), "every room, treasure rooms included, reachable at Lv 3")
	var gates := 0
	for i in _dungeon.rooms.size():
		if _dungeon.rooms[i].required_level == 1 and not _dungeon.rooms[i].is_treasure():
			gates += _dungeon.get_neighbours(i).filter(func(j: int) -> bool: return _dungeon.rooms[j].required_level == 2).size()
	_check(gates >= 2, "more than one route into the Level 2 tier (%d gates)" % gates)


func _test_xp_budget() -> void:
	var xp := {1: [], 2: []}
	for spec in _core():
		if not spec.is_boss:
			xp[spec.required_level].append(_room_xp(spec))
	var l1: Array = xp[1]
	var l2: Array = xp[2]
	var t1: int = l1.reduce(func(a: int, b: int) -> int: return a + b, 0)
	var t2: int = l2.reduce(func(a: int, b: int) -> int: return a + b, 0)
	print("INFO: Level 1 rooms %s = %d XP, Level 2 rooms %s = %d XP" % [l1, t1, l2, t2])
	l1.sort()
	l2.sort()
	_check(t1 >= _run.xp_to_next_level(), "Level 1 tier gives enough XP for Lv 2 (%d >= 50)" % t1)
	_check(t1 - l1[1] - l1[2] < 50, "Lv 2 needs all but at most one Level 1 room")
	var carry := t1 - 50
	_check(t2 >= 100, "Level 2 tier alone gives enough XP for Lv 3 (%d >= 100)" % t2)
	_check(t2 + carry - l2[0] - l2[1] - l2[2] < 100, "Lv 3 needs all but at most two Level 2 rooms")


func _test_gates() -> void:
	var hall := _dungeon.current_room
	hall.start_encounter()
	await _kill_all(hall)
	var hall_doors := _dungeon.get_neighbours(0).map(func(j: int) -> StringName: return _dungeon.door_to(0, j))
	_check(not hall_doors.is_empty() and hall_doors.all(func(d: StringName) -> bool: return _door(hall, d).is_open()), "Level 1 doors open at Lv 1")

	# --- Level 2 gate: a Level 1 room linked to a Level 2 main room ---
	var pair := _gate_pair()
	var gate_index: int = pair[0]
	var l2_index: int = pair[1]
	var gate_door := _dungeon.door_to(gate_index, l2_index)
	var back_door: StringName = OPPOSITE[gate_door]
	var l1_door := _dungeon.door_to(gate_index, _tier1_neighbour(gate_index))
	_dungeon.enter_room(gate_index, l1_door)
	await _frames(2)
	var gate_room := _dungeon.current_room
	await _kill_all(gate_room)
	var up := _door(gate_room, gate_door)
	_check(gate_room.state == Room.State.CLEARED and _door(gate_room, l1_door).is_open(), "cleared Level 1 room opens its Level 1 doors")
	_check(up.level_locked and not up.is_open() and _shape_enabled(up) and up.lock_label == "Lv 2",
			"Level 2 door stays locked at Lv 1, labelled Lv 2")
	_check(not _dungeon.can_enter(l2_index), "Level 2 room not enterable at Lv 1")
	await _try_exit(gate_room, gate_door, ACTIONS[gate_door])
	_check(_dungeon.current_room == gate_room, "Mage cannot pass the Level 2 door at Lv 1")

	_run.add_rewards(_run.xp_to_next_level() - _run.xp, 0)
	await _frames(2)
	_check(_run.level == 2 and not up.level_locked and up.is_open() and not _shape_enabled(up), "Level 2 door opens at Lv 2")
	_check(_message() == "Level 2! Deeper rooms unlocked.", "level-up announces unlocked rooms (%s)" % _message())
	await _try_exit(gate_room, gate_door, ACTIONS[gate_door])
	var l2_room := _dungeon.current_room
	_check(_dungeon.current_index == l2_index, "Level 2 door leads to the Level 2 room")
	await _frames(2)
	var spec := _dungeon.rooms[l2_index]
	# A seeded miniboss room holds only its miniboss instead of the line-up (Issue #43).
	var expected := 1 if _dungeon.miniboss_scene(l2_index) else spec.enemies.size()
	_check(l2_room.state == Room.State.COMBAT and l2_room.enemies_remaining == expected
			and _all_locked(l2_room) and _active_enemies(l2_room) == expected,
			"Level 2 encounter starts on arrival with its spawned enemies (%d)" % l2_room.enemies_remaining)
	var xp_before := _run.xp
	await _kill_all(l2_room)
	var gained := _run.xp - xp_before
	_check(gained == _room_xp(spec) and l2_room.state == Room.State.CLEARED, "Level 2 room grants its XP once (%d)" % gained)

	# --- Revisit: no respawn, no duplicate XP ---
	await _try_exit(l2_room, back_door, ACTIONS[back_door])
	await _try_exit(gate_room, gate_door, ACTIONS[gate_door])
	_check(_dungeon.current_room == l2_room and l2_room.state == Room.State.CLEARED
			and l2_room.get_node(^"Enemies").get_child_count() == 0 and _run.xp == xp_before + gained,
			"revisited Level 2 room stays cleared, no extra XP")

	# --- Minimap state ---
	var map := current_scene.get_node(^"DungeonMap/Map") as DungeonMap
	_check(map != null and map._dungeon == _dungeon, "minimap is bound to the dungeon")
	_check(_dungeon.is_visited(0) and _dungeon.is_visited(gate_index) and _dungeon.is_visited(l2_index)
			and not _dungeon.is_visited(_dungeon.boss_index()), "visited rooms tracked for the minimap")

	# --- Boss gate ---
	# The level gate is checked here; the Ancient Seal half is covered by test_seals.gd.
	_grant_seals()
	var ante_index := _dungeon.index_at(_dungeon.final_anvil_cell)
	_check(_dungeon.get_neighbours(_dungeon.boss_index()) == [ante_index] and _dungeon.door_to(ante_index, _dungeon.boss_index()) == &"DoorTop",
			"the antechamber (anvil room) is the boss room's only neighbour, below it")
	var ante_others := _dungeon.get_neighbours(ante_index).filter(func(j: int) -> bool: return j != _dungeon.boss_index())
	_dungeon.enter_room(ante_index, _dungeon.door_to(ante_index, ante_others[0]))
	await _frames(2)
	var ante := _dungeon.current_room
	await _kill_all(ante)
	var boss_door := _door(ante, &"DoorTop")
	_check(_run.level == 2 and boss_door.level_locked and not boss_door.is_open() and boss_door.lock_label == "BOSS Lv 4",
			"boss gate locked below Lv 4, labelled BOSS Lv 4")
	_check(ante_others.all(func(j: int) -> bool: return _door(ante, _dungeon.door_to(ante_index, j)).is_open()), "other antechamber doors open at Lv 2")
	await _try_exit(ante, &"DoorTop", &"move_up")
	_check(_dungeon.current_room == ante, "Mage cannot pass the boss gate at Lv 2")
	_run.add_rewards(_run.xp_to_next_level() - _run.xp, 0)
	await _frames(2)
	_check(_run.level == 3 and boss_door.level_locked, "boss gate still locked at Lv 3")
	_run.add_rewards(_run.xp_to_next_level() - _run.xp, 0)
	await _frames(2)
	_check(_run.level == 4 and boss_door.is_open(), "boss gate opens at Lv 4")
	_check(_message() == "Level 4! The boss gate is open.", "Lv 4 announces the boss gate (%s)" % _message())
	await _try_exit(ante, &"DoorTop", &"move_up")
	var boss_room := _dungeon.current_room
	_check(_dungeon.current_index == _dungeon.boss_index(), "boss gate leads to the boss room")
	await _frames(2)
	_check(boss_room.state == Room.State.COMBAT and boss_room.enemies_remaining == 1
			and not _door(boss_room, &"DoorBottom").is_open(), "boss fight starts on entry and locks the exit (see test_boss.gd)")
	await _kill_all(boss_room)
	_check(boss_room.state == Room.State.CLEARED and _door(boss_room, &"DoorBottom").is_open()
			and _room_hud_text() == boss_room.cleared_text, "boss room clears and reopens after victory (%s)" % _room_hud_text())


func _test_restart() -> void:
	_mage.take_damage(9999.0)
	await _frames(1)
	var scene_id := current_scene.get_instance_id() if current_scene else 0
	(current_scene.get_node(^"GameOverOverlay") as GameOverOverlay).restart()
	await _wait_for_scene(scene_id)
	_bind()
	_check(_run.level == 1 and _run.xp == 0 and _run.currency == 0 and _run.purchased.is_empty(), "Restart resets the run")
	var visited := range(_dungeon.rooms.size()).filter(func(i: int) -> bool: return _dungeon.is_visited(i))
	_check(visited == [0] and _dungeon.current_room.state == Room.State.IDLE, "Restart resets room progression (only Hall visited)")
	var old_cell := _gate_cell
	var pair := _gate_pair()
	_check(_gate_cell == old_cell, "Restart with the same seed rebuilds the same layout")
	_dungeon.enter_room(pair[0], _dungeon.door_to(pair[0], _tier1_neighbour(pair[0])))
	await _frames(2)
	var gate_room := _dungeon.current_room
	_check(gate_room.state == Room.State.COMBAT and gate_room.enemies_remaining > 0, "Restart respawns room enemies")
	await _kill_all(gate_room)
	_check(_door(gate_room, _dungeon.door_to(pair[0], pair[1])).level_locked, "Restart re-locks the Level 2 gate")


## [Level 1 room, linked Level 2 main room]: the first gate room by index
## (not the start room) that also links to another Level 1 main room.
func _gate_pair() -> Array:
	for i in range(1, _dungeon.rooms.size()):
		var spec := _dungeon.rooms[i]
		if spec.required_level != 1 or spec.is_treasure() or _tier1_neighbour(i) < 0:
			continue
		for j: int in _dungeon.get_neighbours(i):
			if _dungeon.rooms[j].required_level == 2 and not _dungeon.rooms[j].is_treasure():
				_gate_cell = spec.cell
				return [i, j]
	_check(false, "layout has a Level 1 -> Level 2 gate room")
	return [0, 0]


## A Level 1 main room linked to room `index` (-1 if none).
func _tier1_neighbour(index: int) -> int:
	for j: int in _dungeon.get_neighbours(index):
		if _dungeon.rooms[j].required_level == 1 and not _dungeon.rooms[j].is_treasure():
			return j
	return -1


## Main (non-treasure) RoomSpecs.
func _core() -> Array:
	return _dungeon.rooms.filter(func(r: RoomSpec) -> bool: return not r.is_treasure())


## Room indexes reachable from the start room through rooms needing at most
## `level` (optionally ignoring treasure rooms).
func _reachable(level: int, with_treasure: bool = true) -> Dictionary:
	var seen := {_dungeon.start_room: true}
	var queue := [_dungeon.start_room]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for j: int in _dungeon.get_neighbours(i):
			if not seen.has(j) and _dungeon.rooms[j].required_level <= level and (with_treasure or not _dungeon.rooms[j].is_treasure()):
				seen[j] = true
				queue.append(j)
	return seen


## XP from a room's encounter: enemies placed in its scene plus spawned ones.
func _room_xp(spec: RoomSpec) -> int:
	var total := 0
	var room := spec.scene.instantiate()
	for enemy in room.get_node(^"Enemies").get_children():
		total += (enemy as Enemy).xp_reward
	room.free()
	for scene in spec.enemies:
		var enemy := scene.instantiate() as Enemy
		total += enemy.xp_reward
		enemy.free()
	return total


func _bind() -> void:
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage
	_run = _dungeon.run_state
	_run.xp_multiplier_override = 1.0  # raw enemy XP (the scaled budget is tested in test_endless_progression.gd)


func _try_exit(room: Room, door_name: StringName, action: StringName) -> void:
	var door := _door(room, door_name)
	var dir: Vector2 = {&"move_up": Vector2.UP, &"move_down": Vector2.DOWN,
			&"move_left": Vector2.LEFT, &"move_right": Vector2.RIGHT}[action]
	_mage.global_position = door.global_position - dir * 60.0
	Input.action_press(action)
	for i in 50:
		await physics_frame
		if _dungeon.current_room != room:
			break
	Input.action_release(action)
	await _frames(2)


func _kill_all(room: Room) -> void:
	for enemy in room.get_node(^"Enemies").get_children():
		(enemy as Enemy).take_damage(9999.0)
	await _frames(2)


func _door(room: Room, door_name: StringName) -> Door:
	return room.get_node(NodePath("Doors/" + door_name)) as Door


func _all_locked(room: Room) -> bool:
	return room.get_doors().all(func(d: Door) -> bool: return not d.is_open() and _shape_enabled(d))


func _shape_enabled(door: Door) -> bool:
	return not (door.get_node(^"CollisionShape2D") as CollisionShape2D).disabled


func _active_enemies(room: Room) -> int:
	return room.get_node(^"Enemies").get_children().filter(func(e: Node) -> bool: return e.can_process()).size()


func _message() -> String:
	var label := current_scene.get_node(^"RunHud/MessageLabel") as Label
	return label.text if label.visible else ""


func _room_hud_text() -> String:
	var label := current_scene.get_node(^"RoomHud/StatusLabel") as Label
	return label.text if label.visible else ""


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1


## Ancient Seals (Issue #43): the boss gate also needs this level's seals; collect them all.
func _grant_seals() -> void:
	for i: int in _dungeon.seal_rooms():
		_run.collect_seal(_dungeon.seal_id(i))


## Scene changes are deferred: waits until a new, ready scene (not `old_id`) is current.
func _wait_for_scene(old_id: int) -> void:
	for i in 600:
		if current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready():
			break
		await process_frame
	await _frames(2)
