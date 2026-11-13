extends SceneTree
## Headless check of the Issue #55 Stage 3 player progression values:
## - cooldown items: Quick Cast -5%/stack, Quickening Rune -5%, Rune Sigil -5%;
##   the summed reduction is capped at RunState.MAX_COOLDOWN_REDUCTION (40%,
##   multiplier never below 0.60), Swift Casting (-30%) included;
## - damage items: Ember Core +10%/stack, Ember Shard +8%, Fury Idol +6%,
##   Ember Relic +10%; Mage level damage stays +5%/level;
## - unchanged: Warding Charm, Twin Cast, Vitality, Heart Crystal, Bloodstone,
##   Vital Relic, Swift Casting's damage drawback;
## - every effect text shows its value;
## - cooldown / damage multipliers and player output on levels 1, 3, 5 and 10;
## - a Mage level-up in a run: +10 max HP, still heals 20.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_player_progression.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const DUNGEON := "res://scenes/dungeon/dungeon.tscn"
const LEVELS: Array[int] = [1, 3, 5, 10]

var _failures := 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_test_values_and_texts()
	_test_cooldown_cap()
	_test_damage_and_output()
	await _test_level_up()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_values_and_texts() -> void:
	var u := RunState.UPGRADES
	var i := RunState.ITEMS
	var r := RunState.RELICS
	var t := RunState.TREASURES
	# [data, key, value, effect text]
	var rows := [
		[u[&"quick_cast"], "cooldown", 0.05, "-5% spell cooldown per stack"],
		[i[&"quickening_rune"], "cooldown", 0.05, "-5% spell cooldown"],
		[t[&"rune_sigil"], "cooldown", 0.05, "-5% spell cooldown"],
		[u[&"ember_core"], "damage", 0.1, "+10% spell damage per stack"],
		[i[&"ember_shard"], "damage", 0.08, "+8% Fire Ball damage"],
		[i[&"fury_idol"], "damage", 0.06, "+6% spell damage"],
		[r[&"ember_relic"], "damage", 0.1, "+10% Fire Ball damage"],
		# Unchanged by Issue #55.
		[i[&"warding_charm"], "damage_taken", -0.1, "-10% damage taken"],
		[u[&"vitality"], "max_health", 20.0, "+20 max HP per stack"],
		[i[&"heart_crystal"], "max_health", 25.0, "+25 max HP"],
		[i[&"bloodstone"], "max_health", 15.0, "+15 max HP, +3% move speed"],
		[r[&"vital_relic"], "max_health", 30.0, "+30 max HP, heal 30"],
		[Pacts.PACTS[&"swift_casting"], "cooldown", 0.3, ""],
		[Pacts.PACTS[&"swift_casting"], "damage", -0.2, ""],
	]
	for row in rows:
		var data: Dictionary = row[0]
		var ok := is_equal_approx(float(data.get(row[1], 0.0)), row[2])
		if not String(row[3]).is_empty():
			ok = ok and data["effect"] == row[3]
		_check(ok, "%s: %s %s (\"%s\")" % [data["name"], row[1], row[2], data.get("effect", "%s, %s" % [data.get("benefit", ""), data.get("drawback", "")])])
	_check(is_equal_approx(float(i[&"bloodstone"]["speed"]), 0.03), "Bloodstone: +3% move speed unchanged")
	_check(u[&"twin_cast"]["effect"] == "2 projectiles per cast, 70% damage each (this run)"
			and RunState.TWIN_CAST_COUNT == 2 and is_equal_approx(RunState.TWIN_CAST_DAMAGE_FACTOR, 0.7),
			"Twin Cast unchanged (2 x 70%)")
	_check(is_equal_approx(RunState.MAX_COOLDOWN_REDUCTION, 0.4), "cooldown reduction cap is 40%")
	var run := RunState.new()
	_check(is_equal_approx(run.max_health_per_level, 10.0), "level-up max HP is +10")
	_check(is_equal_approx(run.heal_per_level, 20.0), "level-up heal is still 20")
	_check(is_equal_approx(run.damage_bonus_per_level, 0.05), "Mage level damage is still +5% per level")
	run.free()


## A run with `quick` Quick Cast stacks, `rune` Quickening Runes, `sigil` Rune
## Sigils and Pact `pact` (stacks set directly: once-per-level limits don't matter here).
static func _run_with(quick: int, rune: int, sigil: int, pact: StringName = &"") -> RunState:
	var run := RunState.new()
	run.pact = pact
	if quick > 0:
		run.purchased[&"quick_cast"] = quick
	if rune > 0:
		run.collected[&"quickening_rune"] = rune
	if sigil > 0:
		run.treasures[&"rune_sigil"] = sigil
	return run


func _test_cooldown_cap() -> void:
	# [quick cast, rune, sigil, pact, expected multiplier]
	var cases := [
		[0, 0, 0, &"", 1.0],
		[1, 0, 0, &"", 0.95],
		[3, 0, 0, &"", 0.85],
		[0, 1, 0, &"", 0.95],
		[0, 0, 1, &"", 0.95],
		[3, 1, 1, &"", 0.75],
		[3, 3, 3, &"", 0.60],
		[3, 3, 2, &"", 0.60],
		[3, 2, 2, &"", 0.65],
		[0, 0, 0, &"swift_casting", 0.70],
		[1, 0, 0, &"swift_casting", 0.65],
		[2, 0, 0, &"swift_casting", 0.60],
		[3, 0, 0, &"swift_casting", 0.60],
		[1, 1, 0, &"swift_casting", 0.60],
		[3, 3, 3, &"swift_casting", 0.60],
	]
	for c in cases:
		var run := _run_with(c[0], c[1], c[2], c[3])
		var mult := run.spell_cooldown_multiplier()
		_check(is_equal_approx(mult, c[4]), "Quick Cast x%d + Rune x%d + Sigil x%d%s: cooldown x%.2f (expected x%.2f)" % [
				c[0], c[1], c[2], " + Swift Casting" if c[3] == &"swift_casting" else "", mult, c[4]])
		run.free()
	# Every reachable combination (stacks 0-3 each, with and without Swift Casting).
	var lowest := 1.0
	for pact: StringName in [&"", &"swift_casting"]:
		for quick in 4:
			for rune in 4:
				for sigil in 4:
					var run := _run_with(quick, rune, sigil, pact)
					lowest = minf(lowest, run.spell_cooldown_multiplier())
					run.free()
	_check(lowest >= 0.6 - 0.000001 and is_equal_approx(lowest, 0.6), "the cooldown multiplier never falls below 0.60 (lowest %.4f)" % lowest)
	# The Fire Ball cooldown follows the capped multiplier.
	var spell := load("res://scenes/spells/fire_ball/fire_ball.tres") as Spell
	if spell:
		var run := _run_with(3, 3, 3, &"swift_casting")
		_check(is_equal_approx(spell.cooldown * run.spell_cooldown_multiplier(), spell.cooldown * 0.6),
				"capped Fire Ball cooldown: %.3f s (base %.3f s)" % [spell.cooldown * run.spell_cooldown_multiplier(), spell.cooldown])
		run.free()


func _test_damage_and_output() -> void:
	for level in LEVELS:
		var level_bonus := 0.05 * (level - 1)
		var base := RunState.new()
		base.level = level
		base.dungeon_level = level
		var full := RunState.new()
		full.level = level
		full.dungeon_level = level
		full.purchased[&"ember_core"] = 3
		full.collected[&"ember_shard"] = 1
		full.collected[&"fury_idol"] = 1
		full.relics.append(&"ember_relic")
		full.purchased[&"quick_cast"] = 3
		full.collected[&"quickening_rune"] = 1
		full.treasures[&"rune_sigil"] = 1
		var swift := _run_with(3, 1, 1, &"swift_casting")
		swift.level = level
		swift.dungeon_level = level
		swift.purchased[&"ember_core"] = 3
		# Full damage build: Ember Core x3 (+30%), Shard (+8%), Fury Idol (+6%), Relic (+10%) = +54%.
		_check(is_equal_approx(base.spell_damage_multiplier(), 1.0 + level_bonus)
				and is_equal_approx(full.spell_damage_multiplier(), 1.0 + level_bonus + 0.54)
				and is_equal_approx(swift.spell_damage_multiplier(), 1.0 + level_bonus + 0.3 - 0.2),
				"level %d damage: base x%.2f, full build x%.2f, Swift Casting + Ember Core x3 x%.2f" % [
				level, base.spell_damage_multiplier(), full.spell_damage_multiplier(), swift.spell_damage_multiplier()])
		_check(is_equal_approx(base.spell_cooldown_multiplier(), 1.0) and is_equal_approx(full.spell_cooldown_multiplier(), 0.75)
				and is_equal_approx(swift.spell_cooldown_multiplier(), 0.6),
				"level %d cooldown: base x1.00, full build x%.2f, Swift Casting build x%.2f (no level dependence)" % [
				level, full.spell_cooldown_multiplier(), swift.spell_cooldown_multiplier()])
		var want_full := (1.0 + level_bonus + 0.54) / 0.75
		var want_swift := (1.0 + level_bonus + 0.1) / 0.6
		_check(is_equal_approx(full.player_output(), want_full) and is_equal_approx(swift.player_output(), want_swift),
				"level %d player output: base %.3f, full build %.3f, Swift Casting build %.3f" % [
				level, base.player_output(), full.player_output(), swift.player_output()])
		full.purchased[&"twin_cast"] = 1
		_check(is_equal_approx(full.player_output(), want_full * 2.0 * 0.7), "level %d: Twin Cast still multiplies output by 1.4 (%.3f)" % [
				level, full.player_output()])
		base.free()
		full.free()
		swift.free()


func _test_level_up() -> void:
	RunState.seed_override = 5151
	change_scene_to_file(DUNGEON)
	for i in 600:
		if current_scene != null and current_scene.is_node_ready():
			break
		await physics_frame
	for i in 3:
		await physics_frame
	var dungeon := current_scene as Dungeon
	var run := dungeon.run_state
	var health := dungeon.mage.health
	health.take_damage(50.0)
	var max_before := health.max_health
	var hp_before := health.current
	run.xp_multiplier_override = 1.0
	var level_before := run.level
	run.grant_enemy_rewards(run.xp_to_next_level(), 0)
	await process_frame
	_check(run.level == level_before + 1, "setup: the Mage levels up (Lv %d)" % run.level)
	_check(is_equal_approx(health.max_health, max_before + 10.0), "level-up: max HP %.0f -> %.0f (+10)" % [max_before, health.max_health])
	_check(is_equal_approx(health.current, minf(hp_before + 20.0, health.max_health)),
			"level-up still heals 20 (%.0f -> %.0f)" % [hp_before, health.current])
	run.xp_multiplier_override = 0.0
	RunState.seed_override = 0


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
