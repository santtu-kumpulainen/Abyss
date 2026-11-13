extends SceneTree
## Headless check of the Issue #55 Stage 2 split of the enemy level scaling into
## three curves (LevelScaling.Category: regular enemies, minibosses, the boss):
## - category_of() puts every enemy scene on the right curve;
## - on dungeon levels 1, 3, 5 and 10 each curve still gives the pre-#55 values
##   (+25% HP, +6% damage, +2% attack pace capped at +30%, +1.5% move pace
##   capped at +15% per level), directly and through RunState on every tier;
## - calls without a category stay on the regular curve;
## - Dungeon._scale_enemy() scales a regular enemy, a miniboss and the boss by
##   their own curve (max HP and contact damage of the real scenes).
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_scaling_paths.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const DUNGEON := "res://scenes/dungeon/dungeon.tscn"
const LEVELS: Array[int] = [1, 3, 5, 10]
const REGULAR_SCENES: Array[String] = ["giant_goblin", "demon", "demon_caster", "water_caster", "blood_monster"]
const MINIBOSS_SCENES: Array[String] = ["brood_mother", "hexcaller", "water_caster_boss"]
const BOSS_SCENES: Array[String] = ["abyss_warden"]
## Pre-#55 level multipliers on levels 1 / 3 / 5 / 10 (same for every category).
const EXPECTED := {
	"health": [1.0, 1.5, 2.0, 3.25],
	"damage": [1.0, 1.12, 1.24, 1.54],
	"pace": [1.0, 1.04, 1.08, 1.18],
	"move": [1.0, 1.03, 1.06, 1.135],
}

var _failures := 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_test_curves()
	_test_run_state()
	await _test_categories_and_dungeon()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## The pre-#55 formula, written out (the reference every curve must match in Stage 2).
static func _legacy(kind: String, level: int) -> float:
	var steps := maxi(level - 1, 0)
	match kind:
		"health":
			return 1.0 + 0.25 * steps
		"damage":
			return 1.0 + 0.06 * steps
		"pace":
			return 1.0 + minf(0.02 * steps, 0.3)
	return 1.0 + minf(0.015 * steps, 0.15)


static func _curve(kind: String, level: int, category: LevelScaling.Category) -> float:
	match kind:
		"health":
			return LevelScaling.enemy_health(level, category)
		"damage":
			return LevelScaling.enemy_damage(level, category)
		"pace":
			return LevelScaling.enemy_pace(level, category)
	return LevelScaling.enemy_move_pace(level, category)


func _test_curves() -> void:
	for category: int in LevelScaling.Category.values():
		var label: String = LevelScaling.Category.keys()[category]
		for kind: String in EXPECTED:
			var shown: Array[String] = []
			var ok := true
			for i in LEVELS.size():
				var value := _curve(kind, LEVELS[i], category)
				shown.append("L%d %.4f" % [LEVELS[i], value])
				ok = ok and is_equal_approx(value, EXPECTED[kind][i]) and is_equal_approx(value, _legacy(kind, LEVELS[i]))
			_check(ok, "%s %s curve unchanged (%s)" % [label, kind, ", ".join(shown)])
	# The caps still hold deep in the run (level 20) on every curve.
	for category: int in LevelScaling.Category.values():
		_check(is_equal_approx(LevelScaling.enemy_pace(20, category), 1.3)
				and is_equal_approx(LevelScaling.enemy_move_pace(20, category), 1.15),
				"%s pace caps unchanged at level 20" % LevelScaling.Category.keys()[category])
	var defaults_ok := true
	for level in LEVELS:
		for kind: String in EXPECTED:
			defaults_ok = defaults_ok and _curve(kind, level, LevelScaling.Category.REGULAR) == _default_curve(kind, level)
	_check(defaults_ok, "LevelScaling calls without a category use the regular curve")


static func _default_curve(kind: String, level: int) -> float:
	match kind:
		"health":
			return LevelScaling.enemy_health(level)
		"damage":
			return LevelScaling.enemy_damage(level)
		"pace":
			return LevelScaling.enemy_pace(level)
	return LevelScaling.enemy_move_pace(level)


## RunState multipliers per category on every tier equal the pre-#55 formula.
func _test_run_state() -> void:
	for tier: int in Difficulty.TIERS:
		var data := Difficulty.data(tier)
		for category: int in LevelScaling.Category.values():
			var ok := true
			for level in LEVELS:
				var run := RunState.new()
				run.difficulty = tier
				run.dungeon_level = level
				ok = ok and is_equal_approx(run.enemy_health_multiplier(false, category),
						data["enemy_health"] * _legacy("health", level))
				ok = ok and is_equal_approx(run.enemy_damage_multiplier(category == LevelScaling.Category.BOSS, false, category),
						data["enemy_damage"] * _legacy("damage", level) * RunState.ENEMY_DAMAGE_FACTOR)
				ok = ok and is_equal_approx(run.enemy_pace_multiplier(category),
						data["enemy_pace"] * _legacy("pace", level) * Tempo.ENEMY_ATTACK)
				ok = ok and is_equal_approx(run.enemy_move_pace_multiplier(category),
						data["enemy_move_pace"] * _legacy("move", level) * Tempo.ENEMY_MOVE)
				ok = ok and run.enemy_health_multiplier(false, category) == run.enemy_health_multiplier() \
						and run.enemy_damage_multiplier(false, false, category) == run.enemy_damage_multiplier() \
						and run.enemy_pace_multiplier(category) == run.enemy_pace_multiplier() \
						and run.enemy_move_pace_multiplier(category) == run.enemy_move_pace_multiplier()
				run.free()
			_check(ok, "%s: %s RunState multipliers unchanged on levels 1/3/5/10" % [
					Difficulty.display_name(tier), LevelScaling.Category.keys()[category]])


func _test_categories_and_dungeon() -> void:
	RunState.seed_override = 4242
	change_scene_to_file(DUNGEON)
	for i in 600:
		if current_scene != null and current_scene.is_node_ready():
			break
		await physics_frame
	for i in 3:
		await physics_frame
	var dungeon := current_scene as Dungeon
	var holder := Node2D.new()
	holder.position = Vector2(-5000, -5000)
	holder.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(holder)

	var groups := {
		LevelScaling.Category.REGULAR: REGULAR_SCENES,
		LevelScaling.Category.MINIBOSS: MINIBOSS_SCENES,
		LevelScaling.Category.BOSS: BOSS_SCENES,
	}
	for category: int in groups:
		for name: String in groups[category]:
			var enemy := _spawn(holder, name)
			_check(LevelScaling.category_of(enemy) == category, "%s is on the %s curve" % [
					name, LevelScaling.Category.keys()[category]])
			enemy.free()
	var elite := _spawn(holder, "giant_goblin")
	elite.elite = true
	_check(LevelScaling.category_of(elite) == LevelScaling.Category.REGULAR, "an elite enemy stays on the regular curve")
	elite.free()
	var roster_ok := true
	for scene in dungeon.miniboss_scenes:
		var miniboss := scene.instantiate() as Enemy
		holder.add_child(miniboss)
		roster_ok = roster_ok and LevelScaling.category_of(miniboss) == LevelScaling.Category.MINIBOSS
		miniboss.free()
	_check(roster_ok, "every miniboss of the Dungeon roster is on the miniboss curve")

	# Real scenes through Dungeon._scale_enemy on each tier and level 1 / 3 / 5 / 10.
	for tier: int in Difficulty.TIERS:
		var data := Difficulty.data(tier)
		dungeon.run_state.difficulty = tier
		for name: String in ["giant_goblin", "hexcaller", "abyss_warden"]:
			var shown: Array[String] = []
			var ok := true
			for level in LEVELS:
				dungeon.run_state.dungeon_level = level
				var base := _spawn(holder, name)
				var base_hp := base.health.max_health
				var base_contact := base.contact_damage
				base.free()
				var enemy := _spawn(holder, name)
				dungeon._scale_enemy(enemy, false, 1.0)
				var want_hp: float = base_hp * data["enemy_health"] * _legacy("health", level)
				var want_contact: float = base_contact * data["enemy_damage"] * _legacy("damage", level) \
						* RunState.ENEMY_DAMAGE_FACTOR
				ok = ok and is_equal_approx(enemy.health.max_health, want_hp) and is_equal_approx(enemy.contact_damage, want_contact)
				shown.append("L%d %.0f HP" % [level, enemy.health.max_health])
				enemy.free()
			_check(ok, "%s: %s scaled as before (%s)" % [Difficulty.display_name(tier), name, ", ".join(shown)])
	dungeon.run_state.dungeon_level = 1
	dungeon.run_state.difficulty = Difficulty.Tier.NORMAL
	holder.free()
	RunState.seed_override = 0


func _spawn(holder: Node, name: String) -> Enemy:
	var enemy := (load("res://scenes/enemies/%s.tscn" % name) as PackedScene).instantiate() as Enemy
	holder.add_child(enemy)
	return enemy


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
