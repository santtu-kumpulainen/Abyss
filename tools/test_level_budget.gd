extends SceneTree
## Headless check of the per-dungeon-level Mage budget: level cap and room /
## boss gates (MageLevels), the XP budget of the real dungeon, extra enemy
## counts and spawn-point safety, item / treasure stacking and per-level
## refresh, the display-only survival timer and practice-run start levels.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_level_budget.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SEED := 4242
const SCENE := "res://scenes/dungeon/dungeon.tscn"
const NORMAL := Difficulty.Tier.NORMAL
const HARD := Difficulty.Tier.HARD
const ABYSSAL := Difficulty.Tier.ABYSSAL
const XP_PER_LEVEL := 50

var _failures := 0
var _prog: ProgressionStore
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	RunState.seed_override = SEED
	_prog = ProgressionStore.instance(self)
	_prog.clear_progress()
	_test_formulas()
	_test_xp_budget()
	_test_extra_enemy_formula()
	_test_spawn_point_safety()
	_test_stacking_rules()
	await _load_scene()
	await _test_gates_and_refresh()
	await _test_survival_early_clear()
	await _test_practice_start()
	_prog.clear_progress()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	RunState.seed_override = 0
	quit(1 if _failures > 0 else 0)


# --- Formulas -----------------------------------------------------------------

func _test_formulas() -> void:
	_check([MageLevels.cap(1), MageLevels.cap(2), MageLevels.cap(3)] == [4, 7, 10], "cap(D) = 3D + 1: 4 / 7 / 10")
	_check([MageLevels.arrival_level(1), MageLevels.arrival_level(2), MageLevels.arrival_level(3)] == [1, 4, 7],
			"arrival level = previous cap: 1 / 4 / 7")
	_check([MageLevels.offset(1), MageLevels.offset(2), MageLevels.offset(3)] == [0, 3, 6], "offset(D) = 3(D-1): 0 / 3 / 6")
	_check([MageLevels.gate(1, false, 1), MageLevels.gate(2, false, 1), MageLevels.gate(3, true, 1)] == [1, 2, 4],
			"dungeon level 1 gates: rooms Lv 1 / 2, boss Lv 4")
	_check([MageLevels.gate(1, false, 2), MageLevels.gate(2, false, 2), MageLevels.gate(3, true, 2)] == [4, 5, 7],
			"dungeon level 2 gates: rooms Lv 4 / 5, boss Lv 7")
	_check([MageLevels.gate(1, false, 3), MageLevels.gate(2, false, 3), MageLevels.gate(3, true, 3)] == [7, 8, 10],
			"dungeon level 3 gates: rooms Lv 7 / 8, boss Lv 10")
	for d in range(1, 8):
		_check(MageLevels.cap(d) - MageLevels.arrival_level(d) == 3 and MageLevels.gate(1, false, d) == MageLevels.arrival_level(d),
				"level %d: the first room is open on arrival and the boss is 3 level-ups away" % d)
	_check([MageLevels.level_up_cost(1, XP_PER_LEVEL), MageLevels.level_up_cost(2, XP_PER_LEVEL), MageLevels.level_up_cost(3, XP_PER_LEVEL)]
			== [300, 750, 1200], "level-up cost per dungeon level: 300 / 750 / 1200 XP")
	_check(absf(MageLevels.xp_multiplier(1, XP_PER_LEVEL) - 2.484) < 0.01 and absf(MageLevels.xp_multiplier(2, XP_PER_LEVEL) - 6.210) < 0.01
			and absf(MageLevels.xp_multiplier(3, XP_PER_LEVEL) - 9.936) < 0.01, "XP multiplier: 2.48 / 6.21 / 9.94")


# --- XP budget ------------------------------------------------------------------

## XP of the authored enemies per room: {tier -> Array of room XP}, bosses and treasure rooms excluded.
func _room_xp_by_tier() -> Dictionary:
	var dungeon := (load(SCENE) as PackedScene).instantiate() as Dungeon
	var tiers := {1: [], 2: []}
	for spec in dungeon.rooms:
		if spec.is_boss or spec.is_treasure():
			continue
		var xp := 0
		var inst := spec.scene.instantiate()
		for enemy in inst.get_node(^"Enemies").get_children():
			xp += (enemy as Enemy).xp_reward
		inst.free()
		for scene in spec.enemies:
			var e := scene.instantiate() as Enemy
			xp += e.xp_reward
			e.free()
		tiers[spec.required_level].append(xp)
	dungeon.free()
	return tiers


func _test_xp_budget() -> void:
	var tiers := _room_xp_by_tier()
	var tier1: int = tiers[1].reduce(func(a: int, b: int) -> int: return a + b, 0)
	var tier2: int = tiers[2].reduce(func(a: int, b: int) -> int: return a + b, 0)
	_check(tier1 + tier2 == MageLevels.PRE_BOSS_BASE_XP, "pre-boss XP constant matches the dungeon (%d + %d = %d)" % [tier1, tier2, MageLevels.PRE_BOSS_BASE_XP])
	for d in range(1, 8):
		var mult := MageLevels.xp_multiplier(d, XP_PER_LEVEL)
		var cost := MageLevels.level_up_cost(d, XP_PER_LEVEL)
		var first_cost := XP_PER_LEVEL * MageLevels.arrival_level(d)
		_check(tier1 * mult >= first_cost, "level %d: tier-1 rooms alone unlock tier 2 (%.0f >= %d)" % [d, tier1 * mult, first_cost])
		_check((tier1 + tier2) * mult >= cost and (tier1 + tier2) * mult <= cost * 1.5,
				"level %d: pre-boss XP %.0f covers the boss gate (%d) without large waste" % [d, (tier1 + tier2) * mult, cost])
		# Simulate the kills through RunState (tier 1 first), carrying the XP fraction.
		var run := RunState.new()
		run.configure(NORMAL)
		run.dungeon_level = d
		run.level = MageLevels.arrival_level(d)
		for xp: int in tiers[1]:
			run.grant_enemy_rewards(xp, 0)
		var unlocked_tier2 := run.level > MageLevels.arrival_level(d)
		for xp: int in tiers[2]:
			run.grant_enemy_rewards(xp, 0)
		_check(unlocked_tier2 and run.level == MageLevels.cap(d), "level %d: clearing the rooms reaches the boss gate (Lv %d)" % [d, run.level])
		run.free()


# --- Extra enemies ----------------------------------------------------------------

func _extras(tier: int, d: int, required_level: int, free_points: int) -> int:
	var run := RunState.new()
	run.configure(tier)
	run.dungeon_level = d
	var n := run.extra_room_enemies(required_level, free_points)
	run.free()
	return n


func _test_extra_enemy_formula() -> void:
	_check(_extras(NORMAL, 1, 1, 5) == 0 and _extras(NORMAL, 1, 2, 5) == 0, "level 1 / Normal: no extra enemies")
	_check(_extras(NORMAL, 2, 1, 5) == 1 and _extras(NORMAL, 2, 2, 5) == 1, "level 2: +1 enemy in every combat room")
	_check(_extras(NORMAL, 3, 1, 5) == 2, "level 3: tier-1 rooms +2 (no bonus)")
	_check(_extras(NORMAL, 3, 2, 5) == 3 and _extras(NORMAL, 3, 2, 4) == 3, "level 3: tier-2 rooms with >= 4 free points get one more (+3)")
	_check(_extras(NORMAL, 3, 2, 3) == 2, "level 3: tier-2 rooms with < 4 free points get no bonus, capped by the points")
	_check(_extras(NORMAL, 2, 1, 0) == 0 and _extras(NORMAL, 4, 1, 2) == 2, "never more than the free safe points")
	_check(_extras(NORMAL, 9, 2, 8) == RunState.MAX_EXTRA_ENEMIES and _extras(NORMAL, 9, 1, 8) == RunState.MAX_EXTRA_ENEMIES,
			"hard cap of +%d" % RunState.MAX_EXTRA_ENEMIES)
	_check(_extras(HARD, 3, 2, 8) == 4 and _extras(HARD, 2, 2, 8) == 2 and _extras(ABYSSAL, 5, 2, 8) == RunState.MAX_EXTRA_ENEMIES,
			"difficulty extras are added before the cap (Hard L3 = 1+3 = 4, Hard L2 = 1+1 = 2, Abyssal L5 capped)")
	var run := RunState.new()
	run.configure(NORMAL)
	var waves: Array[int] = []
	for d in [1, 2, 3, 6, 9]:
		run.dungeon_level = d
		waves.append(run.extra_wave_enemies())
	_check(waves == [0, 1, 2, 4, 4], "survival waves: +1 per level, capped at +4 (%s)" % [waves])
	run.free()
	run = RunState.new()
	run.configure(ABYSSAL)
	run.dungeon_level = 4
	_check(run.extra_wave_enemies() == 4, "survival waves: Abyssal extras count before the cap (2 + 3 -> 4)")
	run.free()


func _test_spawn_point_safety() -> void:
	for path in ["res://scenes/rooms/templates/dungeon_template.tscn", "res://scenes/rooms/templates/cave_template.tscn",
			"res://scenes/rooms/templates/crypt_template.tscn"]:
		var scene := load(path) as PackedScene
		var room := scene.instantiate() as Room
		var used := 5
		var points := room.safe_extra_points(used)
		var doors := room.get_node(^"Doors").get_children()
		var safe := points.all(func(pos: Vector2) -> bool:
			return doors.all(func(door: Node2D) -> bool:
				return pos.distance_to(door.position + (door.get_parent() as Node2D).position) >= 180.0))
		_check(safe and points.size() <= room.get_node(^"SpawnPoints").get_child_count() - used,
				"%s: extra spawn points are %d away from doors (%d free)" % [path.get_file(), 180, points.size()])
		var goblin := load("res://scenes/enemies/giant_goblin.tscn") as PackedScene
		var pool: Array[PackedScene] = [goblin, goblin, goblin, goblin, goblin]
		var added := room.add_extra_enemies(pool, 4, used)
		var positions := room.get_node(^"Enemies").get_children().map(func(e: Node2D) -> Vector2: return e.position)
		var unique := {}
		for pos: Vector2 in positions:
			unique[pos] = true
		_check(added == mini(4, points.size()) and added <= points.size() and unique.size() == positions.size(),
				"%s: asking for +4 adds %d (<= free points), none overlap" % [path.get_file(), added])
		room.free()


# --- Stacking ------------------------------------------------------------------------

func _next_level(run: RunState) -> void:
	run.boss_defeated = true
	run.choose_relic(&"wind_relic")
	run.begin_next_level()


func _test_stacking_rules() -> void:
	var run := RunState.new()
	run.configure(NORMAL)
	_check(run.collect_item(&"swift_boots") and run.collected[&"swift_boots"] == 1 and is_equal_approx(run.move_speed_multiplier(), 1.08),
			"first Swift Boots: x1, +8% speed")
	_check(not run.collect_item(&"swift_boots") and not run.can_collect(&"swift_boots"), "not collectible twice on the same level")
	_next_level(run)
	_check(run.can_collect(&"swift_boots") and not run.is_collected(&"swift_boots"), "the pickup refreshes on the next level")
	_check(run.collect_item(&"swift_boots") and run.collected[&"swift_boots"] == 2, "second level: stack x2")
	var speed := run.move_speed_multiplier()
	run.changed.emit()
	run.changed.emit()
	_check(is_equal_approx(speed, 1.0 + 0.05 + 0.08 * 2) and is_equal_approx(run.move_speed_multiplier(), speed),
			"bonus = count x effect, computed once (x%.2f incl. +5%% Wind Relic)" % speed)
	_next_level(run)
	_check(run.collect_item(&"swift_boots") and run.collected[&"swift_boots"] == 3, "third level: stack x3")
	_next_level(run)
	_check(not run.can_collect(&"swift_boots") and not run.collect_item(&"swift_boots") and run.collected[&"swift_boots"] == RunState.MAX_STACKS,
			"capped at %d stacks" % RunState.MAX_STACKS)
	# Treasures: stack bonus up to the cap, gold on every claim.
	var gold := run.currency
	var claims := 0
	for i in 5:
		if run.claim_treasure(&"rune_sigil"):
			claims += 1
		_check(not run.claim_treasure(&"rune_sigil"), "chest is empty for the rest of level %d" % run.dungeon_level)
		_next_level(run)
	_check(claims == 5 and run.treasures[&"rune_sigil"] == RunState.MAX_STACKS and is_equal_approx(run.spell_cooldown_multiplier(), 0.7),
			"treasure stacks cap at %d (cooldown x%.2f)" % [RunState.MAX_STACKS, run.spell_cooldown_multiplier()])
	var before := run.currency
	run.claim_treasure(&"survivor_cache")
	_check(run.currency > before and run.treasures[&"survivor_cache"] == 1, "a chest pays its gold again on a later level (+%d)" % (run.currency - before))
	run.free()


# --- Scene tests -----------------------------------------------------------------------

func _test_gates_and_refresh() -> void:
	var boss_i := _dungeon.boss_index()
	var boots_i := _dungeon.item_room_index(&"swift_boots")
	var tier2 := _first_room_with_level(2)
	_check(_dungeon.gate_level(boss_i) == 4 and _dungeon.gate_level(boots_i) == 1 and _dungeon.gate_level(tier2) == 2,
			"scene gates on level 1: tier 1 = Lv 1, tier 2 = Lv 2, boss = Lv 4")
	_run.add_rewards(10000, 0)
	_grant_seals()
	_check(_run.level == 4 and _dungeon.can_enter(boss_i), "the boss opens at Lv 4")
	# Build on level 1: boots (item) and Rune Sigil (treasure).
	_dungeon.enter_room(boots_i, _dungeon.entry_door(boots_i))
	await _frames(2)
	await _kill_all(_dungeon.current_room)
	var pickup := _pickup(_dungeon.current_room)
	_check(pickup != null and pickup.collect() and _run.collected[&"swift_boots"] == 1, "level 1: Swift Boots collected")
	_check(_run.claim_treasure(&"rune_sigil") and _run.treasures[&"rune_sigil"] == 1, "level 1: Rune Sigil claimed")
	await _win_fast()
	_check(_overlay().choose_relic(&"ember_relic") and _run.dungeon_level == 2, "setup: level 2 started")
	# Every level has its own seeded layout (Issue #45): find the rooms again.
	boss_i = _dungeon.boss_index()
	boots_i = _dungeon.item_room_index(&"swift_boots")
	tier2 = _first_room_with_level(2)
	var hp_items := _run.collected.duplicate()
	_check(_run.level == 4 and _run.collected == hp_items and _run.treasures[&"rune_sigil"] == 1, "owned counts survive the level change")
	# Gates on level 2: the Mage keeps Lv 4, which is exactly the first tier.
	_check(_dungeon.gate_level(boss_i) == 7 and _dungeon.gate_level(boots_i) == 4 and _dungeon.gate_level(tier2) == 5,
			"scene gates on level 2: tier 1 = Lv 4, tier 2 = Lv 5, boss = Lv 7")
	_check(_dungeon.can_enter(boots_i) and not _dungeon.can_enter(tier2) and not _dungeon.can_enter(boss_i),
			"level 2: a high Mage level does not bypass the gates")
	_check(_run.max_level() == 7 and not _run.is_max_level(), "the Mage cap rose to Lv 7")
	_run.add_rewards(10000, 0)
	_grant_seals()
	_check(_run.level == 7 and _dungeon.can_enter(boss_i), "level 2: the boss opens at Lv 7")
	# Pickup and chests refresh on level 2.
	_dungeon.enter_room(boots_i, _dungeon.entry_door(boots_i))
	await _frames(2)
	var base_enemies := _dungeon.rooms[boots_i].enemies.size()
	_check(_enemies(_dungeon.current_room).size() >= base_enemies + 1 or _enemies(_dungeon.current_room).size() == _dungeon.current_room.get_node(^"SpawnPoints").get_child_count(),
			"level 2: +1 enemy in a combat room (%d -> %d)" % [base_enemies, _enemies(_dungeon.current_room).size()])
	await _kill_all(_dungeon.current_room)
	pickup = _pickup(_dungeon.current_room)
	_check(pickup != null and pickup.is_active() and pickup.collect() and _run.collected[&"swift_boots"] == 2,
			"level 2: the Swift Boots pickup is back and stacks to x2")
	var label := (_dungeon.get_node(^"RunHud") as RunHud).get_node(^"%ItemsLabel") as Label
	_check(label.text.contains("Swift Boots x2") and label.text.contains("Rune Sigil"), "HUD shows the stack count (%s)" % label.text.replace("\n", " | "))
	_check(is_equal_approx(_mage.speed_multiplier, 1.0 + 0.08 * 2), "stacked speed bonus is applied once (x%.2f)" % _mage.speed_multiplier)
	var puzzle := await _enter(_dungeon.treasure_index(RoomSpec.Treasure.PUZZLE))
	var chest := puzzle.get_node(^"Decor/TreasureChest") as TreasureChest
	_check(chest.run_state == _run and not chest.is_claimed() and chest.prompt_text() != "Empty chest", "level 2: the puzzle chest is not empty")
	_check(_run.claim_treasure(&"rune_sigil") and _run.treasures[&"rune_sigil"] == 2, "level 2: the chest bonus stacks to x2")
	var boss := await _enter(_dungeon.boss_index())
	_check(_enemies(boss).size() == 1, "no extra enemies in the boss room")
	var survival := await _enter(_dungeon.treasure_index(RoomSpec.Treasure.SURVIVAL)) as SurvivalRoom
	_check(survival.extra_per_wave == 1, "level 2: survival waves get +1 enemy each")
	_check(_enemies(survival).is_empty() and survival.get_node(^"Decor/TreasureChest").run_state == _run,
			"no extra enemies in the survival room before the trial")


func _test_survival_early_clear() -> void:
	await _load_scene()
	_run.add_rewards(10000, 0)
	var room := await _enter(_dungeon.treasure_index(RoomSpec.Treasure.SURVIVAL)) as SurvivalRoom
	_check(room.begin_challenge(), "setup: survival trial started")
	var tries := 0
	while room.state == Room.State.COMBAT and tries < 12:
		await _kill_all(room)
		await _frames(2)
		tries += 1
	_check(room.state == Room.State.CLEARED and room.waves_spawned == room.wave_count() and room.time_left() > room.duration - 20.0,
			"the trial ends as soon as the last wave is defeated (%.0f s left of %.0f)" % [room.time_left(), room.duration])
	_check(room.can_exit() and room.chest.is_unlocked() and room.status_text() == "Trial complete! Open the chest", "the chest unlocks and the exit opens")
	var seeker := RunState.new()
	seeker.configure(NORMAL, &"treasure_seeker")
	_check(not Pacts.PACTS[&"treasure_seeker"].has("survival_time") and not Pacts.PACTS[&"treasure_seeker"]["drawback"].contains("survival"),
			"the obsolete survival time bonus is gone")
	seeker.free()


func _test_practice_start() -> void:
	_prog.clear_progress()
	_prog.record_run(7, 3, 100.0, 60.0, NORMAL, &"dungeon")
	var best := _prog.best_run.duplicate()
	_check(_prog.select(NORMAL, &"", 3), "setup: practice start at level 3 selected")
	await _load_scene()
	_check(_run.dungeon_level == 3 and _run.is_replay and _run.level == 7 and _run.max_level() == 10, "practice run starts at level 3 with Mage Lv 7")
	_check(_run.collected.is_empty() and _run.relics.is_empty() and _run.treasures.is_empty() and _run.purchased.is_empty() and _run.currency == 0,
			"practice run grants no items, relics, treasures or gold")
	var base_hp := (load("res://scenes/mage/mage.tscn") as PackedScene).instantiate()
	var expected_hp: float = (base_hp.get_node(^"Health") as Health).max_health + 6 * _run.max_health_per_level
	base_hp.free()
	_check(is_equal_approx(_mage.health.max_health, expected_hp) and is_equal_approx(_mage.health.current, expected_hp),
			"practice run has the max HP of 6 level-ups (%.0f)" % _mage.health.max_health)
	var tier2 := _first_room_with_level(2)
	_check(_dungeon.can_enter(_dungeon.item_room_index(&"swift_boots")) and not _dungeon.can_enter(tier2) and not _dungeon.can_enter(_dungeon.boss_index()),
			"practice gates: tier 1 open, tier 2 (Lv 8) and boss (Lv 10) locked")
	# Extra enemies in real rooms: tier 1 gets +2 on level 3, tier 2 may get one more.
	var room := await _enter(_dungeon.item_room_index(&"swift_boots"))
	var spec := _dungeon.rooms[_dungeon.item_room_index(&"swift_boots")]
	var fresh := spec.scene.instantiate() as Room
	var free := fresh.safe_extra_points(spec.enemies.size()).size()
	fresh.free()
	_check(_enemies(room).size() == spec.enemies.size() + mini(2, free), "level 3 tier-1 room: %d + min(2, %d free) enemies (%d)" % [spec.enemies.size(), free, _enemies(room).size()])
	_run.add_rewards(10000, 0)
	var spec2 := _dungeon.rooms[tier2]
	var room2 := await _enter(tier2)
	var fresh2 := spec2.scene.instantiate() as Room
	var free2 := fresh2.safe_extra_points(spec2.enemies.size()).size()
	fresh2.free()
	var expected := spec2.enemies.size() + mini(2 + (1 if free2 >= 4 else 0), free2)
	_check(_enemies(room2).size() == expected, "level 3 tier-2 room: %d enemies (%d free points)" % [expected, free2])
	_check(_prog.best_run == best and _prog.completion_count(NORMAL) == 0, "practice runs change no record or unlock")


# --- Helpers ------------------------------------------------------------------------------

func _first_room_with_level(level: int) -> int:
	for i in _dungeon.rooms.size():
		var spec := _dungeon.rooms[i]
		# Miniboss rooms replace their line-up and get no extras (test_minibosses.gd).
		if spec.required_level == level and not spec.is_boss and not spec.is_treasure() and not spec.enemies.is_empty() and _dungeon.miniboss_scene(i) == null:
			return i
	return -1


func _enter(index: int) -> Room:
	_dungeon.enter_room(index, _dungeon.entry_door(index))
	await _frames(2)
	return _dungeon.current_room


func _load_scene() -> void:
	var old_id := current_scene.get_instance_id() if current_scene else 0
	paused = false
	change_scene_to_file(SCENE)
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage
	_run = _dungeon.run_state


func _win_fast() -> void:
	while _run.level < _run.max_level():
		_run.add_rewards(_run.xp_to_next_level(), 0)
	_grant_seals()
	_dungeon.enter_room(_dungeon.boss_index(), &"DoorBottom")
	await _frames(2)
	for e in _dungeon.current_room.get_node(^"Enemies").get_children():
		if e is Boss:
			(e as Boss).take_damage(99999.0)
	await _wait_until(func() -> bool: return _overlay().is_open, 240)


func _kill_all(room: Room) -> void:
	for enemy in _enemies(room):
		enemy.take_damage(99999.0)
	await _wait_until(func() -> bool: return _enemies(room).is_empty())
	await _frames(1)


func _enemies(room: Room) -> Array:
	return room.get_node(^"Enemies").get_children().filter(func(n: Node) -> bool: return n is Enemy and not n.is_queued_for_deletion())


func _pickup(room: Room) -> ItemPickup:
	for child in room.get_node(^"Decor").get_children():
		if child is ItemPickup and not child.is_queued_for_deletion():
			return child
	return null


func _overlay() -> VictoryOverlay:
	return current_scene.get_node_or_null(^"VictoryOverlay") as VictoryOverlay


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


## Ancient Seals (Issue #43): the boss gate also needs this level's seals; collect them all.
func _grant_seals() -> void:
	for i: int in _dungeon.seal_rooms():
		_run.collect_seal(_dungeon.seal_id(i))
