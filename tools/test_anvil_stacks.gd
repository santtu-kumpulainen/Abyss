extends SceneTree
## Headless check of the stackable anvil: Quick Cast / Ember Core / Vitality
## stacks, prices, caps, once-per-level purchase and per-level refresh with
## persistent stacks, the Mage-level gates shifted by dungeon level, the
## +5% per Mage level damage growth (applied once) and the enemy baseline HP.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_anvil_stacks.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SEED := 4242
const SCENE := "res://scenes/dungeon/dungeon.tscn"
const FIRE_BALL := "res://scenes/spells/fire_ball/fire_ball.tres"
const NORMAL := Difficulty.Tier.NORMAL

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	RunState.seed_override = SEED
	_test_damage_growth_unit()
	_test_baseline_hp()
	_test_prices_and_caps()
	_test_refresh_and_persistence()
	_test_gates()
	await _test_scene()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	RunState.seed_override = 0
	quit(1 if _failures > 0 else 0)


func _new_run(dungeon_level: int = 1) -> RunState:
	var run := RunState.new()
	run.configure(NORMAL)
	run.dungeon_level = dungeon_level
	run.currency = 100000
	run.level = MageLevels.cap(dungeon_level)
	return run


func _next_level(run: RunState) -> void:
	run.boss_defeated = true
	run.choose_relic(&"wind_relic")
	run.begin_next_level()
	run.level = maxi(run.level, MageLevels.cap(run.dungeon_level))


# --- Damage growth / baseline HP ----------------------------------------------------

func _test_damage_growth_unit() -> void:
	var run := RunState.new()
	run.configure(NORMAL)
	_check(is_equal_approx(run.damage_bonus_per_level, 0.05), "Mage damage growth is +5% per level")
	var values: Array[float] = []
	for level in [1, 2, 4, 7, 10]:
		run.level = level
		values.append(run.spell_damage_multiplier())
	_check(is_equal_approx(values[0], 1.0) and is_equal_approx(values[1], 1.05) and is_equal_approx(values[2], 1.15)
			and is_equal_approx(values[3], 1.30) and is_equal_approx(values[4], 1.45), "damage multiplier at Lv 1/2/4/7/10 = 1.00/1.05/1.15/1.30/1.45 (%s)" % [values])
	run.level = 4
	run.changed.emit()
	run.changed.emit()
	_check(is_equal_approx(run.spell_damage_multiplier(), 1.15), "recalculating does not stack the level bonus")
	run.free()


func _test_baseline_hp() -> void:
	_check(is_equal_approx(LevelScaling.enemy_health(1), 1.0) and is_equal_approx(LevelScaling.enemy_health(2), 1.08)
			and is_equal_approx(LevelScaling.enemy_health(3), 1.16), "regular enemy HP baseline x1.00 / x1.08 / x1.16 for D1-D3 (Issue #55)")
	var run := RunState.new()
	run.configure(NORMAL)
	var hp: Array[float] = []
	for d in [1, 2, 3]:
		run.dungeon_level = d
		hp.append(run.enemy_health_multiplier())
	_check(is_equal_approx(hp[0], 1.0) and is_equal_approx(hp[1], 1.08) and is_equal_approx(hp[2], 1.16), "RunState HP multiplier at D1-D3 (Normal): %s" % [hp])
	run.dungeon_level = 3
	_check(is_equal_approx(run.enemy_damage_multiplier(), 1.24 * 1.10) and is_equal_approx(run.enemy_pace_multiplier(), 1.05 * Tempo.ENEMY_ATTACK),
			"regular enemy damage (+12%/level, then the x1.10 factor) and attack pace (+2.5%/level) scaling (Issue #55)")
	run.free()


# --- Prices, caps, stacks ----------------------------------------------------------------

func _test_prices_and_caps() -> void:
	var run := _new_run()
	var expected := {&"vitality": [100, 150, 200], &"quick_cast": [200, 300, 400], &"ember_core": [300, 450, 600]}
	for id: StringName in expected:
		var prices: Array = expected[id]
		var seen: Array[int] = []
		for stack in 3:
			seen.append(run.upgrade_cost(id))
			var gold := run.currency
			_check(run.purchase(id) and run.currency == gold - prices[stack], "%s stack %d costs %d" % [id, stack + 1, prices[stack]])
			_check(not run.purchase(id), "%s cannot be bought twice on one level" % id)
			_next_level(run)
		_check(seen == prices, "%s prices rise with the stacks owned (%s)" % [id, seen])
		_check(run.upgrade_stacks(id) == 3 and not run.can_purchase(id) and not run.purchase(id), "%s is capped at 3 stacks" % id)
		# Start again for the next upgrade.
		run.free()
		run = _new_run()
	# Quick Cast: -5% cooldown per stack, additive with Rune Sigil.
	run = _new_run()
	var mults: Array[float] = [run.spell_cooldown_multiplier()]
	for stack in 3:
		run.purchase(&"quick_cast")
		mults.append(run.spell_cooldown_multiplier())
		_next_level(run)
	_check(is_equal_approx(mults[0], 1.0) and is_equal_approx(mults[1], 0.95) and is_equal_approx(mults[2], 0.90) and is_equal_approx(mults[3], 0.85),
			"Quick Cast cooldown multiplier: 1.00 / 0.95 / 0.90 / 0.85 (%s)" % [mults])
	var base := (load(FIRE_BALL) as Spell).cooldown
	_check(is_equal_approx(base * mults[3], 0.31 * 0.85), "Fire Ball cooldown with 3 stacks: %.4f s" % (base * mults[3]))
	run.claim_treasure(&"rune_sigil")
	_check(is_equal_approx(run.spell_cooldown_multiplier(), 0.80), "Quick Cast x3 + Rune Sigil x1 add up to x0.80")
	_next_level(run)
	run.claim_treasure(&"rune_sigil")
	run.claim_treasure(&"survivor_cache")
	_next_level(run)
	run.claim_treasure(&"rune_sigil")
	_check(is_equal_approx(run.spell_cooldown_multiplier(), 0.70), "Quick Cast x3 + Rune Sigil x3 = x0.70")
	run.free()
	# Ember Core: +10% damage per stack (Issue #55).
	run = _new_run()
	var gear: Array[float] = [run.spell_damage_multiplier() - run.damage_bonus_per_level * (run.level - 1)]
	for stack in 3:
		run.purchase(&"ember_core")
		gear.append(run.spell_damage_multiplier() - run.damage_bonus_per_level * (run.level - 1))
		_next_level(run)
	_check(is_equal_approx(gear[1] - gear[0], 0.10) and is_equal_approx(gear[2] - gear[0], 0.20) and is_equal_approx(gear[3] - gear[0], 0.30),
			"Ember Core: +10%% damage per stack (%s)" % [gear])
	run.free()


func _test_refresh_and_persistence() -> void:
	var run := _new_run()
	run.add_rewards(0, 0)
	var xp_level := run.level
	run.purchase(&"vitality")
	run.purchase(&"quick_cast")
	run.purchase(&"ember_core")
	run.collect_item(&"swift_boots")
	var gold := run.currency
	_check(not run.can_purchase(&"vitality") and not run.can_purchase(&"quick_cast") and not run.can_purchase(&"ember_core"),
			"all three are sold out for the rest of the level")
	_next_level(run)
	_check(run.can_purchase(&"vitality") and run.can_purchase(&"quick_cast") and run.can_purchase(&"ember_core"), "the anvil restocks on the next level")
	_check(run.upgrade_stacks(&"vitality") == 1 and run.upgrade_stacks(&"quick_cast") == 1 and run.upgrade_stacks(&"ember_core") == 1
			and run.currency == gold and run.level >= xp_level and run.relics == [&"wind_relic"] and run.collected.has(&"swift_boots"),
			"stacks, gold, Mage level, relics and items are preserved by the refresh")
	_check(run.purchase(&"quick_cast") and run.upgrade_stacks(&"quick_cast") == 2 and is_equal_approx(run.spell_cooldown_multiplier(), 0.90),
			"the second Quick Cast stack stacks on the first (x0.90)")
	run.free()


func _test_gates() -> void:
	var run := _new_run()
	var rows := []
	for d in [1, 2, 3]:
		run.dungeon_level = d
		rows.append([run.upgrade_level(&"vitality"), run.upgrade_level(&"quick_cast"), run.upgrade_level(&"ember_core")])
	_check(rows == [[1, 2, 3], [4, 5, 6], [7, 8, 9]], "upgrade Mage level gates shift by 3 per dungeon level (%s)" % [rows])
	run.dungeon_level = 2
	run.level = 4
	_check(run.can_purchase(&"vitality") and not run.can_purchase(&"quick_cast") and not run.can_purchase(&"ember_core"),
			"on level 2 a Lv 4 Mage still needs level-ups for Quick Cast and Ember Core")
	run.level = 6
	_check(run.can_purchase(&"ember_core"), "Ember Core unlocks at Lv 6 on level 2")
	run.free()


# --- Scene ------------------------------------------------------------------------------------

func _test_scene() -> void:
	var old_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(SCENE)
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage
	_run = _dungeon.run_state
	var fire_ball := load(FIRE_BALL) as Spell
	var base_damage := fire_ball.damage
	var base_cooldown := fire_ball.cooldown
	var base_hp := _mage.health.max_health
	_run.add_rewards(0, 5000)
	_run.add_rewards(100000, 0)
	_check(_run.level == 4, "setup: Mage Lv 4")
	var expected_level_damage := base_damage * (1.0 + 0.05 * 3)
	_check(is_equal_approx(_mage.caster.get_cast_spell().damage, expected_level_damage), "projectile damage uses +5%% per level once (%.3f)" % _mage.caster.get_cast_spell().damage)
	_run.changed.emit()
	_run.changed.emit()
	_check(is_equal_approx(_mage.caster.get_cast_spell().damage, expected_level_damage), "repeated recalculation does not double-apply the growth")
	var station := _dungeon.current_room.get_node_or_null(^"Decor/UpgradeStation") as UpgradeStation
	_check(station != null and station.run_state == _run, "the starting room has an anvil")
	_mage.global_position = station.global_position + Vector2(50, 0)
	await _frames(3)
	station.set_open(true)
	_check(station.purchase(&"quick_cast") and is_equal_approx(_mage.caster.get_cast_spell().cooldown, base_cooldown * 0.95), "anvil: Quick Cast stack 1 -> cooldown x0.95")
	_check(not station.purchase(&"quick_cast"), "anvil: a second Quick Cast is refused on the same level")
	_check(station._menu_label.text.contains("Quick Cast (1/3)") and station._menu_label.text.contains("bought this level"), "anvil menu shows the stack count and the sold-out state")
	_check(station.purchase(&"vitality") and is_equal_approx(_mage.health.max_health, base_hp + 30.0 + 20.0), "anvil: Vitality +20 max HP (on top of 3 level-ups at +10)")
	_check(station.purchase(&"ember_core") and is_equal_approx(_mage.caster.get_cast_spell().damage, base_damage * (1.0 + 0.15 + 0.10)),
			"anvil: Ember Core +10%% damage (%.3f)" % _mage.caster.get_cast_spell().damage)
	# Next dungeon level: the anvil restocks, stacks persist, nothing is applied twice.
	_run.boss_defeated = true
	_run.choose_relic(&"vital_relic")
	var hp_before := _mage.health.max_health
	_dungeon.victory = true
	_check(_dungeon.advance_level() and _run.dungeon_level == 2, "setup: level 2 started")
	await _frames(2)
	station = _dungeon.current_room.get_node_or_null(^"Decor/UpgradeStation") as UpgradeStation
	_check(station != null and station.run_state == _run and _run.upgrade_stacks(&"quick_cast") == 1, "level 2: the anvil is there and keeps the stacks")
	_check(is_equal_approx(_mage.caster.get_cast_spell().cooldown, base_cooldown * 0.95) and _mage.health.max_health >= hp_before,
			"level 2: owned bonuses still apply exactly once")
	_mage.global_position = station.global_position + Vector2(50, 0)
	await _frames(3)
	station.set_open(true)
	_run.add_rewards(0, 2000)
	_check(_run.upgrade_level(&"quick_cast") == 5 and not _run.can_purchase(&"quick_cast"), "level 2: a Lv 4 Mage cannot buy Quick Cast (gate Lv 5)")
	_run.add_rewards(_run.xp_to_next_level(), 0)
	_check(_run.level == 5, "setup: Mage Lv 5")
	_check(station.purchase(&"quick_cast") and _run.upgrade_stacks(&"quick_cast") == 2 and is_equal_approx(_mage.caster.get_cast_spell().cooldown, base_cooldown * 0.90),
			"level 2: Quick Cast stack 2 (x0.90) at the 300 price")
	_check(station._menu_label.text.contains("Quick Cast (2/3)"), "menu shows 2/3")


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame


func _wait_until(condition: Callable, max_frames: int = 240) -> void:
	for i in max_frames:
		if condition.call():
			return
		await physics_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
