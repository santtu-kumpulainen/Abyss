extends SceneTree
## Headless check of Issue #43 stage 3: FloorHazard (telegraph timing,
## eruption / lingering damage, cleanup), the Brood Mother (punish window,
## telegraphed summons with 0-XP Demons, locked charge lane), the Hexcaller
## (fan telegraph, hex zones, blink), miniboss placement over many seeds,
## miniboss XP / gold (= the replaced encounter), the pick-1-of-2 reward and
## its duplication rules, the seal drop, and champion rooms (1 miniboss).
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_minibosses.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENE := "res://scenes/dungeon/dungeon.tscn"
const SEED := 31337
const SEEDS := 200


class Dummy extends Node2D:
	var taken := 0.0

	func take_damage(amount: float) -> void:
		taken += amount


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
	await _test_floor_hazard()
	RunState.seed_override = SEED
	await _load()
	if _dungeon == null:
		_check(false, "dungeon scene loaded")
	else:
		_test_placement()
		await _load()
		await _test_brood_mother()
		await _load()
		await _test_hexcaller()
		await _load()
		await _test_rewards_and_seal()
		await _test_reward_fallback()
		await _load()
		await _test_champion_room()
		await _load()
		await _test_unsealed_miniboss_room()
		_test_progression()
		await _load()
		await _test_double_room(4)
		await _load()
		await _test_double_room(6)
		await _load()
		var hard_l3 := await _test_miniboss_economy(Difficulty.Tier.HARD, 3)
		await _load()
		await _test_miniboss_economy(Difficulty.Tier.ABYSSAL, 4)
		await _load()
		await _test_miniboss_economy(Difficulty.Tier.NORMAL, 2)
		await _load()
		var again := await _test_miniboss_economy(Difficulty.Tier.HARD, 3)
		_check(not hard_l3.is_empty() and hard_l3 == again, "economy: same seed -> identical compensation and miniboss rewards (%s)" % hard_l3)
		await _load()
		await _test_caverns_rewards(false)
		await _load()
		await _test_caverns_rewards(true)
		_test_early_levels_unswapped()
	RunState.seed_override = 0
	if _prog:
		_prog.clear_progress()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- FloorHazard -------------------------------------------------------------------

func _test_floor_hazard() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var inside := Dummy.new()
	var outside := Dummy.new()
	for d in [inside, outside]:
		d.add_to_group(&"player")
		arena.add_child(d)
	inside.global_position = Vector2(100, 100)
	outside.global_position = Vector2(100 + 61, 100)
	var hits := [-1]
	var hazard := FloorHazard.spawn(arena, Vector2(100, 100), 60.0, 0.5, 12.0)
	hazard.erupted.connect(func(n: int) -> void: hits[0] = n)
	await _physics(0.4)
	_check(inside.taken == 0.0 and hazard.phase == FloorHazard.Phase.TELEGRAPH and hazard.time_to_erupt() > 0.0,
			"telegraph: harmless before its delay")
	await _physics(0.2)
	_check(inside.taken == 12.0 and outside.taken == 0.0 and hits[0] == 1, "eruption: damages only targets inside the radius, once")
	await _frames(1)
	_check(not is_instance_valid(hazard), "a hazard without lifetime frees itself after erupting")

	# Lingering zone: pulses while the target stays, nothing once it steps out.
	inside.taken = 0.0
	var zone := FloorHazard.spawn(arena, Vector2(100, 100), 60.0, 0.2, 5.0, 2.1)
	zone.pulse_interval = 0.5
	await _physics(0.3)
	_check(inside.taken == 5.0 and zone.phase == FloorHazard.Phase.LINGER, "lingering zone: eruption damage, then it stays")
	await _physics(0.55)
	_check(inside.taken == 10.0, "lingering zone: pulses damage a target standing inside (%.0f)" % inside.taken)
	inside.global_position = Vector2(400, 100)
	await _physics(1.0)
	_check(inside.taken == 10.0, "lingering zone: stepping out avoids further pulses")
	await _physics(0.8)
	_check(not is_instance_valid(zone), "lingering zone frees itself after its lifetime")

	# Damage 0 (summon circle): never hurts, still erupts.
	inside.global_position = Vector2(100, 100)
	inside.taken = 0.0
	var erupted := [false]
	var circle := FloorHazard.spawn(arena, Vector2(100, 100), 40.0, 0.1, 0.0)
	circle.erupted.connect(func(_n: int) -> void: erupted[0] = true)
	await _physics(0.2)
	_check(erupted[0] and inside.taken == 0.0, "a 0-damage hazard erupts without damage")

	# Cleanup: the source dying / leaving, and the room being unloaded.
	var source := Node2D.new()
	source.add_user_signal(&"died")
	arena.add_child(source)
	var a := FloorHazard.spawn(arena, Vector2.ZERO, 40.0, 5.0, 1.0, 0.0, source)
	var b := FloorHazard.spawn(arena, Vector2.ZERO, 40.0, 5.0, 1.0, 0.0, source)
	source.emit_signal(&"died")
	await _frames(1)
	_check(not is_instance_valid(a) and not is_instance_valid(b), "hazards are removed when their source dies")
	var room := Node2D.new()
	arena.add_child(room)
	var c := FloorHazard.spawn(room, Vector2.ZERO, 40.0, 5.0, 1.0, 2.0)
	arena.remove_child(room)
	await _frames(1)
	_check(not is_instance_valid(c), "hazards are removed when their room leaves the tree")
	room.free()
	arena.queue_free()
	await _frames(1)


# --- Placement ---------------------------------------------------------------------

func _test_placement() -> void:
	var pool := RunState.miniboss_reward_pool()
	_check(pool.size() >= 4 and pool.all(func(id: StringName) -> bool: return RunState.ITEMS.has(id)),
			"miniboss rewards come from RunState.ITEMS (%d items)" % pool.size())
	var placed_items := _dungeon.rooms.filter(func(r: RoomSpec) -> bool: return not r.item.is_empty()) \
			.map(func(r: RoomSpec) -> StringName: return r.item)
	_check(not pool.any(func(id: StringName) -> bool: return placed_items.has(id)), "miniboss rewards never clash with room item pickups")
	for count in [1, 2, 3]:
		_dungeon.miniboss_rooms = count
		var ok := true
		var both := true
		var rewards_ok := true
		var distinct_rooms := {}
		for s in SEEDS:
			_run.run_seed = s + 1
			_dungeon._plan_level()
			var anvil := _dungeon.index_at(_dungeon.final_anvil_cell)  # per-seed layout (Issue #45)
			var seals := _dungeon.seal_rooms()
			var bosses := _dungeon.miniboss_room_indexes()
			var seal_bosses := seals.keys().filter(func(i: int) -> bool: return seals[i] == &"miniboss")
			distinct_rooms[str(bosses)] = true
			# Exactly 4 seal sources (Issue #45): at most 2 miniboss rooms hold a seal.
			ok = ok and bosses.size() == count and seals.size() == EncounterPlanner.SEAL_SOURCES \
					and seal_bosses.size() == mini(count, 2) and seal_bosses.all(func(i: int) -> bool: return bosses.has(i))
			var kinds := {}
			for i: int in bosses:
				ok = ok and _dungeon.miniboss_scene(i) != null and i != anvil and not _dungeon.rooms[i].is_boss
				kinds[_dungeon.miniboss_scene(i).resource_path] = true
				var ids := _dungeon.reward_choices(i)
				rewards_ok = rewards_ok and ids.size() == 2 and ids[0] != ids[1] and ids.all(func(id: StringName) -> bool: return pool.has(id))
			for i in _dungeon.rooms.size():
				ok = ok and (_dungeon.miniboss_scene(i) != null) == bosses.has(i)
			# The shuffle bag never repeats a type before all have appeared.
			both = both and kinds.size() == mini(count, _dungeon.miniboss_scenes.size())
			if count == 2:
				var all_ids := _dungeon.reward_choices(bosses[0]) + _dungeon.reward_choices(bosses[1])
				var unique := {}
				for id in all_ids:
					unique[id] = true
				rewards_ok = rewards_ok and unique.size() == 4
			if count == 2:
				ok = ok and not _adjacent(bosses[0], bosses[1])
		_check(ok, "%d miniboss room(s): exactly the planned miniboss rooms, %d of them seal sources, never boss/anvil (%d seeds)%s"
				% [count, mini(count, 2), SEEDS, " and never adjacent" if count == 2 else ""])
		_check(both, "%d miniboss room(s): %s" % [count, "%d different miniboss types" % mini(count, _dungeon.miniboss_scenes.size()) if count >= 2 else "one miniboss"])
		_check(rewards_ok, "%d miniboss room(s): two different reward items each%s" % [count, ", all four different" if count == 2 else ""])
		_check(distinct_rooms.size() > 5, "%d miniboss room(s): placement varies by seed (%d layouts)" % [count, distinct_rooms.size()])
	_dungeon.miniboss_rooms = 2
	_run.run_seed = SEED
	_dungeon._plan_level()
	var first := _miniboss_map()
	_dungeon._plan_level()
	_check(first == _miniboss_map(), "same seed -> same miniboss rooms, scenes and rewards")


# --- Brood Mother ------------------------------------------------------------------

func _test_brood_mother() -> void:
	var index := _miniboss_room(BroodMother)
	var mother := await _enter_miniboss(index) as BroodMother
	_check(mother != null, "setup: Brood Mother room built")
	if mother == null:
		return
	var lineup := _dungeon.room_lineup(index)
	_check(mother.xp_reward == EncounterPlanner.lineup_xp(_mapped(lineup, _run.dungeon_level)) and mother.xp_reward > 0
			and mother.currency_reward == EncounterPlanner.lineup_gold(_mapped(lineup, _run.dungeon_level)) + _dungeon.miniboss_compensation_gold(index) + _dungeon.miniboss_bonus_gold,
			"Brood Mother: XP = replaced encounter (%d), gold = encounter + omitted extras + bonus" % mother.xp_reward)
	_check(_enemies(_dungeon.current_room).size() == 1, "miniboss room: no other encounter enemies")
	var room := _dungeon.current_room
	_park_mage(mother, Vector2(260, 0))

	# Summon: punish window and telegraphed circles.
	var hp := mother.health.current
	_check(mother.begin_summon() and mother.state == Miniboss.State.WINDUP and mother.is_vulnerable(), "summon: channel starts as a punish window")
	mother.take_damage(10.0)
	var expected := 10.0 * mother.damage_taken_multiplier * mother.punish_multiplier
	_check(is_equal_approx(hp - mother.health.current, expected), "summon: she takes x%.1f damage while channelling (%.1f)" % [mother.punish_multiplier, hp - mother.health.current])
	var circles := _hazards_of(mother)
	_check(circles.size() == mother.summon_count and circles.all(func(h: FloorHazard) -> bool: return (h.damage == 0.0
			and is_equal_approx(h.delay, mother.summon_windup))), "summon: %d harmless circles telegraph the spawns" % mother.summon_count)
	var before := _enemies(room).size()
	await _wait_until(func() -> bool: return mother.state != Miniboss.State.WINDUP, 400)
	await _frames(2)
	var demons := mother.alive_summons()
	_check(demons.size() == mother.summon_count and _enemies(room).size() == before + mother.summon_count
			and demons.all(func(d: Enemy) -> bool: return d.xp_reward == 0 and d.currency_reward == 0 and d.scaled),
			"summon: Demons crawl out with 0 XP / 0 gold, scaled and counted for the clear")
	var demon_base := (load("res://scenes/enemies/demon.tscn") as PackedScene).instantiate() as Enemy
	var expected_speed := minf(demon_base.speed * _run.enemy_move_pace_multiplier(), demon_base.speed_cap)
	demon_base.free()
	_check(demons.all(func(d: Enemy) -> bool: return is_equal_approx(d.speed, expected_speed) and d.speed > _mage.speed),
			"summoned Demons get the run's Demon move speed (%.1f, faster than the Mage's %.0f)" % [expected_speed, _mage.speed])
	_check(not mother.is_vulnerable(), "summon: the punish window closes")
	var xp := _run.xp
	var gold := _run.currency
	# Blood Pact's kill heal must not come from summons either.
	_run.pact = &"blood_pact"
	_mage.health.take_damage(30.0)
	var hurt := _mage.health.current
	for d in demons:
		d.take_damage(99999.0)
	await _frames(2)
	_check(_run.xp == xp and _run.currency == gold and demons.all(func(d) -> bool: return not is_instance_valid(d) or d.summoned),
			"summoned Demons grant no XP and no gold")
	_check(is_equal_approx(_mage.health.current, hurt), "summoned Demons grant no kill heal (Blood Pact)")
	await _wait_until(func() -> bool: return mother.state == Miniboss.State.CHASE, 200)

	# Charge: locked lane, dodge by sidestepping.
	mother.set_physics_process(false)
	_park_mage(mother, Vector2(300, 0))
	mother.set_physics_process(true)
	_check(mother.begin_charge() and mother.charge_aim().is_equal_approx(Vector2.RIGHT), "charge: the aim locks on the Mage")
	_mage.global_position = mother.global_position + Vector2(300, 180)
	var mage_hp := _mage.health.current
	await _wait_until(func() -> bool: return mother.state == Miniboss.State.RECOVER, 300)
	_check(mother.charge_aim().is_equal_approx(Vector2.RIGHT) and is_equal_approx(_mage.health.current, mage_hp),
			"charge: the lane does not follow the Mage; a sidestep dodges it")
	await _wait_until(func() -> bool: return mother.state == Miniboss.State.CHASE, 200)
	mother.set_physics_process(false)
	_park_mage(mother, Vector2(-250, 0))
	mother.set_physics_process(true)
	mage_hp = _mage.health.current
	mother.begin_charge()
	await _wait_until(func() -> bool: return mother.state == Miniboss.State.RECOVER, 300)
	_check(is_equal_approx(mage_hp - _mage.health.current, mother.charge_damage * _mage.damage_taken_multiplier),
			"charge: a Mage left in the lane takes the charge damage once (%.1f)" % (mage_hp - _mage.health.current))

	# Summon circles stay inside the floor even when she channels in a corner.
	await _wait_until(func() -> bool: return mother.state == Miniboss.State.CHASE, 200)
	var floor_rect := (room.get_node(^"Visuals") as RoomVisuals).floor_rect.grow(-mother.floor_margin + 1.0)
	mother.global_position = room.to_global(floor_rect.position + Vector2(10, 10))
	_park_mage(mother, Vector2(300, 200))
	mother.begin_summon()
	var cornered := _hazards_of(mother)
	_check(not cornered.is_empty() and cornered.all(func(h: FloorHazard) -> bool: return floor_rect.has_point(room.to_local(h.global_position))),
			"summon circles are kept inside the room floor (away from walls and corner decor)")
	await _wait_until(func() -> bool: return mother.state == Miniboss.State.CHASE, 400)
	for d in mother.alive_summons():
		d.take_damage(99999.0)
	await _frames(2)

	# Death during a summon: circles vanish, nothing spawns, summons crumble.
	_park_mage(mother, Vector2(300, 0))
	mother.begin_summon()
	var pending := _hazards_of(mother)
	_mage.health.take_damage(10.0)
	var before_kill := _mage.health.current
	mother.take_damage(999999.0)
	await _frames(2)
	_check(pending.all(func(h) -> bool: return not is_instance_valid(h)) and _enemies(room).is_empty(),
			"death mid-summon: circles removed, no Demons spawn")
	_check(_mage.health.current > before_kill, "the miniboss itself still grants the Blood Pact kill heal")
	await _wait_until(func() -> bool: return room.state == Room.State.CLEARED)
	_check(room.state == Room.State.CLEARED, "the Brood Mother room clears")
	_dungeon.enter_room(_dungeon.start_room)
	await _frames(1)
	_dungeon.enter_room(index)
	await _frames(2)
	_check(_dungeon.current_room == room and room.state == Room.State.CLEARED and _enemies(room).is_empty()
			and room.get_children().filter(func(n) -> bool: return n is FloorHazard).is_empty() and room.can_exit(),
			"revisiting the cleared miniboss room: no boss, summons or hazards")


# --- Hexcaller ---------------------------------------------------------------------

func _test_hexcaller() -> void:
	var index := _miniboss_room(Hexcaller)
	var hex := await _enter_miniboss(index) as Hexcaller
	_check(hex != null, "setup: Hexcaller room built")
	if hex == null:
		return
	_check(hex.xp_reward == EncounterPlanner.lineup_xp(_dungeon.room_lineup(index)), "Hexcaller: XP = replaced encounter (%d)" % hex.xp_reward)
	hex.set_physics_process(false)
	_park_mage(hex, Vector2(300, 0))
	hex.set_physics_process(true)

	# Fan.
	_check(hex.begin_fan() and hex.state == Miniboss.State.WINDUP, "fan: telegraph starts")
	var dirs := hex.fan_directions()
	var spread := deg_to_rad(hex.fan_spread_degrees)
	_check(dirs.size() == 3 and is_equal_approx(dirs[0].angle_to(dirs[1]), spread) and is_equal_approx(dirs[1].angle_to(dirs[2]), spread),
			"fan: three aim lines, evenly spread")
	_mage.global_position += Vector2(0, 200)
	await _wait_until(func() -> bool: return hex.state != Miniboss.State.WINDUP, 200)
	var bolts := _bolts_of(hex)
	_check(bolts.size() == 3 and bolts.all(func(p: Projectile) -> bool: return dirs.any(func(d: Vector2) -> bool: return p.direction.is_equal_approx(d))),
			"fan: three bolts fly along the telegraphed (locked) lines")
	for b in bolts:
		b.queue_free()
	await _wait_until(func() -> bool: return hex.state == Miniboss.State.CHASE, 200)

	# Hex zones.
	hex.set_physics_process(false)
	_park_mage(hex, Vector2(300, 0))
	hex.set_physics_process(true)
	var at := _mage.global_position
	_check(hex.begin_hex(), "hex: cast starts")
	await _wait_until(func() -> bool: return hex.state != Miniboss.State.WINDUP, 200)
	var zones := _hazards_of(hex)
	_check(zones.size() == hex.hex_count and zones.any(func(z: FloorHazard) -> bool: return z.global_position.distance_to(at) < 1.0)
			and zones.all(func(z: FloorHazard) -> bool: return z.damage > 0.0 and z.lifetime > 0.0 and is_equal_approx(z.delay, hex.hex_delay)),
			"hex: %d lingering zones, one on the Mage, telegraphed for %.1fs" % [hex.hex_count, hex.hex_delay])
	var mage_hp := _mage.health.current
	hex.set_physics_process(false)
	await _physics(hex.hex_delay + 0.1)
	_check(is_equal_approx(mage_hp - _mage.health.current, hex.hex_damage * _mage.damage_taken_multiplier),
			"hex: standing in a zone takes its eruption damage")
	_mage.global_position = at + Vector2(0, 400)
	mage_hp = _mage.health.current
	await _physics(hex.hex_pulse * 1.5)
	_check(is_equal_approx(_mage.health.current, mage_hp), "hex: leaving the zone avoids its pulses")
	hex.set_physics_process(true)
	await _wait_until(func() -> bool: return hex.state == Miniboss.State.CHASE, 200)

	# Blink: triggered by staying close, telegraphed, lands far away.
	hex._hex_left = 999.0
	hex._fan_left = 999.0
	hex._blink_left = 0.0
	hex.set_physics_process(false)
	_park_mage(hex, Vector2(60, 0))
	hex.set_physics_process(true)
	var started := [&"", Vector2.ZERO]
	hex.attack_started.connect(func(a: StringName) -> void:
		started[0] = a
		started[1] = hex.global_position)
	await _wait_until(func() -> bool: return started[0] == &"blink", 200)
	var dest := hex.blink_destination()
	await _physics(hex.blink_windup * 0.5)
	_check(started[0] == &"blink" and hex.state == Miniboss.State.WINDUP and hex.global_position.is_equal_approx(started[1])
			and dest.distance_to(_mage.global_position) > 300.0,
			"blink: staying close starts a telegraphed blink (stands still) to a far spot")
	await _wait_until(func() -> bool: return hex.state != Miniboss.State.WINDUP, 200)
	_check(hex.global_position.is_equal_approx(dest) and is_equal_approx(hex.modulate.a, 1.0), "blink: lands on the marked destination")

	# Death cleanup.
	await _wait_until(func() -> bool: return hex.state == Miniboss.State.CHASE, 200)
	hex._hex_left = 0.0
	hex.begin_hex()
	await _wait_until(func() -> bool: return hex.state != Miniboss.State.WINDUP, 200)
	var left := _hazards_of(hex)
	hex._fan_left = 0.0
	await _wait_until(func() -> bool: return hex.state == Miniboss.State.CHASE, 200)
	hex.begin_fan()
	await _wait_until(func() -> bool: return hex.state != Miniboss.State.WINDUP, 200)
	var bolts_left := _bolts_of(hex)
	var had_both := not left.is_empty() and not bolts_left.is_empty()
	left.append_array(bolts_left)
	hex.take_damage(999999.0)
	await _frames(2)
	_check(had_both and left.all(func(z) -> bool: return not is_instance_valid(z)),
			"Hexcaller death removes its zones and bolts")


# --- Rewards and seal ----------------------------------------------------------------

func _test_rewards_and_seal() -> void:
	# A miniboss room that is one of the 4 seal sources (Issue #45: only 2 of them are).
	var index := _seal_miniboss_room()
	var boss := await _enter_miniboss(index)
	if boss == null:
		_check(false, "setup: miniboss room built")
		return
	var room := _dungeon.current_room
	var ids := _dungeon.reward_choices(index)
	var pickups := _pickups(room)
	_check(pickups.size() == 2 and pickups.all(func(p: ItemPickup) -> bool: return (not p.visible and ids.has(p.item_id)
			and p.choice_group == &"miniboss_reward")), "two reward choices wait hidden in the miniboss room")
	_run.xp_multiplier_override = 1.0
	var gold := _run.currency
	var xp := _run.xp + _run.level * 1000
	var boss_gold := boss.currency_reward
	boss.take_damage(999999.0)
	await _wait_until(func() -> bool: return room.state == Room.State.CLEARED)
	await _frames(1)
	_check(_run.currency - gold == roundi(boss_gold * _run.gold_multiplier()), "miniboss kill pays its gold (%d)" % (_run.currency - gold))
	_check(_run.xp + _run.level * 1000 > xp or _run.is_max_level(), "miniboss kill grants its XP")
	_run.xp_multiplier_override = 0.0
	var seal := room.get_node_or_null(^"Decor/AncientSeal") as AncientSeal
	_check(seal != null and seal.visible and pickups.all(func(p: ItemPickup) -> bool: return p.visible),
			"clearing the miniboss reveals its seal and both reward choices")
	var choice: ItemPickup = pickups[0]
	var choice_id: StringName = choice.item_id
	var other: ItemPickup = pickups[1]
	var other_id: StringName = other.item_id
	_check(choice.collect() and _run.collected.get(choice_id, 0) == 1, "picking one reward collects it through RunState.collect_item")
	_check(not other.is_active() and not other.collect(), "the other choice cannot be taken in the same frame")
	await _frames(1)
	_check(not is_instance_valid(other) and _run.collected.get(other_id, 0) == 0, "the other choice disappears (pick 1 of 2)")
	_check(seal.collect() and _run.seals_collected() == 1, "the miniboss seal is collected separately")
	_dungeon.enter_room(_dungeon.start_room)
	await _frames(1)
	_dungeon.enter_room(index)
	await _frames(2)
	_check(_pickups(_dungeon.current_room).is_empty() and _dungeon.current_room.get_node_or_null(^"Decor/AncientSeal") == null
			and not _run.collect_item(choice_id) and _run.seals_collected() == 1,
			"revisiting: no second reward, no second seal")


## A planned reward at its stack cap is replaced when the room is built.
func _test_reward_fallback() -> void:
	# An unvisited miniboss room (the reward test above may have used either kind).
	var index := -1
	for i in _dungeon.miniboss_room_indexes():
		if not _dungeon.is_visited(i):
			index = i
			break
	var planned := _dungeon.reward_choices(index)
	_check(index >= 0 and planned.size() == 2 and not _dungeon.is_visited(index), "setup: unbuilt miniboss room with two planned rewards")
	var capped := planned[0]
	_run.collected[capped] = RunState.MAX_STACKS
	var boss := await _enter_miniboss(index)
	var pickups := _pickups(_dungeon.current_room)
	var ids := pickups.map(func(p: ItemPickup) -> StringName: return p.item_id)
	_check(pickups.size() == 2 and not ids.has(capped) and ids[0] != ids[1] and ids.all(func(id: StringName) -> bool: return _run.can_collect(id)),
			"a capped reward is replaced, keeping two different options (%s)" % [ids])
	if boss:
		boss.take_damage(999999.0)
		await _frames(2)


# --- Champion rooms ------------------------------------------------------------------

func _test_champion_room() -> void:
	_dungeon.miniboss_rooms = 1
	_dungeon._plan_level()
	var seals := _dungeon.seal_rooms()
	var index := -1
	for i: int in seals:
		if seals[i] == &"champion":
			index = i
	_check(index >= 0 and seals.size() == EncounterPlanner.SEAL_SOURCES, "1 miniboss: a champion room keeps 4 seal sources")
	if index < 0:
		return
	_dungeon.enter_room(index)
	await _frames(2)
	var room := _dungeon.current_room
	var pack := room.get_node_or_null(^"ChampionPack") as ChampionPack
	_check(pack != null and _miniboss_in(room) == null, "champion room: ordinary pack with a ChampionPack rule")
	if pack == null:
		return
	room.start_encounter()
	await _frames(1)
	_check(pack.active and pack.champion != null and pack.warded.size() == _enemies(room).size() - 1, "champion: leader chosen, the rest warded")
	var champ_xp := pack.champion.xp_reward
	_check(_enemies(room).all(func(e: Enemy) -> bool: return e.xp_reward <= champ_xp), "champion: the strongest enemy leads")
	var member := pack.warded[0]
	var hp := member.health.current
	member.take_damage(10.0)
	var warded_hit := hp - member.health.current
	pack.champion.take_damage(999999.0)
	await _frames(2)
	hp = member.health.current
	member.take_damage(10.0)
	var open_hit := hp - member.health.current
	_check(not pack.active and is_equal_approx(warded_hit, open_hit * pack.ward_multiplier) and _message().contains("ward breaks"),
			"champion: the ward cuts damage to x%.2f until the champion dies (%.1f -> %.1f)" % [pack.ward_multiplier, warded_hit, open_hit])
	for e in _enemies(room):
		(e as Enemy).take_damage(999999.0)
	await _wait_until(func() -> bool: return room.state == Room.State.CLEARED)
	var seal := room.get_node_or_null(^"Decor/AncientSeal") as AncientSeal
	_check(seal != null and seal.visible, "champion room: clearing it reveals the seal")


# --- Progression and double rooms (Issue #45) -----------------------------------------

## Miniboss rooms that are not seal sources still give their reward choice, but no seal.
func _test_unsealed_miniboss_room() -> void:
	var index := -1
	for i in _dungeon.miniboss_room_indexes():
		if not _dungeon.seal_rooms().has(i):
			index = i
	_check(_dungeon.miniboss_count() == 3 and index >= 0, "level 1: 3 miniboss rooms by default, one without a seal")
	if index < 0:
		return
	var boss := await _enter_miniboss(index)
	var room := _dungeon.current_room
	_check(boss != null and room.get_node_or_null(^"Decor/AncientSeal") == null and _pickups(room).size() == 2,
			"unsealed miniboss room: a miniboss and two reward choices, no seal")
	for e in _enemies(room):
		(e as Enemy).take_damage(999999.0)
	await _wait_until(func() -> bool: return room.state == Room.State.CLEARED)
	await _frames(1)
	var shown := _pickups(room)
	_check(shown.size() == 2 and shown.all(func(p: ItemPickup) -> bool: return p.visible), "unsealed miniboss room: clearing it reveals both rewards")


## Miniboss / double-room counts per dungeon level (helpers and the planned
## levels), exact reward splits, seal sources, distinct pairs and reward choices.
func _test_progression() -> void:
	var counts: Array[int] = []
	var doubles: Array[int] = []
	for level in range(1, 4):
		counts.append(EncounterPlanner.miniboss_room_count(level, 7 * level))
	for level in range(1, 13):
		doubles.append(EncounterPlanner.double_miniboss_room_count(level))
	_check(counts == [3, 3, 4], "miniboss rooms on levels 1-3: fixed 3, 3, 4 (%s)" % [counts])
	_check(doubles == [0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1], "double-miniboss rooms per level 1-12: none on 1-3, exactly one from level 4 (%s)" % [doubles])
	var late := {}
	var late_ok := true
	for level in range(4, 13):
		for s in 60:
			var seed_value := EncounterPlanner.level_seed(900 + s, level)
			var singles := EncounterPlanner.single_miniboss_room_count(level, seed_value)
			late[singles] = true
			late_ok = late_ok and singles >= 2 and singles <= 3 \
					and EncounterPlanner.miniboss_room_count(level, seed_value) == singles + 1
	_check(late_ok and late.size() == 2, "levels 4-12: 1 double room + 2 or 3 single rooms, both counts occur (%s)" % [late.keys()])
	_test_shuffle_bag()
	var splits_ok := true
	for total in range(0, 25):
		for parts in [1, 2]:
			var shares := EncounterPlanner.split_reward(total, parts)
			splits_ok = splits_ok and shares.size() == parts and shares.reduce(func(a: int, b: int) -> int: return a + b, 0) == total \
					and shares.max() - shares.min() <= 1
	_check(splits_ok, "split_reward: shares always add up to the exact total (0-24 XP/gold, 1-2 minibosses)")
	_dungeon.miniboss_rooms = 0
	var pool := RunState.miniboss_reward_pool()
	var plan_ok := true
	var seal_ok := true
	var pair_ok := true
	var reward_ok := true
	var detail := ""
	for level in range(1, 11):
		for s in 25:
			_run.dungeon_level = level
			_run.run_seed = 5000 + s
			_dungeon._plan_level()
			var rooms := _dungeon.miniboss_room_indexes()
			var double_rooms := rooms.filter(func(i: int) -> bool: return _dungeon.is_double_miniboss(i))
			var seals := _dungeon.seal_rooms()
			var ok := rooms.size() == EncounterPlanner.miniboss_room_count(level, _run.level_seed()) and _dungeon.miniboss_count() == rooms.size() \
					and double_rooms.size() == EncounterPlanner.double_miniboss_room_count(level)
			for i in _dungeon.rooms.size():
				ok = ok and _dungeon.is_double_miniboss(i) == double_rooms.has(i) and (_dungeon.miniboss_scene(i) != null) == rooms.has(i)
			plan_ok = plan_ok and ok
			if not ok and detail.is_empty():
				detail = "level %d: %d rooms, %d doubles" % [level, rooms.size(), double_rooms.size()]
			var kinds := seals.values()
			seal_ok = seal_ok and seals.size() == EncounterPlanner.SEAL_SOURCES and kinds.count(&"treasure") == 2 \
					and kinds.count(&"miniboss") == 2 and kinds.count(&"champion") == 0
			for i in rooms:
				var pair := _dungeon.miniboss_pair(i)
				pair_ok = pair_ok and pair.size() == (2 if double_rooms.has(i) else 1) and (pair.size() == 1 or pair[0] != pair[1])
				var ids := _dungeon.reward_choices(i)
				reward_ok = reward_ok and ids.size() == 2 and ids[0] != ids[1] and ids.all(func(id: StringName) -> bool: return pool.has(id))
	_run.dungeon_level = 1
	_dungeon.miniboss_rooms = 0
	_check(plan_ok, "levels 1-10 (25 seeds each): miniboss and double-miniboss room counts follow the progression %s" % detail)
	_check(seal_ok, "levels 1-10: always exactly 4 seal sources (both puzzle rooms + 2 miniboss rooms, no champions)")
	_check(pair_ok, "double rooms hold two different minibosses (Brood Mother + Hexcaller), other rooms one")
	_check(reward_ok, "every miniboss room (double or not) offers one pick-1-of-2 choice of two different items")


## Shuffle-bag miniboss selection (Issue #51): even per level, no repeat before
## every type appeared, double rooms always mixed, deterministic per run seed,
## unbiased start, and a third roster entry needs no planner change.
func _test_shuffle_bag() -> void:
	var a := load("res://scenes/enemies/brood_mother.tscn") as PackedScene
	var b := load("res://scenes/enemies/hexcaller.tscn") as PackedScene
	var c := load("res://scenes/enemies/demon.tscn") as PackedScene  # stand-in third roster entry
	var roster: Array[PackedScene] = [a, b]
	var roster3: Array[PackedScene] = [a, b, c]
	var no_doubles: Array[int] = []
	var bag_ok := true
	for types in [2, 3, 4]:
		for s in 100:
			var draws := EncounterPlanner.miniboss_bag(types, 40, s)
			for start in range(0, 40 - types + 1, types):
				var seen := {}
				for t in draws.slice(start, start + types):
					seen[t] = true
				bag_ok = bag_ok and seen.size() == types
			for k in range(1, draws.size()):
				bag_ok = bag_ok and draws[k] != draws[k - 1]
	_check(bag_ok, "shuffle bag: every bag holds each type once and no type follows itself (2-4 types, 100 seeds)")

	var even_ok := true
	var double_ok := true
	var first_counts := {0: 0, 1: 0}
	var extra := {0: 0, 1: 0}
	var detail := ""
	for s in 200:
		var run_seed := 7000 + s
		for level in range(1, 8):
			var level_seed := EncounterPlanner.level_seed(run_seed, level)
			var count := EncounterPlanner.miniboss_room_count(level, level_seed)
			var rooms: Array[int] = []
			rooms.assign(range(count))
			var doubles: Array[int] = []
			if EncounterPlanner.double_miniboss_room_count(level) > 0:
				doubles.append(rooms[s % count])
			var plan := EncounterPlanner.assign_minibosses(rooms, doubles, roster, run_seed, level)
			var per := {a: 0, b: 0}
			for i in rooms:
				var picked: Array = plan[i]
				for scene in picked:
					per[scene] += 1
				if doubles.has(i):
					double_ok = double_ok and picked.size() == 2 and picked[0] != picked[1]
				else:
					double_ok = double_ok and picked.size() == 1
			if absi(per[a] - per[b]) > 1 and detail.is_empty():
				detail = " (seed %d level %d: %d / %d)" % [run_seed, level, per[a], per[b]]
			even_ok = even_ok and absi(per[a] - per[b]) <= 1
			if level == 1:
				first_counts[0 if (plan[rooms[0]] as Array)[0] == a else 1] += 1
				extra[0 if per[a] > per[b] else 1] += 1
	_check(even_ok, "2-type roster: per-level counts differ by at most 1 on levels 1-7 (200 runs)%s" % detail)
	_check(double_ok, "double rooms always get two different minibosses, single rooms one")
	_check(first_counts[0] > 60 and first_counts[1] > 60 and extra[0] > 60 and extra[1] > 60,
			"no selection bias: first type %d / %d, level-1 extra encounter %d / %d (200 runs)"
			% [first_counts[0], first_counts[1], extra[0], extra[1]])

	# The bag continues across levels: level 1 ends with the type level 2 must not start with.
	var carry_ok := true
	for s in 100:
		var run_seed := 8000 + s
		var l1: Array[int] = []
		l1.assign(range(3))
		var l2 := l1.duplicate()
		var p1 := EncounterPlanner.assign_minibosses(l1, no_doubles, roster, run_seed, 1)
		var p2 := EncounterPlanner.assign_minibosses(l2, no_doubles, roster, run_seed, 2)
		carry_ok = carry_ok and (p1[2] as Array)[0] != (p2[0] as Array)[0]
	_check(carry_ok, "the bag carries over: level 2 never starts with the type level 1 ended with")

	var rooms4: Array[int] = [3, 8, 12, 17]
	var dbl: Array[int] = [8]
	var once := EncounterPlanner.assign_minibosses(rooms4, dbl, roster3, 4242, 4)
	var again := EncounterPlanner.assign_minibosses(rooms4, dbl, roster3, 4242, 4)
	var used := {}
	for i in rooms4:
		for scene in once[i]:
			used[scene] = true
	_check(str(once) == str(again) and used.size() == 3 and (once[8] as Array).size() == 2 and once[8][0] != once[8][1],
			"3-type roster: deterministic per seed, all three types used on a 5-draw level, mixed double room")


## A double-miniboss room on dungeon level `level`: both minibosses spawn with
## 0.6x HP, the Brood Mother capped at 2 summons and the Hexcaller's opening
## delayed; XP and gold are split exactly, bonus gold and the reward choice once.
func _test_double_room(level: int) -> void:
	_run.dungeon_level = level
	_dungeon._plan_level()
	var double_rooms := _dungeon.miniboss_room_indexes().filter(func(i: int) -> bool: return _dungeon.is_double_miniboss(i))
	_check(double_rooms.size() == EncounterPlanner.double_miniboss_room_count(level), "level %d: %d double room(s) planned" % [level, double_rooms.size()])
	if double_rooms.is_empty():
		return
	var index: int = double_rooms[0]
	var lineup := _dungeon.room_lineup(index)
	var lineup_xp := EncounterPlanner.lineup_xp(_mapped(lineup, level))
	var lineup_gold := EncounterPlanner.lineup_gold(_mapped(lineup, level))
	_dungeon.enter_room(index, _dungeon.entry_door(index))
	await _frames(2)
	var room := _dungeon.current_room
	var bosses: Array = _enemies(room).filter(func(e: Node) -> bool: return e is Miniboss)
	_check(bosses.size() == 2 and _enemies(room).size() == 2, "level %d double room: exactly two minibosses, nothing else" % level)
	if bosses.size() != 2:
		return
	# Roster-agnostic (Issue #51 Stage 2b: Brood Mother, Hexcaller and Water Caster): two different types.
	var first: Miniboss = bosses[0]
	var second: Miniboss = bosses[1]
	_check(first.scene_file_path != second.scene_file_path,
			"level %d double room: two different minibosses (%s and %s)" % [level, first.display_name, second.display_name])
	var xp_sum: int = first.xp_reward + second.xp_reward
	var gold_sum: int = first.currency_reward + second.currency_reward
	_check(xp_sum == lineup_xp and absi(first.xp_reward - second.xp_reward) <= 1,
			"level %d double room: XP split exactly (%d + %d = %d, line-up %d)" % [level, first.xp_reward, second.xp_reward, xp_sum, lineup_xp])
	var comp := _dungeon.miniboss_compensation_gold(index)
	_check(gold_sum == lineup_gold + comp + 2 * _dungeon.miniboss_bonus_gold
			and absi(first.currency_reward - second.currency_reward) <= 1,
			"level %d double room: line-up + omitted-extras gold split exactly, bonus per miniboss (%d + %d = %d + %d + 2 x %d)"
			% [level, first.currency_reward, second.currency_reward, lineup_gold, comp, _dungeon.miniboss_bonus_gold])
	# HP: base x 0.6 x the run's enemy HP scaling (same scaling as a single miniboss).
	var scaling := _run.enemy_health_multiplier() * _run.output_hp_modifier()
	var hp_ok := true
	for b: Miniboss in bosses:
		var base := (load(b.scene_file_path) as PackedScene).instantiate() as Miniboss
		hp_ok = hp_ok and is_equal_approx(b.health.max_health, (base.get_node(^"Health") as Health).max_health * _dungeon.double_health_factor * scaling)
		if b is BroodMother:
			hp_ok = hp_ok and (b as BroodMother).max_summons == _dungeon.double_max_summons
		elif b is Hexcaller:
			hp_ok = hp_ok and is_equal_approx(b.opening_delay, base.opening_delay + _dungeon.double_hexcaller_delay)
		base.free()
	_check(hp_ok, "level %d double room: 0.6x HP each, a Brood Mother max %d summons, a Hexcaller opens %.1f s later"
			% [level, _dungeon.double_max_summons, _dungeon.double_hexcaller_delay])
	var pickups := _pickups(room)
	_check(pickups.size() == 2 and pickups[0].item_id != pickups[1].item_id and pickups.all(func(p: ItemPickup) -> bool:
			return p.choice_group == &"miniboss_reward" and not p.visible), "level %d double room: one hidden pick-1-of-2 reward choice" % level)
	# Kill both: the room pays exactly the line-up XP (raw) and its gold + bonus once.
	_run.xp_multiplier_override = 1.0
	var xp_before := _total_xp()
	var gold_before := _run.currency
	var expected_gold := roundi(first.currency_reward * _run.gold_multiplier()) + roundi(second.currency_reward * _run.gold_multiplier())
	for b: Miniboss in bosses:
		b.take_damage(999999.0)
	await _wait_until(func() -> bool: return room.state == Room.State.CLEARED)
	await _frames(1)
	_check(room.state == Room.State.CLEARED and _total_xp() - xp_before == lineup_xp
			and _run.currency - gold_before == expected_gold,
			"level %d double room: clearing it grants exactly the line-up XP (%d) and the room's gold once (%d)"
			% [level, _total_xp() - xp_before, _run.currency - gold_before])
	_run.xp_multiplier_override = 0.0
	var shown := pickups.filter(func(p: ItemPickup) -> bool: return is_instance_valid(p) and p.visible)
	_check(shown.size() == 2 and shown[0].collect() and not shown[1].collect(), "level %d double room: only one of the two rewards can be taken" % level)
	await _frames(1)
	_dungeon.enter_room(_dungeon.start_room)
	await _frames(1)
	_dungeon.enter_room(index)
	await _frames(2)
	_check(_dungeon.current_room.state == Room.State.CLEARED and _enemies(_dungeon.current_room).is_empty()
			and _pickups(_dungeon.current_room).is_empty(), "level %d double room: revisit gives no respawn and no second reward" % level)
	_run.dungeon_level = 1


## Issue #51 economy on dungeon level `level` at difficulty `tier`. Every miniboss
## room pays its line-up gold + the gold of the extra enemies it omits (once per
## room) + miniboss_bonus_gold per miniboss, and its line-up XP unchanged. One room
## is cleared (killing blows repeated) to check the gold multiplier is applied
## once per kill and nothing is granted twice. A normal tier-2 room must spawn
## exactly the extras the compensation assumes. Returns a signature of the plan.
func _test_miniboss_economy(tier: int, level: int) -> String:
	_run.difficulty = tier
	_run.dungeon_level = level
	_dungeon._plan_level()
	var label := "%s L%d" % [Difficulty.display_name(tier), level]
	var bonus := _dungeon.miniboss_bonus_gold
	var rooms_ok := true
	var any_comp := false
	var parts: Array[String] = []
	var target := -1
	for i in _dungeon.miniboss_room_indexes():
		_dungeon.enter_room(i)
		await _frames(2)
		var bosses: Array = _enemies(_dungeon.current_room).filter(func(e: Node) -> bool: return e is Miniboss)
		var lineup := _dungeon.room_lineup(i)
		var extras: Array = _expected_extras(i, level)
		var gold_sum := 0
		var xp_sum := 0
		for b: Miniboss in bosses:
			gold_sum += b.currency_reward
			xp_sum += b.xp_reward
		rooms_ok = rooms_ok and bosses.size() == _dungeon.miniboss_pair(i).size() \
				and _dungeon.miniboss_compensation_gold(i) == extras[1] \
				and gold_sum == EncounterPlanner.lineup_gold(_mapped(lineup, level)) + extras[1] + bosses.size() * bonus \
				and xp_sum == EncounterPlanner.lineup_xp(_mapped(lineup, level))
		any_comp = any_comp or extras[1] > 0
		parts.append("%d:%d:%d" % [i, extras[1], gold_sum])
		if target < 0 or bosses.size() > 1:
			target = i
	_check(rooms_ok, "%s economy: each miniboss room = line-up XP; line-up gold + omitted extras (once per room) + %d per miniboss" % [label, bonus])
	_check(any_comp, "%s economy: omitted extra enemies are compensated (%s)" % [label, ", ".join(parts)])

	# Clear one room (the double room if there is one): gold multiplier once per kill, nothing twice.
	_dungeon.enter_room(target)
	await _frames(2)
	var room := _dungeon.current_room
	room.start_encounter()
	await _frames(1)
	var bosses: Array = _enemies(room).filter(func(e: Node) -> bool: return e is Miniboss)
	var mult := _run.gold_multiplier()
	var expected_gold := 0
	for b: Miniboss in bosses:
		expected_gold += roundi(b.currency_reward * mult)
	_run.xp_multiplier_override = 1.0
	var xp_before := _total_xp()
	var gold_before := _run.currency
	for b: Miniboss in bosses:
		b.take_damage(999999.0)
		b.take_damage(999999.0)
	await _wait_until(func() -> bool: return room.state == Room.State.CLEARED)
	await _frames(3)
	var gained := _run.currency - gold_before
	_check(is_equal_approx(mult, Difficulty.data(tier)["gold"]) and gained == expected_gold
			and _total_xp() - xp_before == EncounterPlanner.lineup_xp(_mapped(_dungeon.room_lineup(target), level)),
			"%s economy: clearing a %s room grants its gold x%.2f once (%d) and its line-up XP" % [label, "double" if bosses.size() > 1 else "single", mult, gained])
	_run.xp_multiplier_override = 0.0
	_dungeon.enter_room(_dungeon.start_room)
	await _frames(1)
	_dungeon.enter_room(target)
	await _frames(2)
	_check(_run.currency - gold_before == gained and _enemies(_dungeon.current_room).is_empty(),
			"%s economy: repeated killing blows and a revisit grant nothing more" % label)

	# A normal tier-2 room spawns exactly the extras the compensation rule assumes.
	var normal := -1
	for i in _dungeon.rooms.size():
		var spec := _dungeon.rooms[i]
		if spec.required_level >= 2 and not spec.is_boss and not spec.is_treasure() and not spec.enemies.is_empty() \
				and _dungeon.miniboss_scene(i) == null and not _dungeon.is_visited(i):
			normal = i
			break
	if normal >= 0:
		var extras: Array = _expected_extras(normal, level)
		var placed := _scene_enemy_gold(normal, level)
		_dungeon.enter_room(normal)
		await _frames(2)
		var total := 0
		for e: Enemy in _enemies(_dungeon.current_room):
			total += e.currency_reward
		var pool_gold := EncounterPlanner.lineup_gold(_mapped(_dungeon.room_lineup(normal), level))
		_check(_dungeon.miniboss_compensation_gold(normal) == 0 and total == pool_gold + placed + extras[1],
				"%s economy: a normal room is unchanged and spawns the extras the rule assumes (%d extras, %d gold)" % [label, extras[0], extras[1]])
	_run.difficulty = Difficulty.Tier.NORMAL
	_run.dungeon_level = 1
	return "|".join(parts)


## Caverns biome (level 4+) reward consistency for a single (`double` false) or
## double miniboss room whose line-up holds an enemy the biome swaps (Giant Goblin
## 1 XP / 5 gold -> Blood Monster 4 XP / 12 gold): the minibosses' XP and gold come
## from the swapped line-up - the enemies the normal room would spawn - split
## exactly; the omitted extras' gold from the same line-up once per room; 40 gold
## (no XP) per miniboss. Clearing the room grants the XP and gold once.
func _test_caverns_rewards(double: bool) -> void:
	var level := 4
	var kind := "double" if double else "single"
	_run.dungeon_level = level
	_check(Biomes.biome_id(level) == &"caverns", "setup: level %d is in the Caverns biome" % level)
	var index := -1
	for s in 200:
		_run.run_seed = 6000 + s
		_dungeon._plan_level()
		for i in _dungeon.miniboss_room_indexes():
			var lineup := _dungeon.room_lineup(i)
			if _dungeon.is_double_miniboss(i) == double and i != _dungeon.start_room \
					and EncounterPlanner.lineup_xp(_mapped(lineup, level)) != EncounterPlanner.lineup_xp(lineup):
				index = i
				break
		if index >= 0:
			break
	_check(index >= 0, "setup: a Caverns %s miniboss room with a biome-swapped enemy (seed %d)" % [kind, _run.run_seed])
	if index < 0:
		_run.dungeon_level = 1
		return
	var lineup := _dungeon.room_lineup(index)
	var pool := _mapped(lineup, level)
	var extras: Array = _expected_extras(index, level)
	_dungeon.enter_room(index)
	await _frames(2)
	var room := _dungeon.current_room
	var bosses: Array = _enemies(room).filter(func(e: Node) -> bool: return e is Miniboss)
	var xp_sum := 0
	var gold_sum := 0
	var xps: Array[int] = []
	var golds: Array[int] = []
	for b: Miniboss in bosses:
		xp_sum += b.xp_reward
		gold_sum += b.currency_reward
		xps.append(b.xp_reward)
		golds.append(b.currency_reward)
	var count := 2 if double else 1
	var pool_xp := EncounterPlanner.lineup_xp(pool)
	var pool_gold := EncounterPlanner.lineup_gold(pool)
	var bonus := _dungeon.miniboss_bonus_gold
	_check(bosses.size() == count and xp_sum == pool_xp and xps.max() - xps.min() <= 1,
			"Caverns %s room: XP = swapped line-up %d (authored %d), split %s"
			% [kind, pool_xp, EncounterPlanner.lineup_xp(lineup), xps])
	_check(bosses.size() == count and gold_sum == pool_gold + extras[1] + count * bonus
			and golds.max() - golds.min() <= 1 and _dungeon.miniboss_compensation_gold(index) == extras[1],
			"Caverns %s room: gold = swapped line-up %d (authored %d) + extras %d once + %d x %d bonus, split %s"
			% [kind, pool_gold, EncounterPlanner.lineup_gold(lineup), extras[1], count, bonus, golds])
	room.start_encounter()
	await _frames(1)
	var mult := _run.gold_multiplier()
	var expected_gold := 0
	for g in golds:
		expected_gold += roundi(g * mult)
	_run.xp_multiplier_override = 1.0
	var xp_before := _total_xp()
	var gold_before := _run.currency
	for b: Miniboss in bosses:
		b.take_damage(999999.0)
		b.take_damage(999999.0)
	await _wait_until(func() -> bool: return room.state == Room.State.CLEARED)
	await _frames(3)
	_check(_total_xp() - xp_before == pool_xp and _run.currency - gold_before == expected_gold,
			"Caverns %s room: clearing grants the swapped line-up XP (%d) and gold (%d) once" % [kind, _total_xp() - xp_before, _run.currency - gold_before])
	_run.xp_multiplier_override = 0.0
	_run.dungeon_level = 1


## Levels 1-3 have no biome enemy swaps, so a miniboss room's resolved line-up is
## its authored one there and the rewards are unchanged by the Caverns fixes.
func _test_early_levels_unswapped() -> void:
	var ok := true
	var checked := 0
	for level in range(1, 4):
		_run.dungeon_level = level
		for s in 30:
			_run.run_seed = 6500 + s
			_dungeon._plan_level()
			for i in _dungeon.miniboss_room_indexes():
				var lineup := _dungeon.room_lineup(i)
				var pool := _mapped(lineup, level)
				ok = ok and str(pool.map(func(p: PackedScene) -> String: return p.resource_path)) \
						== str(lineup.map(func(p: PackedScene) -> String: return p.resource_path))
				checked += 1
	_run.dungeon_level = 1
	_check(ok and checked > 0, "levels 1-3: miniboss line-ups are never biome-swapped, rewards unchanged (%d rooms)" % checked)


## [count, unscaled gold] of the extra enemies room `index` gets as a normal room
## on dungeon level `level` (computed on a fresh instance of its room scene).
func _expected_extras(index: int, level: int) -> Array:
	var spec := _dungeon.rooms[index]
	var pool := _mapped(_dungeon.room_lineup(index), level)
	var inst := Biomes.map_scene(spec.scene, level, "room_map").instantiate() as Room
	var count := _run.extra_room_enemies(spec.required_level, inst.safe_extra_points(pool.size()).size())
	inst.free()
	var gold := 0
	for k in count:
		gold += EncounterPlanner.scene_gold(pool[k % pool.size()])
	return [count, gold]


## Gold of the enemies placed in room `index`'s scene itself.
func _scene_enemy_gold(index: int, level: int) -> int:
	var inst := Biomes.map_scene(_dungeon.rooms[index].scene, level, "room_map").instantiate()
	var gold := 0
	for e in inst.get_node(^"Enemies").get_children():
		gold += (e as Enemy).currency_reward
	inst.free()
	return gold


func _mapped(lineup: Array[PackedScene], level: int) -> Array[PackedScene]:
	var pool: Array[PackedScene] = []
	for scene in lineup:
		pool.append(Biomes.map_scene(scene, level, "enemy_map"))
	return pool


## Total XP earned so far (levels gained + current XP; xp_per_level * level per level).
func _total_xp() -> int:
	var total := _run.xp
	for l in range(1, _run.level):
		total += _run.xp_per_level * l
	return total


## A miniboss room that is a seal source (-1 if none).
func _seal_miniboss_room() -> int:
	for i in _dungeon.miniboss_room_indexes():
		if _dungeon.seal_rooms().get(i) == &"miniboss":
			return i
	return -1


# --- Helpers -----------------------------------------------------------------------

func _miniboss_room(type: Variant) -> int:
	for i in _dungeon.rooms.size():
		var scene := _dungeon.miniboss_scene(i)
		if scene == null:
			continue
		var inst := scene.instantiate()
		var match_type := is_instance_of(inst, type)
		inst.free()
		if match_type:
			return i
	return -1


func _enter_miniboss(index: int) -> Miniboss:
	if index < 0:
		return null
	_dungeon.enter_room(index)
	await _frames(2)
	_dungeon.current_room.start_encounter()
	await _frames(1)
	return _miniboss_in(_dungeon.current_room)


func _miniboss_in(room: Room) -> Miniboss:
	for e in _enemies(room):
		if e is Miniboss:
			return e
	return null


## Puts the Mage at `offset` from `boss` and lets physics settle.
func _park_mage(boss: Node2D, offset: Vector2) -> void:
	_mage.global_position = boss.global_position + offset
	_mage.velocity = Vector2.ZERO


func _hazards_of(source: Node) -> Array:
	return get_nodes_in_group(&"floor_hazards").filter(func(h: FloorHazard) -> bool:
		return h.source == source and not h.is_queued_for_deletion())


func _bolts_of(source: Node) -> Array:
	return current_scene.get_children().filter(func(n: Node) -> bool:
		return n is Projectile and (n as Projectile).source == source and not n.is_queued_for_deletion())


func _pickups(room: Room) -> Array:
	return room.get_node(^"Decor").get_children().filter(func(n: Node) -> bool: return n is ItemPickup and not n.is_queued_for_deletion())


func _enemies(room: Room) -> Array:
	return room.get_node(^"Enemies").get_children().filter(func(n: Node) -> bool:
		return n is Enemy and not n.is_queued_for_deletion())


func _miniboss_map() -> String:
	var parts: Array[String] = []
	for i in _dungeon.rooms.size():
		if _dungeon.miniboss_scene(i):
			parts.append("%d:%s:%s" % [i, _dungeon.miniboss_scene(i).resource_path, _dungeon.reward_choices(i)])
	return "|".join(parts)


func _adjacent(a: int, b: int) -> bool:
	var d := _dungeon.rooms[a].cell - _dungeon.rooms[b].cell
	return absi(d.x) + absi(d.y) == 1


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


func _physics(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await physics_frame
		elapsed += 1.0 / Engine.physics_ticks_per_second


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
