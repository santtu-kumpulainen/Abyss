extends SceneTree
## Headless check of saving and resuming an unfinished run (Issue #63):
## the save written at safe points, a full resume (room, cleared rooms,
## enemies, HP, XP, gold, items, map) without duplicate rewards, the
## room-entry checkpoint when leaving mid-fight, the pending boss reward
## (victory) resume without a second unlock, death deleting the save, a new
## run never restoring the old one, and damaged / outdated / invalid files.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_run_save.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const DUNGEON_SCENE := "res://scenes/dungeon/dungeon.tscn"
const SAVE_FILE := "user://run_save_suite.json"
const SEED := 4242

var _failures := 0
var _prog: ProgressionStore
var _dungeon: Dungeon


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RunSave.path_override = SAVE_FILE
	RunSave.delete()
	RunState.seed_override = SEED
	_prog = ProgressionStore.instance(self)
	_prog.clear_progress()
	await _test_resume_cleared_room()
	await _test_mid_fight_checkpoint()
	await _test_victory_resume()
	await _test_pause_menu_leave()
	await _test_layout_mismatch()
	await _test_death_and_new_run()
	_test_file_handling()
	RunSave.delete()
	RunSave.path_override = ""
	RunState.seed_override = 0
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## Steps 1-8 of the issue's test plan.
func _test_resume_cleared_room() -> void:
	await _load_dungeon()
	var first := RunSave.read()
	_check(first["status"] == RunSave.Status.VALID and not _dungeon.resumed, "a new run writes a valid save at its start")
	# A room with an item pickup: enter it, defeat its enemies, collect the item.
	var item_room := -1
	for i in _dungeon.rooms.size():
		if not _dungeon.rooms[i].item.is_empty() and not _dungeon.room_lineup(i).is_empty():
			item_room = i
			break
	_check(item_room >= 0, "the seeded level has an item room with enemies")
	if item_room < 0:
		return
	await _enter(item_room)
	await _kill_all()
	await _frames(3)
	var pickup := _first_pickup(_dungeon.current_room)
	_check(_dungeon.current_room.state == Room.State.CLEARED and pickup != null, "item room cleared, its pickup is active")
	var item_id := pickup.item_id if pickup else &""
	var collected_ok := pickup != null and pickup.collect()
	await _frames(3)
	_dungeon.mage.global_position = Vector2(400, 300)
	_dungeon.mage.health.take_damage(7.0)
	_check(_dungeon.save_run(), "saving outside combat succeeds")
	var before := _snapshot()
	var visited_before := _visited()
	var saved := RunSave.read()
	_check(collected_ok and saved["status"] == RunSave.Status.VALID
			and int(saved["data"]["run"]["collected"].get(String(item_id), 0)) == 1, "the save holds the collected item")

	# Leave and launch again: Continue resumes the run.
	await _resume(saved["data"])
	_check(_dungeon.resumed and _dungeon.current_index == item_room, "resumes in the saved room")
	var room := _dungeon.current_room
	_check(room.state == Room.State.CLEARED and _alive_enemies(room) == 0, "the cleared room stays cleared (no enemies return)")
	_check(_snapshot() == before, "HP, max HP, XP, level, gold, items and seals are restored exactly\n  %s\n  %s" % [before, _snapshot()])
	_check(_visited() == visited_before, "the map shows the same visited rooms")
	_check(_dungeon.mage.global_position.distance_to(Vector2(400, 300)) < 1.0, "the Mage is back where it stood")
	_check(_first_pickup(room) == null and not _dungeon.run_state.can_collect(item_id),
			"the collected item is gone and cannot be collected twice")
	# Resuming also kept saving: the file now matches the resumed run.
	_check(RunSave.read()["data"]["run"]["collected"] == saved["data"]["run"]["collected"], "the resumed run's save keeps the items")


## Leaving during a fight resumes at that room's entry with the fight reset
## and its rewards rolled back (no duplicate XP / gold).
func _test_mid_fight_checkpoint() -> void:
	var target := -1
	for n: int in _dungeon.get_neighbours(_dungeon.current_index):
		if not _dungeon.is_visited(n) and _dungeon.room_lineup(n).size() >= 2 and not _dungeon.rooms[n].is_boss:
			target = n
			break
	if target < 0:
		for i in _dungeon.rooms.size():
			if not _dungeon.is_visited(i) and _dungeon.room_lineup(i).size() >= 2 and not _dungeon.rooms[i].is_boss \
					and not _dungeon.rooms[i].is_treasure():
				target = i
				break
	await _enter(target)
	var room := _dungeon.current_room
	var enemies_at_entry := _alive_enemies(room)
	var entry := _snapshot()
	var door := _dungeon._entry_door
	var killed := false
	for enemy in room.get_node(^"Enemies").get_children():
		if enemy is Enemy and not (enemy as Enemy).health.is_dead():
			(enemy as Enemy).take_damage(1.0e9)
			killed = true
			break
	await _frames(5)
	_check(killed and room.state == Room.State.COMBAT and _dungeon.run_state.xp + _dungeon.run_state.level * 1000 != entry["xp"] + entry["level"] * 1000,
			"a kill mid-fight granted XP")
	_check(not _dungeon.save_run(), "nothing is saved during combat")
	var saved := RunSave.read()
	_check(saved["status"] == RunSave.Status.VALID and saved["data"]["dungeon"]["in_combat"]
			and int(saved["data"]["dungeon"]["current_index"]) == target, "the save is the room-entry checkpoint")
	await _resume(saved["data"])
	room = _dungeon.current_room
	_check(_dungeon.current_index == target and room.state == Room.State.COMBAT and _alive_enemies(room) == enemies_at_entry,
			"resume re-enters the fight with every enemy of the encounter")
	_check(_snapshot()["xp"] == entry["xp"] and _snapshot()["gold"] == entry["gold"] and _snapshot()["level"] == entry["level"],
			"rewards of the interrupted fight were rolled back with it")
	_check(_dungeon._entry_door == door, "the Mage re-enters through the same door")
	await _kill_all()
	await _frames(3)


## The boss dies, the game is left before the relic is chosen: the resume shows
## the relic choice again; the boss stays dead and the unlock is not repeated.
func _test_victory_resume() -> void:
	var boss_room := _dungeon.boss_index()
	await _enter(boss_room)
	await _kill_all()
	await _wait_for_overlay()
	await _frames(3)
	var completions := _prog.completion_count(_dungeon.run_state.difficulty)
	var saved := RunSave.read()
	_check(_dungeon.victory and saved["status"] == RunSave.Status.VALID and saved["data"]["dungeon"]["victory"],
			"the boss kill is saved as a pending boss reward")
	paused = false
	await _resume(saved["data"])
	await _wait_for_overlay()
	var overlay := _dungeon.get_node(^"VictoryOverlay") as VictoryOverlay
	_check(_dungeon.victory and overlay.is_open and _alive_enemies(_dungeon.current_room) == 0,
			"resume reopens the relic choice; the boss is not resurrected")
	_check(_prog.completion_count(_dungeon.run_state.difficulty) == completions, "the victory is not recorded twice")
	var level := _dungeon.run_state.dungeon_level
	var relic: StringName = Biomes.relic_pool(level)[0]
	_check(overlay.choose_relic(relic) and _dungeon.run_state.dungeon_level == level + 1, "choosing the relic starts the next level")
	await _frames(3)
	var next := RunSave.read()
	_check(next["status"] == RunSave.Status.VALID and int(next["data"]["run"]["dungeon_level"]) == level + 1
			and not next["data"]["dungeon"]["victory"] and (next["data"]["run"]["relics"] as Array).has(String(relic)),
			"the new level is saved with the relic")
	paused = false


## Pause -> "Save & Main Menu" saves the current state and the menu offers Continue;
## during a fight the pause menu says the fight will restart.
func _test_pause_menu_leave() -> void:
	var pause := _dungeon.get_node(^"PauseMenu") as PauseMenu
	_dungeon.mage.global_position = Vector2(520, 330)
	await _frames(2)
	_check(pause.open() and pause.save_note_text().contains("saved"), "pause menu: outside combat the run is saved")
	var level := _dungeon.run_state.dungeon_level
	var scene_id := current_scene.get_instance_id()
	pause.main_menu()
	await _wait_for_scene(scene_id)
	var saved := RunSave.read()
	var menu := current_scene as MainMenu
	_check(menu != null and not paused and saved["status"] == RunSave.Status.VALID
			and int(saved["data"]["run"]["dungeon_level"]) == level
			and Vector2(saved["data"]["dungeon"]["position"][0], saved["data"]["dungeon"]["position"][1]).distance_to(Vector2(520, 330)) < 1.0,
			"Save & Main Menu saves where the Mage stands")
	_check(menu != null and (menu.get_node(^"%ContinueButton") as Button).visible, "the main menu then offers Continue")
	await _resume(saved["data"])
	_check(_dungeon.resumed and _dungeon.run_state.dungeon_level == level, "Continue from the menu resumes that run")
	# During a fight the note explains the checkpoint.
	for n: int in _dungeon.get_neighbours(_dungeon.current_index):
		if not _dungeon.room_lineup(n).is_empty() and not _dungeon.rooms[n].is_boss:
			await _enter(n)
			break
	pause = _dungeon.get_node(^"PauseMenu") as PauseMenu
	_check(_dungeon.current_room.state != Room.State.COMBAT or pause.save_note_text().contains("start of this fight"),
			"pause menu: during a fight it says the fight restarts")


## A valid save whose level plan no longer matches (e.g. the game changed level
## generation) or whose entry door does not exist is not restored: a fresh run starts.
func _test_layout_mismatch() -> void:
	var saved := RunSave.read()
	_check(saved["status"] == RunSave.Status.VALID and int(saved["data"]["dungeon"]["layout"]) == _dungeon.layout_fingerprint(),
			"the save stores the level plan fingerprint")
	for change in ["layout", "door"]:
		var data: Dictionary = saved["data"].duplicate(true)
		if change == "layout":
			data["dungeon"]["layout"] = int(data["dungeon"]["layout"]) + 1
		else:
			data["dungeon"]["entry_door"] = "DoorNowhere"
		await _resume(data)
		var refused := current_scene
		var start := Time.get_ticks_msec()
		while (current_scene == refused or current_scene == null or not current_scene.is_node_ready()) \
				and Time.get_ticks_msec() - start < 5000:
			await process_frame
		await _frames(2)
		_dungeon = current_scene as Dungeon
		_check(_dungeon != null and not _dungeon.resumed and _dungeon.run_state.dungeon_level == 1
				and RunSave.read()["status"] == RunSave.Status.VALID,
				"a mismatched save (%s) starts a fresh run instead of a broken restore" % change)


func _test_death_and_new_run() -> void:
	_dungeon.mage.take_damage(1.0e9)
	await _frames(2)
	_check(_dungeon.mage.is_dead() and not RunSave.exists(), "death deletes the save")
	_check(not _dungeon.save_run(), "a dead run is never saved again")
	# A new run (no Continue) never restores anything; it writes its own save.
	RunState.seed_override = SEED + 1
	paused = false
	await _load_dungeon()
	var fresh := RunSave.read()
	_check(not _dungeon.resumed and _dungeon.run_state.dungeon_level == 1 and _dungeon.run_state.collected.is_empty()
			and _dungeon.run_state.run_seed == SEED + 1, "a new run starts fresh")
	_check(fresh["status"] == RunSave.Status.VALID and int(fresh["data"]["run"]["run_seed"]) == SEED + 1,
			"the new run's save replaces the old one")
	# Leaving a fresh run and starting another new one (not Continue) ignores the save too.
	var first_id := int(fresh["data"]["dungeon"]["run_id"])
	await _load_dungeon()
	_check(not _dungeon.resumed and int(RunSave.read()["data"]["dungeon"]["run_id"]) != first_id,
			"New Run with an existing save does not restore it")
	RunState.seed_override = SEED


func _test_file_handling() -> void:
	var good := RunSave.read()
	_check(good["status"] == RunSave.Status.VALID, "current save is valid before the damage tests")
	var text := FileAccess.get_file_as_string(SAVE_FILE)
	# Damaged: not JSON at all.
	_write(SAVE_FILE, "{ this is not json")
	_check(RunSave.read()["status"] == RunSave.Status.INVALID, "a damaged file is reported as invalid")
	# Truncated (a partial write).
	_write(SAVE_FILE, text.substr(0, text.length() / 2))
	_check(RunSave.read()["status"] == RunSave.Status.INVALID, "a truncated file is reported as invalid")
	# Edited data without a matching checksum.
	var envelope: Dictionary = JSON.parse_string(text)
	var tampered := envelope.duplicate()
	tampered["data"] = (envelope["data"] as String).replace("\"currency\":", "\"currency\":9")
	_write(SAVE_FILE, JSON.stringify(tampered))
	_check(RunSave.read()["status"] == RunSave.Status.INVALID, "edited data fails the checksum")
	# Newer save format / another game version.
	var newer := envelope.duplicate()
	newer["version"] = RunSave.VERSION + 1
	_write(SAVE_FILE, JSON.stringify(newer))
	_check(RunSave.read()["status"] == RunSave.Status.OUTDATED, "a newer save format is refused as outdated")
	var other := envelope.duplicate()
	other["game_version"] = "0.0.0-old"
	_write(SAVE_FILE, JSON.stringify(other))
	_check(RunSave.read()["status"] == RunSave.Status.OUTDATED, "a save from another game version is outdated")
	# Valid checksum but impossible content (unknown item id).
	var data: Dictionary = JSON.parse_string(envelope["data"])
	data["run"]["collected"]["no_such_item"] = 1
	var body := JSON.stringify(data)
	var bad := envelope.duplicate()
	bad["data"] = body
	bad["checksum"] = body.md5_text()
	_write(SAVE_FILE, JSON.stringify(bad))
	_check(RunSave.read()["status"] == RunSave.Status.INVALID, "unknown ids are rejected even with a valid checksum")
	# Valid checksum but an absurd (edited) Mage level.
	var huge: Dictionary = JSON.parse_string(envelope["data"])
	huge["run"]["level"] = 1000000000
	var huge_body := JSON.stringify(huge)
	var huge_env := envelope.duplicate()
	huge_env["data"] = huge_body
	huge_env["checksum"] = huge_body.md5_text()
	_write(SAVE_FILE, JSON.stringify(huge_env))
	_check(RunSave.read()["status"] == RunSave.Status.INVALID, "absurd values are rejected (no endless level-up loop)")
	# Writing invalid data never replaces a valid save.
	_write(SAVE_FILE, text)
	var broken: Dictionary = JSON.parse_string(envelope["data"])
	broken["mage"]["health"] = -5
	_check(RunSave.write(broken) != OK and FileAccess.get_file_as_string(SAVE_FILE) == text
			and RunSave.read()["status"] == RunSave.Status.VALID, "invalid data is refused and the valid save is kept")
	_check(RunSave.write({}) != OK and RunSave.read()["status"] == RunSave.Status.VALID, "partial data is refused")
	RunSave.delete()
	_check(RunSave.read()["status"] == RunSave.Status.NONE and not FileAccess.file_exists(SAVE_FILE + ".tmp"),
			"a missing file means no unfinished run")


# --- helpers ---

func _load_dungeon() -> void:
	var scene_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(DUNGEON_SCENE)
	await _wait_for_scene(scene_id)
	_dungeon = current_scene as Dungeon


## "Quit and Continue": a new Dungeon restores `data` through the Progression autoload.
func _resume(data: Dictionary) -> void:
	paused = false
	_prog.prepare_resume(data)
	await _load_dungeon()


func _enter(index: int) -> void:
	var door := _dungeon.entry_door(index)
	_dungeon.enter_room(index, door)
	await _frames(3)


func _kill_all() -> void:
	for pass_i in 4:
		for enemy in _dungeon.current_room.get_node(^"Enemies").get_children():
			if enemy is Enemy and not (enemy as Enemy).health.is_dead():
				(enemy as Enemy).take_damage(1.0e9)
		await _frames(4)


## The victory screen opens after Dungeon.victory_delay seconds (real time).
func _wait_for_overlay() -> void:
	var start := Time.get_ticks_msec()
	while not (_dungeon.get_node(^"VictoryOverlay") as VictoryOverlay).is_open and Time.get_ticks_msec() - start < 5000:
		await process_frame


func _alive_enemies(room: Room) -> int:
	var count := 0
	for enemy in room.get_node(^"Enemies").get_children():
		if enemy is Enemy and not (enemy as Enemy).health.is_dead() and not enemy.is_queued_for_deletion():
			count += 1
	return count


func _first_pickup(room: Room) -> ItemPickup:
	for node in room.get_node(^"Decor").get_children():
		if node is ItemPickup and not node.is_queued_for_deletion() and (node as ItemPickup).is_active():
			return node
	return null


func _snapshot() -> Dictionary:
	var run := _dungeon.run_state
	return {"hp": snappedf(_dungeon.mage.health.current, 0.01), "max_hp": snappedf(_dungeon.mage.health.max_health, 0.01),
			"xp": run.xp, "level": run.level, "gold": run.currency, "items": run.collected.duplicate(),
			"seals": run.seals_collected(), "dungeon_level": run.dungeon_level, "enemies": run.enemies_defeated,
			"damage": snappedf(run.spell_damage_multiplier(), 0.0001)}


func _visited() -> Array:
	var out: Array = []
	for i in _dungeon.rooms.size():
		if _dungeon.is_visited(i):
			out.append([i, _dungeon.is_cleared(i)])
	return out


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1


func _wait_for_scene(old_id: int) -> void:
	for i in 600:
		if current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready():
			break
		await process_frame
	await _frames(2)
