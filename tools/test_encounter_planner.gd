extends SceneTree
## Headless check of the seeded encounter variation (Issue #43, stage 1):
## seed derivation, determinism, equal-XP swap groups, per-room and pre-boss
## XP budgets over many seeds, unchanged enemy counts / boss / treasure rooms,
## real variation between seeds, and the Dungeon building rooms from the plan
## (same seed -> same encounters, revisits keep them, next level re-plans).
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_encounter_planner.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENE := "res://scenes/dungeon/dungeon.tscn"
const SEEDS := 300
const SEED := 424242

var _failures := 0
var _rooms: Array[RoomSpec] = []
var _dungeon: Dungeon


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	var template := (load(SCENE) as PackedScene).instantiate() as Dungeon
	_rooms = template.rooms.duplicate()
	template.free()
	_test_seeds()
	_test_swap_groups()
	_test_plans_over_seeds()
	_test_treasure_variation()
	await _test_dungeon_integration()
	await _test_treasure_rooms_in_dungeon()
	RunState.seed_override = 0
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_seeds() -> void:
	_check(EncounterPlanner.level_seed(7, 1) == EncounterPlanner.level_seed(7, 1), "level seed is deterministic")
	_check(EncounterPlanner.level_seed(7, 1) != EncounterPlanner.level_seed(7, 2), "level seed differs per dungeon level")
	_check(EncounterPlanner.level_seed(7, 1) != EncounterPlanner.level_seed(8, 1), "level seed differs per run seed")
	var run := RunState.new()
	run.run_seed = 99
	run.dungeon_level = 3
	_check(run.level_seed() == EncounterPlanner.level_seed(99, 3), "RunState.level_seed() uses the run seed and dungeon level")
	run.free()


func _test_swap_groups() -> void:
	var seen := {}
	var ok := true
	for group: Array in EncounterPlanner.SWAP_GROUPS:
		var xp := -1
		for path in group:
			var scene := load(path) as PackedScene
			ok = ok and scene != null and not seen.has(path)
			seen[path] = true
			if scene == null:
				continue
			var value := EncounterPlanner.scene_xp(scene)
			ok = ok and (xp < 0 or value == xp) and value > 0
			xp = value
	_check(ok and not EncounterPlanner.SWAP_GROUPS.is_empty(), "swap groups: existing enemy scenes, equal XP within a group, no scene in two groups")


func _test_plans_over_seeds() -> void:
	# PRE_BOSS_BASE_XP = enemies placed in the room scenes + RoomSpec.enemies (as test_level_budget counts it).
	var placed_xp := 0
	var authored_xp := 0
	for spec in _rooms:
		if spec.is_boss or spec.is_treasure():
			continue
		var inst := spec.scene.instantiate()
		for enemy in inst.get_node(^"Enemies").get_children():
			placed_xp += (enemy as Enemy).xp_reward
		inst.free()
		authored_xp += EncounterPlanner.lineup_xp(spec.enemies)
	_check(placed_xp + authored_xp == MageLevels.PRE_BOSS_BASE_XP,
			"authored pre-boss XP is PRE_BOSS_BASE_XP (%d placed + %d planned)" % [placed_xp, authored_xp])

	var deterministic := true
	var room_xp_ok := true
	var total_xp_ok := true
	var counts_ok := true
	var fixed_ok := true
	var fixed_types_ok := true
	var swaps_ok := true
	var distinct := {}
	var swapped_any := false
	var reordered_any := false
	for s in SEEDS:
		var seed_value := EncounterPlanner.level_seed(s + 1, 1 + s % 4)
		var plan := EncounterPlanner.plan(_rooms, seed_value)
		var again := EncounterPlanner.plan(_rooms, seed_value)
		deterministic = deterministic and _signature(plan) == _signature(again)
		distinct[_signature(plan)] = true
		var total := 0
		for i in _rooms.size():
			var spec := _rooms[i]
			if spec.enemies.is_empty():
				counts_ok = counts_ok and not plan.has(i)
				continue
			var lineup: Array[PackedScene] = []
			lineup.assign(plan[i])
			counts_ok = counts_ok and lineup.size() == spec.enemies.size()
			room_xp_ok = room_xp_ok and EncounterPlanner.lineup_xp(lineup) == EncounterPlanner.lineup_xp(spec.enemies)
			if spec.is_boss or spec.is_treasure():
				fixed_ok = fixed_ok and _paths(lineup) == _paths(spec.enemies)
				continue
			total += EncounterPlanner.lineup_xp(lineup)
			# Scenes outside every swap group keep their counts; swapped slots stay within the limit.
			fixed_types_ok = fixed_types_ok and _unswappable_counts(lineup) == _unswappable_counts(spec.enemies)
			var changed := _changed_count(spec.enemies, lineup)
			swaps_ok = swaps_ok and changed <= EncounterPlanner.MAX_SWAPS_PER_ROOM
			swapped_any = swapped_any or changed > 0
			reordered_any = reordered_any or (changed == 0 and _paths(lineup) != _paths(spec.enemies))
		total_xp_ok = total_xp_ok and placed_xp + total == MageLevels.PRE_BOSS_BASE_XP
	_check(deterministic, "same seed -> identical plan (%d seeds)" % SEEDS)
	_check(room_xp_ok, "every planned room keeps its authored XP")
	_check(total_xp_ok, "planned pre-boss XP is exactly PRE_BOSS_BASE_XP for every seed")
	_check(counts_ok, "enemy count per room unchanged; rooms without enemies stay empty")
	_check(fixed_ok, "boss and treasure rooms keep their authored line-ups")
	_check(fixed_types_ok, "enemies outside the swap groups are never added or removed")
	_check(swaps_ok, "at most %d enemies swapped per room" % EncounterPlanner.MAX_SWAPS_PER_ROOM)
	_check(swapped_any and reordered_any and distinct.size() > SEEDS / 2,
			"seeds produce real variation (%d distinct plans of %d)" % [distinct.size(), SEEDS])


## Rune order and survival waves (unit level, many seeds).
func _test_treasure_variation() -> void:
	var base := PackedStringArray(["moon", "sun", "star"])
	var orders := {}
	var perm_ok := true
	var same_ok := true
	for s in SEEDS:
		var order := EncounterPlanner.rune_order(base, s + 1)
		var sorted := Array(order)
		sorted.sort()
		perm_ok = perm_ok and sorted == ["moon", "star", "sun"]
		same_ok = same_ok and order == EncounterPlanner.rune_order(base, s + 1)
		orders[",".join(order)] = true
	_check(perm_ok and same_ok, "rune order: always the same three runes; same seed -> same order")
	_check(orders.size() == 6, "rune order: all 6 orders occur across seeds (%d)" % orders.size())

	var survival := (load("res://scenes/rooms/survival_room.tscn") as PackedScene).instantiate() as SurvivalRoom
	var authored: Array[PackedScene] = survival.wave_enemies.duplicate()
	var sizes := survival.wave_sizes
	survival.free()
	var waves_ok := true
	var same_waves := true
	var distinct := {}
	for s in SEEDS:
		var waves := EncounterPlanner.vary_waves(authored, sizes, s + 1)
		same_waves = same_waves and _paths(waves) == _paths(EncounterPlanner.vary_waves(authored, sizes, s + 1))
		waves_ok = waves_ok and waves.size() == authored.size()
		var start := 0
		for w in sizes.size():
			var planned: Array[PackedScene] = []
			planned.assign(waves.slice(start, start + sizes[w]))
			var original: Array[PackedScene] = []
			original.assign(authored.slice(start, start + sizes[w]))
			waves_ok = waves_ok and EncounterPlanner.lineup_xp(planned) == EncounterPlanner.lineup_xp(original) and _unswappable_counts(planned) == _unswappable_counts(original)
			start += sizes[w]
		distinct[",".join(_paths(waves))] = true
	_check(waves_ok, "survival waves: every wave keeps its size, XP and non-swappable enemies (%d seeds)" % SEEDS)
	_check(same_waves and distinct.size() > SEEDS / 2, "survival waves: deterministic per seed and varied (%d distinct)" % distinct.size())


## The Dungeon builds the treasure rooms from the level seed.
func _test_treasure_rooms_in_dungeon() -> void:
	RunState.seed_override = SEED
	await _load_dungeon()
	var puzzle_i := -1
	var survival_i := -1
	for i in _dungeon.rooms.size():
		match _dungeon.rooms[i].treasure:
			RoomSpec.Treasure.PUZZLE:
				puzzle_i = i
			RoomSpec.Treasure.SURVIVAL:
				survival_i = i
	var level_seed := _dungeon.run_state.level_seed()
	_dungeon.enter_room(puzzle_i)
	await _frames(1)
	var puzzle := _dungeon.current_room as RunePuzzleRoom
	var expected_order := EncounterPlanner.rune_order(PackedStringArray(["moon", "sun", "star"]), hash([level_seed, puzzle_i]))
	_check(puzzle.sequence == expected_order and (puzzle.get_node(^"Decor/Plaque") as Label).text == puzzle.hint_text(expected_order),
			"rune room uses the seeded order %s and its plaque matches" % expected_order)
	_dungeon.enter_room(survival_i)
	await _frames(1)
	var trial := _dungeon.current_room as SurvivalRoom
	var fresh := (load("res://scenes/rooms/survival_room.tscn") as PackedScene).instantiate() as SurvivalRoom
	var expected_waves := EncounterPlanner.vary_waves(fresh.wave_enemies, fresh.wave_sizes, hash([level_seed, survival_i]))
	fresh.free()
	_check(_paths(trial.wave_enemies) == _paths(expected_waves), "survival room uses the seeded waves")
	var first_order := puzzle.sequence
	var first_waves := _paths(trial.wave_enemies)
	await _load_dungeon()
	_dungeon.enter_room(puzzle_i)
	await _frames(1)
	var again := (_dungeon.current_room as RunePuzzleRoom).sequence
	_dungeon.enter_room(survival_i)
	await _frames(1)
	_check(again == first_order and _paths((_dungeon.current_room as SurvivalRoom).wave_enemies) == first_waves,
			"same seed after a restart -> same rune order and waves")
	# Different run seeds give different treasure rooms.
	var orders := {}
	for s in 40:
		var seed_value := EncounterPlanner.level_seed(s + 1, 1)
		orders[",".join(EncounterPlanner.rune_order(PackedStringArray(["moon", "sun", "star"]), hash([seed_value, puzzle_i])))] = true
	_check(orders.size() >= 4, "different run seeds give different rune orders (%d of 6 in 40 runs)" % orders.size())
	RunState.seed_override = 0


func _test_dungeon_integration() -> void:
	RunState.seed_override = SEED
	await _load_dungeon()
	if _dungeon == null:
		_check(false, "dungeon scene loaded")
		return
	var run := _dungeon.run_state
	_check(run.run_seed == SEED and _dungeon.run_summary()["seed"] == SEED, "seed override is used and reported in the run summary")
	var index := _combat_room()
	var expected := _paths(_dungeon.room_lineup(index))
	var planned := EncounterPlanner.plan(_dungeon.rooms, EncounterPlanner.level_seed(SEED, run.dungeon_level))
	_check(expected == _paths(planned[index]), "Dungeon line-up matches EncounterPlanner for the level seed")
	_dungeon.enter_room(index)
	await _frames(1)
	var spawned := _enemy_paths(_dungeon.current_room)
	_check(spawned.slice(0, expected.size()) == expected, "room enemies spawn in the planned order at the authored markers")
	_dungeon.enter_room(_dungeon.start_room)
	await _frames(1)
	_dungeon.enter_room(index)
	await _frames(1)
	_check(_enemy_paths(_dungeon.current_room) == spawned, "revisiting keeps the same (cached) encounter")

	# Restart with the same seed reproduces the encounters.
	await _load_dungeon()
	_dungeon.enter_room(index)
	await _frames(1)
	_check(_enemy_paths(_dungeon.current_room) == spawned, "same seed after a restart -> same encounter")

	# The next dungeon level is planned from its own level seed.
	_dungeon.run_state.dungeon_level += 1
	_dungeon._plan_level()
	var next := EncounterPlanner.plan(_dungeon.rooms, EncounterPlanner.level_seed(SEED, _dungeon.run_state.dungeon_level))
	_check(_signature(next) == _signature(_lineups_of(_dungeon)), "a new dungeon level re-plans from its level seed")

	# Without an override every run gets a fresh non-zero seed.
	RunState.seed_override = 0
	await _load_dungeon()
	var first := _dungeon.run_state.run_seed
	await _load_dungeon()
	_check(first != 0 and _dungeon.run_state.run_seed != 0 and first != _dungeon.run_state.run_seed, "runs without an override get different seeds")


func _load_dungeon() -> void:
	var old_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(SCENE)
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_dungeon = current_scene as Dungeon


## First combat room with a swappable enemy (miniboss rooms replace their line-up, see test_minibosses.gd).
func _combat_room() -> int:
	for i in _dungeon.rooms.size():
		var spec := _dungeon.rooms[i]
		if spec.is_boss or spec.is_treasure() or spec.enemies.is_empty() or _dungeon.miniboss_scene(i) != null:
			continue
		if spec.enemies.any(func(s: PackedScene) -> bool: return EncounterPlanner.swap_group(s).size() > 1):
			return i
	return -1


func _lineups_of(dungeon: Dungeon) -> Dictionary:
	var result := {}
	for i in dungeon.rooms.size():
		if not dungeon.rooms[i].enemies.is_empty():
			result[i] = dungeon.room_lineup(i)
	return result


func _signature(plan: Dictionary) -> String:
	var keys := plan.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%d:%s" % [k, ",".join(_paths(plan[k]))])
	return "|".join(parts)


func _paths(lineup: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for scene: PackedScene in lineup:
		result.append(scene.resource_path)
	return result


func _enemy_paths(room: Room) -> PackedStringArray:
	var result := PackedStringArray()
	for child in room.get_node(^"Enemies").get_children():
		if child is Enemy and not child.is_queued_for_deletion():
			result.append(child.scene_file_path)
	return result


## Path -> count for scenes outside every swap group.
func _unswappable_counts(lineup: Array) -> Dictionary:
	var counts := {}
	for scene: PackedScene in lineup:
		if EncounterPlanner.swap_group(scene).is_empty():
			counts[scene.resource_path] = counts.get(scene.resource_path, 0) + 1
	return counts


## How many enemies of `lineup` differ from `authored` as multisets.
func _changed_count(authored: Array, lineup: Array) -> int:
	var remaining := {}
	for scene: PackedScene in authored:
		remaining[scene.resource_path] = remaining.get(scene.resource_path, 0) + 1
	var changed := 0
	for scene: PackedScene in lineup:
		if remaining.get(scene.resource_path, 0) > 0:
			remaining[scene.resource_path] -= 1
		else:
			changed += 1
	return changed


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
