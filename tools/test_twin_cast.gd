extends SceneTree
## Headless check of the permanent Twin Cast anvil upgrade (4000 gold, sold from
## dungeon level 3, bought once EVER: the unlock is saved and applies to every
## later run; two projectiles of 70% damage per cast sharing one cooldown and
## one `cast` signal), of the flat x1.10 enemy damage factor and of boss bolts
## dealing 25% of the target's max HP.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_twin_cast.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENE := "res://scenes/dungeon/dungeon.tscn"
const BOSS := Vector2i(2, 0)
const GOBLIN_ROOM := Vector2i(0, 4)
const NORMAL := Difficulty.Tier.NORMAL
const HARD := Difficulty.Tier.HARD

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState
var _prog: ProgressionStore


## Stand-in target recording the damage it takes.
class Dummy extends Node2D:
	var taken := 0.0

	func take_damage(amount: float) -> void:
		taken += amount


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_prog = ProgressionStore.instance(self)
	_prog.clear_progress()
	_test_eligibility()
	_test_once_and_persistence()
	_test_no_other_multiplier()
	_test_enemy_damage_unit()
	await _test_casting()
	await _test_enemy_damage_scene()
	await _test_permanent_unlock()
	await _test_boss_bolts()
	_prog.clear_progress()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _new_run(dungeon_level: int, gold: int = 100000) -> RunState:
	var run := RunState.new()
	run.configure(NORMAL)
	run.dungeon_level = dungeon_level
	run.currency = gold
	run.level = MageLevels.cap(dungeon_level)
	return run


func _next_level(run: RunState) -> void:
	run.boss_defeated = true
	run.choose_relic(&"wind_relic")
	run.begin_next_level()
	run.level = maxi(run.level, MageLevels.cap(run.dungeon_level))


# --- Purchase rules ---------------------------------------------------------------------------

func _test_eligibility() -> void:
	var data: Dictionary = RunState.UPGRADES[&"twin_cast"]
	_check(data["prices"] == [4000] and data["max_stacks"] == 1 and data["permanent"] and data["min_dungeon_level"] == 3,
			"Twin Cast: 4000 gold, one stack, permanent, from dungeon level 3")
	var run := _new_run(1)
	_check(not run.can_purchase(&"twin_cast") and not run.purchase(&"twin_cast") and run.currency == 100000, "not sold on dungeon level 1")
	_next_level(run)
	_check(run.dungeon_level == 2 and not run.can_purchase(&"twin_cast"), "not sold on dungeon level 2")
	_next_level(run)
	_check(run.dungeon_level == 3 and run.can_purchase(&"twin_cast"), "sold from dungeon level 3")
	run.free()
	run = _new_run(3, 3999)
	_check(not run.can_purchase(&"twin_cast") and not run.purchase(&"twin_cast") and run.currency == 3999 and not run.has_twin_cast(),
			"3999 gold is not enough")
	run.currency = 4500
	_check(run.purchase(&"twin_cast") and run.currency == 500 and run.has_twin_cast(), "4000 gold is deducted exactly once (500 left)")
	run.free()
	run = _new_run(3)
	run.level = 6
	_check(not run.can_purchase(&"twin_cast"), "the Mage level gate of dungeon level 3 (Lv 7) also applies")
	run.free()


func _test_once_and_persistence() -> void:
	var run := _new_run(3)
	var gold := run.currency
	_check(run.purchase(&"twin_cast") and run.upgrade_stacks(&"twin_cast") == 1, "bought on level 3")
	_check(not run.purchase(&"twin_cast") and not run.can_purchase(&"twin_cast") and run.currency == gold - 4000
			and run.upgrade_stacks(&"twin_cast") == 1, "it cannot be bought a second time")
	_next_level(run)
	_check(run.dungeon_level == 4 and run.has_twin_cast() and run.upgrade_stacks(&"twin_cast") == 1 and not run.can_purchase(&"twin_cast"),
			"it persists across levels and is never restocked")
	_next_level(run)
	_check(run.has_twin_cast() and not run.can_purchase(&"twin_cast") and run.projectile_count() == 2, "still owned two levels later")
	run.free()


func _test_no_other_multiplier() -> void:
	var run := _new_run(3)
	_check(run.projectile_count() == 1 and is_equal_approx(run.projectile_damage_factor(), 1.0), "without Twin Cast: 1 projectile, factor 1.0")
	for id: StringName in [&"quick_cast", &"ember_core", &"vitality"]:
		for stack in 3:
			run.purchase(id)
			_next_level(run)
	run.claim_treasure(&"rune_sigil")
	run.boss_defeated = true
	run.choose_relic(&"ember_relic")
	run.collect_item(&"ember_shard")
	_check(run.projectile_count() == 1 and is_equal_approx(run.projectile_damage_factor(), 1.0),
			"Quick Cast, Ember Core, Vitality, Rune Sigil, relics and items never add projectiles")
	run.currency = 10000
	run.dungeon_level = 5
	run.purchase(&"twin_cast")
	run.changed.emit()
	run.changed.emit()
	_check(run.projectile_count() == 2 and is_equal_approx(run.projectile_damage_factor(), 0.7), "Twin Cast: exactly 2 projectiles at x0.7, stable under recalculation")
	run.free()


# --- Casting ---------------------------------------------------------------------------------------

func _projectiles() -> Array:
	return current_scene.get_children().filter(func(n: Node) -> bool: return n is Projectile and not n.is_queued_for_deletion())


func _test_casting() -> void:
	await _load_scene()
	var fire_ball := load("res://scenes/spells/fire_ball/fire_ball.tres") as Spell
	var caster := _mage.caster
	var casts := [0]
	caster.cast.connect(func(_p: Projectile) -> void: casts[0] += 1)
	var aim := caster.global_position + Vector2(200, 0)
	_check(caster.projectile_count == 1, "setup: one projectile per cast without Twin Cast")
	var single := caster.try_cast(aim)
	_check(single != null and _projectiles().size() == 1 and casts[0] == 1 and is_equal_approx(single.damage_factor, 1.0), "one projectile at full damage before Twin Cast")
	for p in _projectiles():
		p.free()
	caster._cooldown_left = 0.0
	# Buy Twin Cast through RunState with Ember Core / Quick Cast already owned.
	_run.dungeon_level = 3
	_run.currency = 20000
	_run.level = 7
	_run.purchased[&"ember_core"] = 2
	_run.purchased[&"quick_cast"] = 3
	_run.collected[&"ember_shard"] = 1
	_check(_run.purchase(&"twin_cast"), "setup: Twin Cast bought on level 3")
	_check(caster.projectile_count == 2 and is_equal_approx(caster.projectile_damage_factor, 0.7), "the Dungeon applies Twin Cast to the caster")
	_run.changed.emit()
	_run.changed.emit()
	_check(caster.projectile_count == 2, "recalculations never add projectiles")
	casts[0] = 0
	var first := caster.try_cast(aim)
	var shots := _projectiles()
	_check(first != null and shots.size() == 2 and casts[0] == 1, "one cast fires two projectiles and emits one cast signal")
	var cast_spell := caster.get_cast_spell()
	var expected_damage := fire_ball.damage * (1.0 + 0.05 * 6 + 0.5 + 0.15)
	_check(is_equal_approx(cast_spell.damage, expected_damage) and shots.all(func(p: Projectile) -> bool: return is_equal_approx(p.damage_factor, 0.7)),
			"projectiles carry the full damage bonuses (%.2f) and a 0.7 factor" % cast_spell.damage)
	_check(is_equal_approx(fire_ball.damage, 10.0), "the shared Fire Ball resource keeps its damage")
	var angle_a: float = (shots[0] as Projectile).direction.angle()
	var angle_b: float = (shots[1] as Projectile).direction.angle()
	_check(absf(rad_to_deg(angle_a - angle_b)) > 5.0 and absf(rad_to_deg(angle_a - angle_b)) < 12.0
			and is_equal_approx((angle_a + angle_b) / 2.0, 0.0), "slight spread (%.1f deg apart) around the aim" % absf(rad_to_deg(angle_a - angle_b)))
	for p: Projectile in shots:
		var dummy := Dummy.new()
		current_scene.add_child(dummy)
		p._on_body_entered(dummy)
		_check(is_equal_approx(dummy.taken, expected_damage * 0.7), "each projectile deals 70%% of %.2f = %.2f" % [expected_damage, dummy.taken])
		dummy.free()
	_check(is_equal_approx(caster.cooldown_left(), cast_spell.cooldown) and caster.try_cast(aim) == null and casts[0] == 1,
			"both projectiles share one cooldown: no second cast until it ends")
	_check(is_equal_approx(cast_spell.cooldown, fire_ball.cooldown * (1.0 - 0.15)), "Quick Cast still applies once (cooldown %.4f)" % cast_spell.cooldown)


# --- Permanent unlock ---------------------------------------------------------------------------------

func _test_permanent_unlock() -> void:
	_prog.clear_progress()
	await _load_scene()
	var twin := &"twin_cast"
	_check(not _prog.is_upgrade_unlocked(twin) and not _run.has_twin_cast() and _mage.caster.projectile_count == 1, "a new save starts without Twin Cast")
	_run.dungeon_level = 3
	_run.level = 7
	_run.currency = 5000
	_check(_run.purchase(twin) and _run.currency == 1000, "first purchase: 4000 gold deducted")
	_check(_prog.is_upgrade_unlocked(twin) and FileAccess.file_exists(ProgressionStore.TEST_SAVE_PATH), "the purchase unlocks it in the save")
	_check(_mage.caster.projectile_count == 2, "it is active at once")
	_run.boss_defeated = true
	_run.choose_relic(&"wind_relic")
	_run.begin_next_level()
	_check(_run.dungeon_level == 4 and _run.has_twin_cast() and _mage.caster.projectile_count == 2, "it persists across dungeon levels")
	# A new game session reads the save file.
	var session := ProgressionStore.new()
	session.save_path = ProgressionStore.TEST_SAVE_PATH
	session.load_progress()
	_check(session.is_upgrade_unlocked(twin), "a new game session loads the unlock from the save file")
	session.free()
	# A new run: unlocked, active, nothing to buy.
	await _load_scene()
	_check(_run.dungeon_level == 1 and _run.has_twin_cast() and _mage.caster.projectile_count == 2 and is_equal_approx(_mage.caster.projectile_damage_factor, 0.7),
			"a new run starts with Twin Cast already active")
	_run.dungeon_level = 3
	_run.level = 7
	_run.currency = 10000
	_check(not _run.can_purchase(twin) and not _run.purchase(twin) and _run.currency == 10000 and _run.upgrade_stacks(twin) == 1,
			"it cannot be bought (or charged) again")
	var station := _dungeon.current_room.get_node_or_null(^"Decor/UpgradeStation") as UpgradeStation
	_mage.global_position = station.global_position + Vector2(50, 0)
	await _frames(3)
	station.set_open(true)
	_check(station._menu_label.text.contains("Twin Cast") and station._menu_label.text.contains("[UNLOCKED]"), "the Anvil shows [UNLOCKED]")
	_check(not station.purchase(twin) and _run.currency == 10000, "the Anvil refuses another purchase")
	_run.boss_defeated = true
	_run.choose_relic(&"wind_relic")
	_run.begin_next_level()
	_check(not _run.can_purchase(twin) and _run.projectile_count() == 2, "it is not restocked on the next level")
	# Before it is unlocked, it is still sold from level 3 on.
	_prog.clear_progress()
	await _load_scene()
	_run.dungeon_level = 2
	_run.level = 10
	_run.currency = 5000
	_check(not _run.can_purchase(twin), "not sold on level 2 in a run without the unlock")
	_run.dungeon_level = 3
	_check(_run.can_purchase(twin), "sold from level 3 in a run without the unlock")
	# Practice runs may use an unlock but never create one.
	_prog.record_run(5, 3, 100.0, 60.0, NORMAL, &"dungeon")
	_check(_prog.select(NORMAL, &"", 3), "setup: practice run from level 3")
	await _load_scene()
	_run.currency = 5000
	_check(_run.is_replay and _run.purchase(twin) and _run.has_twin_cast() and not _prog.is_upgrade_unlocked(twin),
			"a practice run can buy it for itself but does not unlock it for later runs")


# --- Boss bolts: 25% of max HP -------------------------------------------------------------------------

func _test_boss_bolts() -> void:
	_prog.clear_progress()
	await _load_scene()
	_run.add_rewards(100000, 0)
	_grant_seals()
	var boss_room := await _enter(_dungeon.index_at(BOSS))
	var boss: Boss = null
	for e in boss_room.get_node(^"Enemies").get_children():
		if e is Boss:
			boss = e
	_check(boss != null and is_equal_approx(boss.volley_max_hp_fraction, 0.25), "the boss has a 25% max-HP bolt")
	var base_hp := _mage.health.max_health
	var lost := _boss_bolt_hit(boss)
	_check(is_equal_approx(lost, base_hp * 0.25), "a boss bolt deals 25%% of max HP at base HP (%.1f of %.0f)" % [lost, base_hp])
	_check(not is_equal_approx(lost, boss.volley_damage), "the flat volley_damage (%.1f) is not used" % boss.volley_damage)
	# Vitality: one real purchase, then two more stacks' worth of max HP.
	_run.currency = 1000
	_check(_run.purchase(&"vitality"), "setup: Vitality bought")
	_mage.health.increase_max_health(40.0, 40.0)
	var max_hp := _mage.health.max_health
	_check(is_equal_approx(max_hp, base_hp + 60.0), "setup: max HP with 3 Vitality stacks (%.0f)" % max_hp)
	_mage.health.increase_max_health(0.0, max_hp)
	lost = _boss_bolt_hit(boss)
	_check(is_equal_approx(lost, max_hp * 0.25), "with Vitality the bolt deals 25%% of the new max HP (%.1f of %.0f)" % [lost, max_hp])
	# A wounded Mage still loses 25% of MAX HP, not of current HP.
	_mage.health.take_damage(max_hp * 0.4)
	var wounded := _mage.health.current
	lost = _boss_bolt_hit(boss)
	_check(is_equal_approx(lost, max_hp * 0.25) and is_equal_approx(_mage.health.current, wounded - lost), "the bolt uses max HP, not current HP")
	_mage.health.increase_max_health(0.0, max_hp)
	# Scaling does not change the bolt.
	_run.dungeon_level = 3
	boss.volley_damage *= 5.0
	_check(is_equal_approx(_boss_bolt_hit(boss), max_hp * 0.25), "difficulty / level / global damage factors do not change it")
	_mage.health.increase_max_health(0.0, max_hp)
	# Other damage sources are untouched.
	var shot_ranged := await _ranged_shot()
	_check(shot_ranged != null and is_zero_approx(shot_ranged.max_hp_fraction), "ordinary enemy projectiles have no max-HP fraction")
	var before := _mage.health.current
	shot_ranged._on_body_entered(_mage)
	_check(is_equal_approx(before - _mage.health.current, shot_ranged.spell.damage), "an ordinary enemy projectile still deals its flat damage (%.1f)" % shot_ranged.spell.damage)
	_mage.health.increase_max_health(0.0, max_hp)
	var warden := (load("res://scenes/enemies/abyss_warden.tscn") as PackedScene).instantiate() as Boss
	_check(is_equal_approx(boss.slam_damage, warden.slam_damage * 1.10) and is_equal_approx(boss.contact_damage, warden.contact_damage * 1.10),
			"boss slam (%.1f) and contact (%.1f) damage are unchanged by the bolt rule" % [boss.slam_damage, boss.contact_damage])
	warden.free()


## Fires one boss bolt at the Mage and returns the HP lost.
func _boss_bolt_hit(boss: Boss) -> float:
	var shot := boss._fire(Vector2.RIGHT)
	var before := _mage.health.current
	shot._on_body_entered(_mage)
	return before - _mage.health.current


func _ranged_shot() -> Projectile:
	for i in _dungeon.rooms.size():
		var spec := _dungeon.rooms[i]
		if not spec.is_boss and _dungeon.room_lineup(i).any(func(s: PackedScene) -> bool: return s.resource_path.ends_with("demon_caster.tscn")):
			var room := await _enter(i)
			for e in room.get_node(^"Enemies").get_children():
				if e is RangedEnemy:
					return (e as RangedEnemy).fire(_mage.global_position)
	return null


# --- Enemy damage -----------------------------------------------------------------------------------

func _test_enemy_damage_unit() -> void:
	_check(is_equal_approx(RunState.ENEMY_DAMAGE_FACTOR, 1.10), "enemy damage factor is x1.10")
	var run := RunState.new()
	run.configure(NORMAL)
	var values: Array[float] = []
	for d in [1, 2, 3]:
		run.dungeon_level = d
		values.append(run.enemy_damage_multiplier())
	_check(is_equal_approx(values[0], 1.10) and is_equal_approx(values[1], 1.06 * 1.10) and is_equal_approx(values[2], 1.12 * 1.10),
			"enemy damage = 1.10 x dungeon-level scaling (+6%%/level): %s" % [values])
	_check(is_equal_approx(LevelScaling.enemy_damage(3), 1.12) and is_equal_approx(LevelScaling.enemy_health(3), 1.5) and is_equal_approx(LevelScaling.enemy_pace(3), 1.04),
			"level scaling constants are unchanged (damage, HP, speed)")
	_check(is_equal_approx(run.enemy_pace_multiplier(), LevelScaling.enemy_pace(3)) and is_equal_approx(run.enemy_health_multiplier(), 1.5),
			"enemy HP and speed multipliers do not include the damage factor")
	run.free()
	run = RunState.new()
	run.configure(HARD)
	_check(is_equal_approx(run.enemy_damage_multiplier(), 1.25 * 1.10) and is_equal_approx(run.enemy_damage_multiplier(true), 1.25 * 1.10),
			"Hard stacks with the factor once (x1.25 x 1.10)")
	run.free()
	run = RunState.new()
	run.configure(NORMAL, &"hunters_mark")
	_check(is_equal_approx(run.enemy_damage_multiplier(true), 1.10 * 1.3) and is_equal_approx(run.enemy_damage_multiplier(false), 1.10),
			"Pact modifiers multiply on top (Hunter's Mark: elites x1.3)")
	run.free()
	run = RunState.new()
	run.configure(NORMAL)
	_check(is_equal_approx(run.gold_multiplier(), 1.0) and run.xp_multiplier() > 0.0, "gold and XP are untouched")
	run.free()


func _test_enemy_damage_scene() -> void:
	_prog.clear_progress()  # an earlier test unlocked Twin Cast, which would add the output HP modifier
	await _load_scene()
	var goblin := _stats("res://scenes/enemies/giant_goblin.tscn")
	var room := await _enter(_dungeon.index_at(GOBLIN_ROOM))
	# Spawn order is seeded (EncounterPlanner): check the room's first goblin.
	var enemy := room.get_node(^"Enemies").get_child(0) as Enemy
	for child in room.get_node(^"Enemies").get_children():
		if child.scene_file_path.ends_with("giant_goblin.tscn"):
			enemy = child as Enemy
			break
	_check(is_equal_approx(enemy.contact_damage, goblin["damage"] * 1.10), "a regular enemy deals 10%% more (%.2f -> %.2f)" % [goblin["damage"], enemy.contact_damage])
	_check(is_equal_approx(enemy.health.max_health, goblin["hp"]) and is_equal_approx(enemy.speed, goblin["speed"])
			and is_equal_approx(enemy.attack_cooldown, goblin["cooldown"]) and enemy.xp_reward == goblin["xp"] and enemy.currency_reward == goblin["gold"],
			"HP, speed, attack cooldown, XP and gold are unchanged")
	var caster_base := (load("res://scenes/enemies/demon_caster.tscn") as PackedScene).instantiate() as RangedEnemy
	var caster_damage := caster_base.projectile_damage
	caster_base.free()
	var found: RangedEnemy = null
	for i in _dungeon.rooms.size():
		# The run's planned line-up (EncounterPlanner may swap casters out of an authored room).
		if _dungeon.room_lineup(i).any(func(s: PackedScene) -> bool: return s.resource_path.ends_with("demon_caster.tscn")) and not _dungeon.rooms[i].is_boss:
			var r := await _enter(i)
			for e in r.get_node(^"Enemies").get_children():
				if e is RangedEnemy:
					found = e
					break
			break
	_check(found != null and is_equal_approx(found.projectile_damage, caster_damage * 1.10), "a ranged enemy's projectile deals 10%% more (%.2f)" % (found.projectile_damage if found else -1.0))
	var boss_base := (load(_dungeon.rooms[_dungeon.index_at(BOSS)].scene.resource_path) as PackedScene)
	_grant_seals()
	var boss_room := await _enter(_dungeon.index_at(BOSS))
	var boss: Boss = null
	for e in boss_room.get_node(^"Enemies").get_children():
		if e is Boss:
			boss = e
	var warden := (load("res://scenes/enemies/abyss_warden.tscn") as PackedScene).instantiate() as Boss
	var slam := warden.slam_damage
	var volley := warden.volley_damage
	var contact := warden.contact_damage
	warden.free()
	_check(boss != null and is_equal_approx(boss.slam_damage, slam * 1.10) and is_equal_approx(boss.volley_damage, volley * 1.10)
			and is_equal_approx(boss.contact_damage, contact * 1.10), "the boss's slam, volley and contact damage are all +10%%")
	boss_base = null


func _stats(path: String) -> Dictionary:
	var e := (load(path) as PackedScene).instantiate() as Enemy
	var stats := {"hp": (e.get_node(^"Health") as Health).max_health, "damage": e.contact_damage, "speed": e.speed,
			"cooldown": e.attack_cooldown, "xp": e.xp_reward, "gold": e.currency_reward}
	e.free()
	return stats


func _enter(index: int) -> Room:
	_dungeon.enter_room(index, &"DoorBottom")
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
