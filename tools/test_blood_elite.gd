extends SceneTree
## Headless check of Issue #58 Stage 3, the Blood Monster Elite
## (scenes/enemies/blood_monster_elite.tscn): stats vs the unchanged regular
## Blood Monster, seeded promotion (never below ELITE_MIN_LEVEL, at most one per
## room, never in boss / treasure / miniboss / champion rooms), Blood Frenzy
## (one telegraphed Mage-only nova, faster dash, windup unchanged), the elite
## death blast (bigger, longer warning, once), safe chain reactions and
## exactly-once rewards.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_blood_elite.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SEED := 4242
const SCENE := "res://scenes/dungeon/dungeon.tscn"
const REGULAR := preload("res://scenes/enemies/blood_monster.tscn")
const ELITE := preload("res://scenes/enemies/blood_monster_elite.tscn")

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_test_stats()
	_test_planner()
	RunState.seed_override = SEED
	change_scene_to_file(SCENE)
	await _wait_for_scene(0)
	if _dungeon == null:
		_check(false, "dungeon scene loaded")
	else:
		_check(_dungeon.blood_elite_scene == ELITE, "the Dungeon uses the Elite scene")
		_test_promotion(1)
		await _test_frenzy_and_nova()
		await _test_death_and_rewards()
		await _test_chain()
		await _next_level()
		_test_promotion(2)
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	RunState.seed_override = 0
	quit(1 if _failures > 0 else 0)


func _test_stats() -> void:
	var r := REGULAR.instantiate() as BloodMonster
	var e := ELITE.instantiate() as BloodMonsterElite
	root.add_child(r)
	root.add_child(e)
	_check(not r is BloodMonsterElite and r.health.max_health == 90.0 and r.xp_reward == 4 and r.currency_reward == 12
			and r.death_blast_radius == 100.0 and r.death_blast_delay == 0.6 and r.special_windup == 0.9,
			"regular Blood Monster unchanged (90 HP, 4 XP, 12 gold, 100 px / 0.6 s blast)")
	_check(e is BloodMonster and e.elite and e.health.max_health > r.health.max_health * 2.0
			and e.xp_reward > r.xp_reward * 2 and e.currency_reward > r.currency_reward * 2,
			"Elite: >2x HP and rewards (%d HP, %d XP, %d gold)" % [e.health.max_health, e.xp_reward, e.currency_reward])
	_check(e.death_blast_radius > r.death_blast_radius and e.death_blast_delay > r.death_blast_delay
			and e.special_windup >= r.special_windup and e.sprite_scale > r.sprite_scale,
			"Elite: bigger blast with a longer warning, same readable windup, bigger body")
	_check(e.nova_delay >= 0.8 and e.nova_radius > 0.0 and not e.frenzied, "Elite: nova has a readable warning, starts calm")
	r.free()
	e.free()


func _test_planner() -> void:
	var below := true
	var picked := 0
	var ok := true
	for s in 400:
		below = below and EncounterPlanner.elite_pick(3, EncounterPlanner.ELITE_MIN_LEVEL - 1, s) == -1
		var p := EncounterPlanner.elite_pick(3, EncounterPlanner.ELITE_MIN_LEVEL, s)
		ok = ok and p >= -1 and p < 3 and p == EncounterPlanner.elite_pick(3, EncounterPlanner.ELITE_MIN_LEVEL, s)
		if p >= 0:
			picked += 1
	_check(below, "no Elites below dungeon level %d" % EncounterPlanner.ELITE_MIN_LEVEL)
	_check(ok and EncounterPlanner.elite_pick(0, 5, 1) == -1, "elite picks are deterministic, in range, none without Blood Monsters")
	var rate := picked / 400.0
	_check(absf(rate - EncounterPlanner.ELITE_ROOM_CHANCE) < 0.08, "promotion rate ~%.0f%% (%.0f%%)" % [EncounterPlanner.ELITE_ROOM_CHANCE * 100, rate * 100])


## Builds every room of the current level: Elites only where allowed, at most one per room.
func _test_promotion(level: int) -> void:
	var total := 0
	var allowed := true
	for i in _dungeon.rooms.size():
		var room := _dungeon._get_room(i)
		var elites := room.find_children("*", "BloodMonsterElite", true, false)
		total += elites.size()
		var spec := _dungeon.rooms[i]
		if elites.size() > 1 or (not elites.is_empty() and (spec.is_boss or spec.is_treasure()
				or _dungeon.miniboss_room_indexes().has(i) or _dungeon.seal_rooms().get(i) == &"champion")):
			allowed = false
	_check(allowed, "L%d: at most one Elite per room, never in boss / treasure / miniboss / champion rooms" % level)
	if level < EncounterPlanner.ELITE_MIN_LEVEL:
		_check(total == 0, "L%d: no Elites" % level)
	else:
		_check(total > 0, "L%d: Elites are promoted on this seed (%d)" % [level, total])
		# Each eligible room follows its seeded pick exactly (1:1 swap, so the
		# room's Blood Monster count is the original candidate count).
		var seeded := true
		for i in _dungeon.rooms.size():
			var spec := _dungeon.rooms[i]
			if spec.is_boss or spec.is_treasure() or _dungeon.miniboss_room_indexes().has(i) \
					or _dungeon.seal_rooms().get(i) == &"champion":
				continue
			var room := _dungeon._get_room(i)
			var monsters := room.get_node(^"Enemies").get_children().filter(func(n: Node) -> bool: return n is BloodMonster).size()
			var has_elite := not room.find_children("*", "BloodMonsterElite", true, false).is_empty()
			var pick := EncounterPlanner.elite_pick(monsters, level, hash([_run.level_seed(), i]))
			seeded = seeded and has_elite == (pick >= 0)
		_check(seeded, "L%d: every room's Elite matches its seeded pick" % level)


## Adds an Elite / regular Blood Monster to the current (fighting) room, scaled and registered.
func _spawn(scene: PackedScene, pos: Vector2) -> BloodMonster:
	var m := scene.instantiate() as BloodMonster
	_dungeon.current_room.add_summoned_enemy(m, pos)
	m.summoned = false  # a real encounter enemy: grants rewards
	return m


func _fight_room() -> void:
	var index := -1
	for i in _dungeon.rooms.size():
		var spec := _dungeon.rooms[i]
		if i != _dungeon.start_room and not spec.is_boss and not spec.is_treasure() and not spec.enemies.is_empty() \
				and not _dungeon.miniboss_room_indexes().has(i) and spec.required_level <= 1:
			index = i
			break
	_dungeon.enter_room(index, _dungeon.entry_door(index))
	await _frames(3)
	# Clear the planned enemies out of the way (far corner) so only test monsters matter.
	for e in _dungeon.current_room.get_node(^"Enemies").get_children():
		if e is Enemy:
			(e as Enemy).global_position = Vector2(60, 60)
			(e as Enemy).process_mode = Node.PROCESS_MODE_DISABLED


func _test_frenzy_and_nova() -> void:
	await _fight_room()
	_mage.global_position = Vector2(900, 500)
	var e := _spawn(ELITE, Vector2(400, 320)) as BloodMonsterElite
	var bystander := _spawn(REGULAR, Vector2(440, 320))
	bystander.process_mode = Node.PROCESS_MODE_DISABLED
	e.process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(1)
	var windup := e.special_windup
	var speed := e.dash_speed
	e.take_damage(e.health.max_health * 0.3)
	_check(not e.frenzied and e.nova == null, "no frenzy above half HP")
	e.take_damage(e.health.max_health * 0.25)
	_check(e.frenzied and e.nova != null and is_equal_approx(e.dash_speed, speed * e.frenzy_dash_speed_mult)
			and e.special_windup == windup, "frenzy at half HP: nova, faster dash, windup (warning) unchanged")
	var nova := e.nova
	e.take_damage(1.0)
	_check(e.nova == nova, "only one nova per Elite")
	# Fairness: the Mage stands in the nova; nothing happens before the warning ends.
	_mage.global_position = e.global_position + Vector2(30, 0)
	var hp := _mage.health.current
	var b_hp := bystander.health.current
	var nova_damage := nova.damage
	var nova_delay := nova.delay
	await _seconds(nova_delay * 0.5)
	_check(_mage.health.current == hp and nova.phase == FloorHazard.Phase.TELEGRAPH, "nova warns before it hits")
	await _seconds(nova_delay * 0.5 + 0.25)
	var expected := nova_damage * _mage.damage_taken_multiplier
	_check(is_equal_approx(hp - _mage.health.current, expected), "nova hits the Mage once (%.1f)" % (hp - _mage.health.current))
	_check(bystander.health.current == b_hp, "nova never damages enemies (no chain from a nova)")
	_mage.health.increase_max_health(0.0, 999.0)
	_mage.global_position = Vector2(900, 500)


func _test_death_and_rewards() -> void:
	var e := _spawn(ELITE, Vector2(600, 200)) as BloodMonsterElite
	e.process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(1)
	var gold := _run.currency
	var kills := _run.enemies_defeated
	var elite_gold := roundi(e.currency_reward * _run.gold_multiplier())
	var deaths := [0]
	e.died.connect(func() -> void: deaths[0] += 1)
	e.take_damage(999999.0)
	e.take_damage(999999.0)
	e.health.died.emit()  # a duplicate death signal must not repeat anything
	var blast := e.death_blast
	_check(blast != null and blast.radius == 150.0 and blast.delay == 1.0
			and blast.eruption_shake == CombatFeedback.Shake.HEAVY, "Elite leaves one big death blast (150 px, 1.0 s warning, heavy shake)")
	await _seconds(1.3)
	var blasts := _dungeon.current_room.find_children("*", "BloodBlast", true, false).filter(func(b: Node) -> bool:
		return (b as BloodBlast).excluded == e)
	_check(deaths[0] == 1 and _run.enemies_defeated == kills + 1, "the Elite dies once")
	_check(_run.currency - gold == elite_gold and _run.currency - gold > 12,
			"Elite rewards granted exactly once (+%d gold)" % (_run.currency - gold))
	_check(blasts.size() <= 1, "no second death blast")


func _test_chain() -> void:
	# An Elite blast kills a weakened regular Blood Monster, whose blast catches a third.
	var e := _spawn(ELITE, Vector2(300, 450)) as BloodMonsterElite
	var a := _spawn(REGULAR, Vector2(380, 450))
	var b := _spawn(REGULAR, Vector2(460, 450))
	for m in [e, a, b]:
		(m as Node).process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(1)
	a.health.current = 1.0
	b.health.current = 1.0
	_mage.global_position = Vector2(950, 120)
	var kills := _run.enemies_defeated
	var elite_gold := roundi(e.currency_reward * _run.gold_multiplier())
	var gold := _run.currency
	e.take_damage(999999.0)
	await _seconds(1.2)  # elite blast (1.0 s) kills a
	_check(not is_instance_valid(a) or a.dying, "the Elite blast kills a weakened Blood Monster")
	await _seconds(0.9)  # a's blast (0.6 s) kills b
	_check(not is_instance_valid(b) or b.dying, "the chain continues to the next Blood Monster")
	await _seconds(0.9)
	_check(_run.enemies_defeated == kills + 3, "three deaths, each counted once (%d)" % (_run.enemies_defeated - kills))
	var expected := elite_gold + 2 * roundi(12 * _run.gold_multiplier())
	_check(_run.currency - gold == expected, "chain rewards paid exactly once each (+%d, expected +%d)" % [_run.currency - gold, expected])
	var blasts := _dungeon.current_room.find_children("*", "BloodBlast", true, false)
	_check(blasts.size() <= 3, "the chain ends: at most one blast per monster (%d alive)" % blasts.size())
	_check(_mage.health.current > 0.0, "the Mage outside the blasts is unharmed")


## Ends the current level the way a boss kill + relic choice does and starts the next one.
func _next_level() -> void:
	var level := _run.dungeon_level
	_run.boss_defeated = true
	_run.choose_relic(&"wind_relic")
	_dungeon.victory = true
	_check(_dungeon.advance_level() and _run.dungeon_level == level + 1, "advanced to level %d" % (level + 1))
	await _frames(2)


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


func _seconds(s: float) -> void:
	await create_timer(s, false, true).timeout


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
