extends SceneTree
## Headless check of Issue #58 Stage 1 (scenes/dungeon/dungeon.tscn): the 250
## starting gold and its affordability, seeded 1-4 loot chests per RUN spread
## over several dungeon levels (run total, count bounds, safe placement,
## determinism, locked until cleared, gold paid exactly once) and the ESC pause
## menu (pauses the tree, no duplicates, ignored while another overlay owns the
## screen, an open Anvil menu closes first, Restart / Main Menu while paused).
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_mvp_finalization.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

## Run seeds: 120 plans 4 chests on levels [1, 2, 3, 3], 101 plans 1 (level 1),
## 104 plans 3 on [1, 2, 3] (both run-total bounds, spread over levels).
const SEEDS := [120, 101, 104]
## Levels walked per seed: the chest span plus two levels that must stay empty.
const LEVELS_CHECKED := EncounterPlanner.LOOT_CHEST_LEVEL_SPAN + 2
const SCENE := "res://scenes/dungeon/dungeon.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_test_economy()
	_test_chest_planner()
	_test_chest_sprite()
	RunState.seed_override = SEEDS[0]
	change_scene_to_file(SCENE)
	await _wait_for_scene(0)
	if _dungeon == null:
		_check(false, "dungeon scene loaded")
	else:
		_check(_run.currency == RunState.STARTING_GOLD and _run.gold_earned == 0,
				"a new run starts with %d gold, none of it counted as earned" % _run.currency)
		for s: int in SEEDS:
			if s != SEEDS[0]:
				RunState.seed_override = s
				await _restart_via_pause()
			await _test_run_chests(s)
		RunState.seed_override = SEEDS[0]
		await _restart_via_pause()
		await _test_chest_open()
		await _test_escape_closes_anvil()
		await _test_pause_menu()
		await _test_pause_restart()
		await _test_pause_main_menu()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	RunState.seed_override = 0
	quit(1 if _failures > 0 else 0)


func _test_economy() -> void:
	var run := RunState.new()
	_check(RunState.STARTING_GOLD == 250 and run.currency == 250, "RunState starts with 250 gold")
	var affordable := RunState.CONSUMABLES.keys().filter(func(id: StringName) -> bool: return run.can_buy_consumable(id))
	_check(affordable.has(&"health_potion") and run.upgrade_cost(&"vitality") <= run.currency,
			"250 gold buys a consumable or Vitality (affordable: %s)" % [affordable])
	_check(run.buy_consumable(&"health_potion") and run.currency == 250 - 120, "buying a Health Potion leaves 130 gold")
	run.reset()
	_check(run.currency == 250 and run.gold_earned == 0, "reset() restores the starting gold")
	# Loot chest payout: once per id per level, again on the next level.
	var gold := run.open_loot_chest(&"a")
	_check(gold == RunState.LOOT_CHEST_GOLD and run.currency == 250 + gold and run.gold_earned == gold,
			"a loot chest pays %d gold (Normal) and counts as earned" % gold)
	_check(run.open_loot_chest(&"a") == -1 and run.currency == 250 + gold, "the same chest pays nothing twice")
	_check(run.open_loot_chest(&"") == -1, "an empty chest id is refused")
	run.dungeon_level = 3
	_check(run.loot_chest_gold() == RunState.LOOT_CHEST_GOLD + 2 * RunState.LOOT_CHEST_GOLD_PER_LEVEL, "chest gold grows per dungeon level")
	run.free()


func _test_chest_planner() -> void:
	var counts := {}
	for s in 400:
		var c := EncounterPlanner.loot_chest_count(s)
		counts[c] = counts.get(c, 0) + 1
	_check(counts.keys().all(func(c: int) -> bool: return c >= 1 and c <= 4) and counts.has(1) and counts.has(4),
			"loot chest count stays in 1..4 and reaches both bounds (%s)" % [counts])
	var levels_ok := true
	for s in 400:
		for start in [1, 4]:
			var levels := EncounterPlanner.loot_chest_levels(s, start)
			var total := 0
			for d in range(start, start + 10):
				total += EncounterPlanner.loot_chests_on_level(s, start, d)
			levels_ok = levels_ok and levels.size() == EncounterPlanner.loot_chest_count(s) and total == levels.size() \
					and levels[0] == start and levels.all(func(d: int) -> bool:
						return d >= start and d < start + EncounterPlanner.LOOT_CHEST_LEVEL_SPAN) \
					and levels == EncounterPlanner.loot_chest_levels(s, start)
	_check(levels_ok, "run plan: per-level shares sum to the run total (1..4), first chest on the start level, all within the span, deterministic")
	var candidates: Array[int] = [2, 5, 7, 9, 11, 14]
	var a := EncounterPlanner.pick_chest_rooms(candidates, 4, 99)
	_check(a == EncounterPlanner.pick_chest_rooms(candidates, 4, 99) and a.size() == 4
			and a.all(func(i: int) -> bool: return candidates.has(i)), "chest rooms are deterministic, distinct candidates (%s)" % [a])
	var few: Array[int] = [3, 8]
	_check(EncounterPlanner.pick_chest_rooms(few, 4, 1).size() == 2 and EncounterPlanner.pick_chest_rooms([] as Array[int], 3, 1).is_empty(),
			"never more chests than candidate rooms")


func _test_chest_sprite() -> void:
	var sprite := ChestSprite.new()
	var atlas := sprite.texture as AtlasTexture
	_check(atlas != null and atlas.atlas != null and atlas.region == Rect2(1, 1, 22, 22) and sprite.material is ShaderMaterial,
			"ChestSprite cuts a sheet cell and keys its background")
	sprite.opened = true
	_check(sprite.modulate == ChestSprite.OPENED_TINT, "an opened chest sprite is dimmed")
	sprite.free()


## Walks LEVELS_CHECKED dungeon levels of one run and counts the chests actually
## placed: the run total is 1-4 and matches the run plan.
func _test_run_chests(seed_value: int) -> void:
	var planned := EncounterPlanner.loot_chest_count(seed_value)
	var per_level: Array[int] = []
	for k in LEVELS_CHECKED:
		if k > 0:
			await _next_level()
		per_level.append(_test_chest_layout(seed_value))
	var total := 0
	for n in per_level:
		total += n
	_check(total == planned and total >= 1 and total <= EncounterPlanner.MAX_LOOT_CHESTS and per_level[0] >= 1,
			"seed %d: %d chest(s) placed in the whole run, as planned (%d), per level %s" % [seed_value, total, planned, per_level])
	if seed_value == 120:
		_check(total == 4 and per_level.slice(0, 3).all(func(n: int) -> bool: return n >= 1),
				"seed 120: upper bound, chests on three different levels")
	elif seed_value == 101:
		_check(total == 1 and per_level[0] == 1, "seed 101: lower bound, one chest on level 1")
	_check(per_level.slice(EncounterPlanner.LOOT_CHEST_LEVEL_SPAN).all(func(n: int) -> bool: return n == 0),
			"seed %d: no new chests after the first %d levels" % [seed_value, EncounterPlanner.LOOT_CHEST_LEVEL_SPAN])


## Checks the current level's chest rooms; returns how many chests were placed.
func _test_chest_layout(seed_value: int) -> int:
	var chest_rooms := _dungeon.loot_chest_rooms()
	var level := _run.dungeon_level
	var share := EncounterPlanner.loot_chests_on_level(seed_value, _run.start_level, level)
	var expected := EncounterPlanner.pick_chest_rooms(_dungeon._loot_chest_candidates(), share, _run.level_seed())
	_check(chest_rooms == expected and chest_rooms.size() <= share,
			"seed %d L%d: %d chest room(s) = the level's share of the run plan" % [seed_value, level, chest_rooms.size()])
	var placed := 0
	for i in chest_rooms:
		var spec := _dungeon.rooms[i]
		_check(i != _dungeon.start_room and not spec.is_boss and not spec.is_treasure() and not spec.enemies.is_empty()
				and not _dungeon.miniboss_room_indexes().has(i) and spec.cell != _dungeon.final_anvil_cell,
				"seed %d: room %d is a valid chest room" % [seed_value, i])
		var room := _dungeon._get_room(i)
		var chests := room.find_children("*", "LootChest", true, false)
		_check(chests.size() == 1, "seed %d: room %d holds exactly one loot chest" % [seed_value, i])
		if chests.size() != 1:
			continue
		placed += 1
		var chest := chests[0] as LootChest
		_check(chest.run_state == _run and chest.chest_id == _dungeon.loot_chest_id(i), "seed %d: chest %d bound to the run" % [seed_value, i])
		_check_placement(room, chest, seed_value, i)
	return placed


## Ends the current level the way a boss kill + relic choice does and starts the next one.
func _next_level() -> void:
	var level := _run.dungeon_level
	_run.boss_defeated = true
	_run.choose_relic(&"wind_relic")
	_dungeon.victory = true
	_check(_dungeon.advance_level() and _run.dungeon_level == level + 1, "advanced to level %d" % (level + 1))
	await _frames(2)


## The chest stands inside the floor (wall margin), clear of doors, obstacles,
## spawn points, enemies and other interactables.
func _check_placement(room: Room, chest: LootChest, seed_value: int, i: int) -> void:
	var p := chest.position
	var floor_ok := (room.get_node(^"Visuals") as RoomVisuals).floor_rect.grow(-_dungeon.seal_wall_margin + 0.1).has_point(p)
	var doors_ok := room.get_node(^"Doors").get_children().all(func(d: Node2D) -> bool:
		return p.distance_to(d.position) >= _dungeon.seal_door_clearance)
	var clear := true
	for node in room.find_children("*", "", true, false):
		if node == chest or node.get_parent() == chest:
			continue
		if node is Obstacle:
			var o := node as Obstacle
			var pos := _dungeon._room_position(room, o)
			if Rect2(pos - o.footprint / 2.0, o.footprint).grow(_dungeon.seal_obstacle_margin).has_point(p):
				clear = false
		elif node is Enemy or node is Interactable or node is ItemPickup or node is AncientSeal \
				or node is Marker2D and node.get_parent().name == &"SpawnPoints":
			if _dungeon._room_position(room, node as Node2D).distance_to(p) < _dungeon.seal_clearance:
				clear = false
	_check(floor_ok and doors_ok and clear, "seed %d: chest in room %d at a safe spot %s" % [seed_value, i, p])


func _test_chest_open() -> void:
	var i := _dungeon.loot_chest_rooms()[0]
	_dungeon.enter_room(i)
	await _frames(2)
	var room := _dungeon.current_room
	var chest := room.find_children("*", "LootChest", true, false)[0] as LootChest
	var gold := _run.currency
	_check(not chest.is_unlocked() and not chest.interact() and _run.currency == gold, "a loot chest is locked until its room is cleared")
	room.start_encounter()
	for enemy in room.get_node(^"Enemies").get_children():
		if enemy is Enemy:
			(enemy as Enemy).take_damage(999999.0)
	await _wait_until(func() -> bool: return room.state == Room.State.CLEARED, 600)
	gold = _run.currency
	var paid := [-1]
	chest.opened.connect(func(g: int) -> void: paid[0] = g)
	_check(chest.is_unlocked() and chest.interact() and paid[0] > 0 and _run.currency == gold + paid[0],
			"opening the cleared room's chest pays %d gold" % paid[0])
	_check(not chest.interact() and _run.currency == gold + paid[0] and chest.prompt_text() == "Empty chest",
			"a second open pays nothing")
	_check(_run.open_loot_chest(chest.chest_id) == -1, "RunState refuses the same chest id again this level")


## The first ESC closes an open Anvil menu, the next one pauses.
func _test_escape_closes_anvil() -> void:
	_dungeon.enter_room(_dungeon.start_room)
	await _frames(2)
	var station := _dungeon.current_room.get_node_or_null(^"Decor/UpgradeStation") as UpgradeStation
	var menu := current_scene.get_node(^"PauseMenu") as PauseMenu
	_check(station != null, "the start room has an anvil")
	if station == null:
		return
	_mage.global_position = station.global_position + Vector2(50, 0)
	await _frames(3)
	station.set_open(true)
	_check(station.is_open, "anvil menu open")
	_press_escape()
	await process_frame
	_check(not station.is_open and not menu.is_open() and not paused, "first ESC closes the anvil menu, no pause")
	_press_escape()
	await process_frame
	_check(menu.is_open() and paused and not station.is_open, "second ESC opens the pause menu")
	_press_escape()
	await process_frame
	_check(not menu.is_open() and not paused and not station.is_open, "third ESC resumes; the anvil stays closed")


func _test_pause_menu() -> void:
	var menu := current_scene.get_node(^"PauseMenu") as PauseMenu
	_check(menu != null and not menu.visible and not paused, "pause menu hidden at start")
	_press_escape()
	await process_frame
	_check(menu.is_open() and menu.visible and paused, "ESC opens the menu and pauses the tree")
	_check(not menu.open() and current_scene.find_children("*", "PauseMenu", true, false).size() == 1,
			"opening again does nothing (one menu)")
	_press_escape()
	await process_frame
	_check(not menu.is_open() and not menu.visible and not paused, "ESC again resumes")
	for k in 5:
		_press_escape()
		await process_frame
	_check(menu.is_open() and paused, "repeated ESC toggles cleanly (odd count = open)")
	menu.resume()
	menu.resume()
	_check(not paused and not menu.visible, "Resume unpauses; a second resume is harmless")
	paused = true
	_check(not menu.open() and not menu.visible, "ignored while another overlay paused the game")
	paused = false
	_dungeon.victory = true
	_check(not menu.can_open(), "ignored once victory started")
	_dungeon.victory = false


func _test_pause_restart() -> void:
	_run.currency = 9999
	var menu := current_scene.get_node(^"PauseMenu") as PauseMenu
	_check(menu.open(), "menu opens before Restart")
	var old_id := current_scene.get_instance_id()
	menu.restart()
	await _wait_for_scene(old_id)
	var new_menu := current_scene.get_node_or_null(^"PauseMenu") as PauseMenu
	_check(_dungeon != null and not paused and _run.currency == RunState.STARTING_GOLD and _dungeon.current_index == _dungeon.start_room
			and new_menu != null and not new_menu.visible, "Restart while paused: fresh unpaused run, menu closed")
	# Restart from the Game Over screen still works and the dead Mage blocks pausing.
	_mage.take_damage(999999.0)
	await _frames(1)
	_check(not (current_scene.get_node(^"PauseMenu") as PauseMenu).can_open(), "ESC is ignored on the Game Over screen")


func _test_pause_main_menu() -> void:
	var old_id := current_scene.get_instance_id()
	(current_scene.get_node(^"GameOverOverlay") as GameOverOverlay).restart()
	await _wait_for_scene(old_id)
	var menu := current_scene.get_node(^"PauseMenu") as PauseMenu
	_check(menu.open(), "menu opens before Main Menu")
	old_id = current_scene.get_instance_id()
	menu.main_menu()
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_check(current_scene != null and current_scene.scene_file_path == MENU_SCENE and not paused
			and current_scene.find_children("*", "Dungeon", true, false).is_empty(),
			"Main Menu while paused: menu scene, unpaused, no dungeon left")


func _restart_via_pause() -> void:
	var old_id := current_scene.get_instance_id()
	var menu := current_scene.get_node(^"PauseMenu") as PauseMenu
	menu.open()
	menu.restart()
	await _wait_for_scene(old_id)


func _press_escape() -> void:
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	var up := InputEventAction.new()
	up.action = &"ui_cancel"
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()


## Scene changes are deferred; waits until a new, ready scene (not `old_id`) is current, then binds.
func _wait_for_scene(old_id: int) -> void:
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_dungeon = current_scene as Dungeon
	if _dungeon:
		_mage = _dungeon.mage
		_run = _dungeon.run_state


func _wait_until(condition: Callable, max_frames: int = 240) -> void:
	for i in max_frames:
		if condition.call():
			return
		await physics_frame
	await process_frame


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
