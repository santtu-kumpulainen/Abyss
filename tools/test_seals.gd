extends SceneTree
## Headless check of the Ancient Seals objective (Issue #43, stage 2):
## seal source planning (>= 4 sources for 1-3 miniboss rooms, both treasure
## rooms, reachable before the boss, deterministic per seed), RunState seal
## rules (known sources only, once per level), collecting seals in a combat seal
## room and the rune puzzle (only after the room is complete), revisits, the
## HUD objective, minimap markers, the boss gate (3 seals AND the Mage level
## cap, door label), skipping one source, and the reset on the next level.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_seals.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENE := "res://scenes/dungeon/dungeon.tscn"
const BOSS := Vector2i(2, 0)
const BOSS_ENTRY := Vector2i(2, 1)
const SEEDS := 200

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState
var _prog: ProgressionStore


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_prog = ProgressionStore.instance(self)
	if _prog:
		_prog.clear_progress()
	_test_run_state_rules()
	RunState.seed_override = 777
	await _load()
	if _dungeon == null:
		_check(false, "dungeon scene loaded")
	else:
		_test_planning()
		await _load()
		await _test_combat_seal_and_revisit()
		await _test_puzzle_seal()
		await _test_boss_gate_and_skip()
		await _test_next_level_reset()
	RunState.seed_override = 0
	if _prog:
		_prog.clear_progress()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_run_state_rules() -> void:
	var run := RunState.new()
	var emitted: Array[StringName] = []
	run.seal_collected.connect(func(id: StringName) -> void: emitted.append(id))
	var ids: Array[StringName] = [&"a", &"b", &"c", &"d"]
	run.set_seal_sources(ids)
	_check(not run.collect_seal(&"unknown") and run.seals_collected() == 0, "unknown seal ids cannot be collected")
	_check(run.collect_seal(&"a") and not run.collect_seal(&"a") and run.seals_collected() == 1 and emitted == [&"a"],
			"a seal is collected once; duplicates are rejected and emit nothing")
	run.set_seal_sources(ids)
	_check(run.seals_collected() == 1 and run.is_seal_collected(&"a"), "re-registering the sources keeps collected seals")
	run.collect_seal(&"b")
	_check(not run.seals_complete(), "2 seals: not complete")
	run.collect_seal(&"c")
	_check(run.seals_complete() and run.seals_collected() == RunState.SEALS_REQUIRED and run.can_collect_seal(&"d"),
			"3 of 4 seals complete the objective (the 4th stays optional)")
	run.boss_defeated = true
	run.choose_relic(RunState.RELICS.keys()[0])
	_check(run.begin_next_level() and run.seals_collected() == 0 and run.seal_sources().is_empty() and not run.can_collect_seal(&"d"),
			"next dungeon level: seals and sources reset")
	run.free()


func _test_planning() -> void:
	var anvil := _dungeon.index_at(_dungeon.final_anvil_cell)
	var boss := _dungeon.index_at(BOSS)
	var reachable := _reachable_without_boss()
	for bosses in [1, 2, 3]:
		_dungeon.miniboss_rooms = bosses
		var ok := true
		var kinds_ok := true
		var distinct := {}
		for s in SEEDS:
			_run.run_seed = s + 1
			_dungeon._plan_level()
			var seals := _dungeon.seal_rooms()
			distinct[str(seals.keys())] = true
			var counts := {&"treasure": 0, &"miniboss": 0, &"champion": 0}
			for i: int in seals:
				counts[seals[i]] += 1
				ok = ok and i != boss and i != anvil and reachable.has(i) and not _dungeon.rooms[i].is_boss
			ok = ok and seals.size() >= EncounterPlanner.MIN_SEAL_SOURCES and seals.size() > RunState.SEALS_REQUIRED
			ok = ok and _run.seal_sources().size() == seals.size()
			kinds_ok = kinds_ok and counts[&"treasure"] == 2 and counts[&"miniboss"] == bosses \
					and counts[&"champion"] == maxi(EncounterPlanner.MIN_SEAL_SOURCES - bosses - 2, 0)
		_check(ok, "%d miniboss room(s): >= %d seal sources, never the boss/anvil room, all reachable before the boss (%d seeds)"
				% [bosses, EncounterPlanner.MIN_SEAL_SOURCES, SEEDS])
		_check(kinds_ok, "%d miniboss room(s): both treasure rooms + %d miniboss + champion rooms fill up to %d"
				% [bosses, bosses, EncounterPlanner.MIN_SEAL_SOURCES])
		_check(distinct.size() > 5, "%d miniboss room(s): seal rooms vary between seeds (%d layouts)" % [bosses, distinct.size()])
	_dungeon.miniboss_rooms = 2
	_run.run_seed = 4242
	_dungeon._plan_level()
	var first := _dungeon.seal_rooms()
	_dungeon._plan_level()
	_check(first == _dungeon.seal_rooms(), "same seed -> same seal rooms")


func _test_combat_seal_and_revisit() -> void:
	var index := _combat_seal_room()
	_check(index >= 0, "setup: a combat seal room exists")
	if index < 0:
		return
	var id := _dungeon.seal_id(index)
	var map := current_scene.get_node(^"DungeonMap/Map") as DungeonMap
	_check(_objective().begins_with("Ancient Seals 0/3"), "HUD shows the objective (%s)" % _objective())
	_check(map.seal_marker_color(index) == map.seal_color and map.seal_marker_color(_dungeon.start_room).a == 0.0,
			"minimap: available seal room marked, ordinary rooms not")
	_dungeon.enter_room(index)
	await _frames(2)
	var room := _dungeon.current_room
	var seal := room.get_node_or_null(^"Decor/AncientSeal") as AncientSeal
	_check(seal != null and seal.seal_id == id and seal.run_state == _run, "the seal room holds its Ancient Seal")
	if seal == null:
		return
	room.start_encounter()
	_check(not seal.visible and not seal.collect() and _run.seals_collected() == 0, "the seal stays hidden and locked while the room is not cleared")
	_kill_all(room)
	await _wait_until(func() -> bool: return room.state == Room.State.CLEARED)
	_check(seal.visible and seal.is_active(), "clearing the room reveals the seal")
	_mage.global_position = seal.global_position
	await _wait_until(func() -> bool: return _run.seals_collected() == 1)
	_check(_run.is_seal_collected(id) and not is_instance_valid(seal), "touching the seal collects it")
	await _frames(1)
	_check(_objective().begins_with("Ancient Seals 1/3") and _message().begins_with("Ancient Seal 1/3 claimed"),
			"HUD objective and message follow (%s / %s)" % [_objective(), _message()])
	_check(map.seal_marker_color(index) == map.seal_collected_color, "minimap: collected seal room is dimmed")
	_dungeon.enter_room(_dungeon.start_room)
	await _frames(1)
	_dungeon.enter_room(index)
	await _frames(2)
	_check(_dungeon.current_room.get_node_or_null(^"Decor/AncientSeal") == null and _run.seals_collected() == 1
			and not _run.collect_seal(id), "revisiting: the seal stays collected and cannot be taken again")


func _test_puzzle_seal() -> void:
	var index := -1
	for i: int in _dungeon.seal_rooms():
		if _dungeon.rooms[i].treasure == RoomSpec.Treasure.PUZZLE:
			index = i
	_check(index >= 0, "setup: the rune puzzle is a seal source")
	if index < 0:
		return
	_dungeon.enter_room(index)
	await _frames(2)
	var puzzle := _dungeon.current_room as RunePuzzleRoom
	var seal := puzzle.get_node_or_null(^"Decor/AncientSeal") as AncientSeal
	_check(seal != null and not seal.visible and not seal.collect(), "puzzle seal is locked until the puzzle is solved")
	for rune in puzzle.sequence:
		puzzle.activate(rune)
	await _frames(1)
	_check(puzzle.is_solved() and seal != null and seal.visible and seal.collect() and _run.seals_collected() == 2,
			"solving the rune puzzle releases its seal (2/3)")


func _test_boss_gate_and_skip() -> void:
	var boss := _dungeon.index_at(BOSS)
	var entry := _dungeon.index_at(BOSS_ENTRY)
	_dungeon.enter_room(entry)
	await _frames(1)
	var door := _dungeon.current_room.get_node(^"Doors/DoorTop") as Door
	_check(door.level_locked and door.lock_label == "SEALS 2/3  Lv %d" % _run.max_level() and not _dungeon.can_enter(boss),
			"boss door: locked, label shows seals and level (%s)" % door.lock_label)
	while _run.level < _run.max_level():
		_run.add_rewards(_run.xp_to_next_level(), 0)
	await _frames(1)
	_check(door.level_locked and not door.is_open() and door.lock_label == "SEALS 2/3" and not _dungeon.can_enter(boss),
			"level cap alone does not open the boss gate (%s)" % door.lock_label)
	_check(_message().contains("still needs Ancient Seals"), "the level-up message points to the missing seals (%s)" % _message())
	# Third seal: collected while standing next to the gate. One source stays uncollected.
	var remaining := _dungeon.seal_rooms().keys().filter(func(i: int) -> bool: return not _dungeon.is_seal_collected(i))
	_check(remaining.size() >= 2, "setup: at least two sources left before the third seal")
	_run.collect_seal(_dungeon.seal_id(remaining[0]))
	await _frames(1)
	_check(_run.seals_complete() and not door.level_locked and door.is_open() and door.lock_label == "" and _dungeon.can_enter(boss),
			"3 seals + level cap open the gate at once, skipping a source (%d left)" % (remaining.size() - 1))
	_check(_objective().ends_with("the Warden's gate is open") and _message().begins_with("All Ancient Seals claimed"),
			"HUD reports the open gate (%s)" % _objective())


func _test_next_level_reset() -> void:
	# Seals without the level: gate shut, label shows the level.
	await _load()
	for i: int in _dungeon.seal_rooms():
		_run.collect_seal(_dungeon.seal_id(i))
	_dungeon.enter_room(_dungeon.index_at(BOSS_ENTRY))
	await _frames(1)
	var door := _dungeon.current_room.get_node(^"Doors/DoorTop") as Door
	_check(door.level_locked and door.lock_label == "BOSS Lv %d" % _run.max_level() and _objective().contains("reach Lv"),
			"seals alone do not open the gate (%s)" % door.lock_label)
	while _run.level < _run.max_level():
		_run.add_rewards(_run.xp_to_next_level(), 0)
	_dungeon.enter_room(_dungeon.index_at(BOSS), &"DoorBottom")
	await _frames(2)
	for e in _dungeon.current_room.get_node(^"Enemies").get_children():
		if e is Boss:
			(e as Boss).take_damage(999999.0)
	await _wait_until(func() -> bool: return _dungeon.victory)
	_run.choose_relic(Biomes.relic_pool(_run.dungeon_level)[0])
	_check(_dungeon.advance_level(), "setup: advanced to the next dungeon level")
	await _frames(2)
	_check(_run.dungeon_level == 2 and _run.seals_collected() == 0 and _run.seal_sources().size() >= EncounterPlanner.MIN_SEAL_SOURCES
			and _dungeon.seal_rooms().size() == _run.seal_sources().size(), "next level: seals reset, new sources registered")
	_check(_objective().begins_with("Ancient Seals 0/3"), "HUD objective resets (%s)" % _objective())
	var any := _dungeon.seal_rooms().keys()[0] as int
	_check(_run.can_collect_seal(_dungeon.seal_id(any)), "seals can be collected again on the new level")
	_dungeon.enter_room(_dungeon.index_at(BOSS_ENTRY))
	await _frames(1)
	door = _dungeon.current_room.get_node(^"Doors/DoorTop") as Door
	_check(door.level_locked and not _dungeon.can_enter(_dungeon.index_at(BOSS)), "next level: the boss gate is sealed again")


## Room indexes reachable from the start without entering the boss room.
func _reachable_without_boss() -> Dictionary:
	var seen := {_dungeon.start_room: true}
	var queue: Array = [_dungeon.start_room]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for j: int in _dungeon.get_neighbours(i):
			if not seen.has(j) and not _dungeon.rooms[j].is_boss:
				seen[j] = true
				queue.append(j)
	return seen


func _combat_seal_room() -> int:
	var seals := _dungeon.seal_rooms()
	for i: int in seals:
		if seals[i] != &"treasure":
			return i
	return -1


func _kill_all(room: Room) -> void:
	for e in room.get_node(^"Enemies").get_children():
		if e is Enemy and not e.is_queued_for_deletion():
			(e as Enemy).take_damage(999999.0)


func _objective() -> String:
	return (current_scene.get_node(^"RunHud/ObjectiveLabel") as Label).text


func _message() -> String:
	return (current_scene.get_node(^"RunHud/MessageLabel") as Label).text


func _load() -> void:
	paused = false
	var old_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(SCENE)
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_dungeon = current_scene as Dungeon
	if _dungeon:
		_mage = _dungeon.mage
		_run = _dungeon.run_state


func _wait_until(condition: Callable, max_frames: int = 300) -> void:
	for i in max_frames:
		if condition.call():
			return
		await process_frame


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
