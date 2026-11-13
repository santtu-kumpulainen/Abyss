extends SceneTree
## Headless check of the Issue #55 Stage 5 miniboss HP curve (+50% max HP per
## dungeon level) in real Dungeon rooms on levels 1, 3, 5 and 10:
## - single, double and triple miniboss rooms (built by Dungeon._add_miniboss and
##   scaled by Dungeon._scale_enemy): final max HP =
##   base x room factor (1 / 0.85 / 0.75) x difficulty x (1 + 0.5 (L-1)) x the
##   room's output HP modifier, each applied exactly once;
## - the output HP modifier composes with it (a strong build on level 1);
## - miniboss damage, attack pace, cooldowns, move speed and projectile speed
##   still follow the unchanged pre-#55 miniboss curve; the boss and regular
##   enemies are unaffected.
## The planned miniboss line-up of three miniboss rooms is set to 1 / 2 / 3
## different minibosses so every room type is covered on every level (the
## planner itself only places triple rooms from level 4).
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_miniboss_hp.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const DUNGEON := "res://scenes/dungeon/dungeon.tscn"
const LEVELS: Array[int] = [1, 3, 5, 10]
const SEED := 6060
## Pre-#55 miniboss curve (unchanged except HP).
const DAMAGE_PER_LEVEL := 0.06
const PACE_PER_LEVEL := 0.02
const PACE_CAP := 0.3
const MOVE_PER_LEVEL := 0.015
const MOVE_CAP := 0.15
## Projectile / attack timing values paced like attack_cooldown, per miniboss script.
const PACED_COOLDOWNS := {
	"BroodMother": ["summon_cooldown", "charge_cooldown"],
	"Hexcaller": ["fan_cooldown", "hex_cooldown", "blink_cooldown"],
	"WaterCasterBoss": ["bolt_cooldown", "zone_cooldown", "wave_cooldown"],
}
const PACED_SPEEDS := {
	"BroodMother": [],
	"Hexcaller": ["fan_speed"],
	"WaterCasterBoss": ["bolt_speed"],
}
const SCALED_DAMAGE := {
	"BroodMother": ["contact_damage", "charge_damage"],
	"Hexcaller": ["contact_damage", "fan_damage", "hex_damage"],
	"WaterCasterBoss": ["contact_damage", "bolt_damage", "zone_damage", "wave_damage"],
}
## Never scaled: the Brood Mother charge speed (and every telegraph, see test_tempo).
const FIXED := {"BroodMother": ["charge_speed"], "Hexcaller": [], "WaterCasterBoss": []}

var _failures := 0
var _dungeon: Dungeon


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_test_curve()
	for level in LEVELS:
		await _test_level(level)
	RunState.seed_override = 0
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_curve() -> void:
	var mb := LevelScaling.Category.MINIBOSS
	var want: Array[float] = [1.0, 2.0, 3.0, 5.5]
	var got: Array[float] = []
	for level in LEVELS:
		got.append(LevelScaling.enemy_health(level, mb))
	_check(is_equal_approx(LevelScaling.MINIBOSS_HEALTH_PER_LEVEL, 0.5) and got == want,
			"miniboss HP curve +50%% per level: %s" % [got])
	_check(is_equal_approx(LevelScaling.enemy_health(10, LevelScaling.Category.BOSS), 3.25)
			and is_equal_approx(LevelScaling.enemy_health(10, LevelScaling.Category.REGULAR), 1.72),
			"boss (x3.25) and regular (x1.72) HP on level 10 unchanged")
	_check(is_equal_approx(LevelScaling.enemy_damage(10, mb), 1.54) and is_equal_approx(LevelScaling.enemy_pace(10, mb), 1.18)
			and is_equal_approx(LevelScaling.enemy_move_pace(10, mb), 1.135) and is_equal_approx(LevelScaling.enemy_pace(50, mb), 1.3)
			and is_equal_approx(LevelScaling.enemy_move_pace(50, mb), 1.15), "miniboss damage / pace / move curve unchanged")


func _test_level(level: int) -> void:
	RunState.seed_override = SEED + level
	change_scene_to_file(DUNGEON)
	for i in 600:
		if current_scene != null and current_scene.is_node_ready():
			break
		await physics_frame
	for i in 3:
		await physics_frame
	_dungeon = current_scene as Dungeon
	var run := _dungeon.run_state
	run.dungeon_level = level
	_dungeon._plan_level()
	_check(is_equal_approx(_dungeon.double_health_factor, 0.85) and is_equal_approx(_dungeon.triple_health_factor, 0.75),
			"level %d: double / triple room factors unchanged (x0.85 / x0.75)" % level)
	# Level 1: a strong build, so the output HP modifier is above 1 and must compose.
	if level == 1:
		run.purchased[&"ember_core"] = 3
		run.purchased[&"twin_cast"] = 1
	var rooms := _dungeon.miniboss_room_indexes().filter(func(i: int) -> bool: return i != _dungeon.current_index)
	_check(rooms.size() >= 3, "level %d: setup: %d miniboss rooms" % [level, rooms.size()])
	if rooms.size() < 3:
		return
	var scenes := _dungeon.miniboss_scenes
	for size in [1, 2, 3]:
		var index: int = rooms[size - 1]
		var lineup: Array[PackedScene] = []
		for k in size:
			lineup.append(scenes[(k + level) % scenes.size()])
		_dungeon._minibosses[index] = lineup
		var modifier := run.output_hp_modifier()
		_dungeon.enter_room(index, _dungeon.entry_door(index))
		for i in 2:
			await physics_frame
		await _check_room(level, size, modifier)


func _check_room(level: int, size: int, modifier: float) -> void:
	var run := _dungeon.run_state
	var kind: String = ["single", "double", "triple"][size - 1]
	var label := "level %d %s room" % [level, kind]
	var bosses: Array[Miniboss] = []
	for node in _dungeon.current_room.get_node(^"Enemies").get_children():
		if node is Miniboss:
			bosses.append(node as Miniboss)
	_check(bosses.size() == size, "%s: %d minibosses" % [label, bosses.size()])
	var factor: float = [1.0, _dungeon.double_health_factor, _dungeon.triple_health_factor][size - 1]
	var steps := level - 1
	var curve := 1.0 + 0.5 * steps
	var hp_ok := true
	var stats_ok := true
	var shown: Array[String] = []
	var bad: Array[String] = []
	for b in bosses:
		var base := (load(b.scene_file_path) as PackedScene).instantiate() as Miniboss
		var base_hp := (base.get_node(^"Health") as Health).max_health
		# The existing behaviour tier by level (Issue #51, e.g. Water Caster cooldowns) is part of the reference.
		base.configure_for_level(level)
		var want := base_hp * factor * curve * modifier
		hp_ok = hp_ok and b.scaled and is_equal_approx(b.health.max_health, want) and is_equal_approx(b.health.current, b.health.max_health)
		shown.append("%s %.0f (base %.0f x%.2f x%.1f x%.3f)" % [b.display_name, b.health.max_health, base_hp, factor, curve, modifier])
		# Everything but HP still on the pre-#55 miniboss curve.
		var dmg := (1.0 + DAMAGE_PER_LEVEL * steps) * RunState.ENEMY_DAMAGE_FACTOR
		var pace := (1.0 + minf(PACE_PER_LEVEL * steps, PACE_CAP)) * Tempo.ENEMY_ATTACK
		var move := (1.0 + minf(MOVE_PER_LEVEL * steps, MOVE_CAP)) * Tempo.ENEMY_MOVE * LevelScaling.player_catchup(run.move_speed_multiplier())
		var script_name: String = b.get_script().get_global_name()
		var checks := {"attack_cooldown": base.attack_cooldown / pace,
				"speed": minf(base.speed * move, maxf(base.speed, LevelScaling.MAX_PURSUER_SPEED))}
		for key: String in SCALED_DAMAGE[script_name]:
			checks[key] = float(base.get(key)) * dmg
		for key: String in PACED_COOLDOWNS[script_name]:
			checks[key] = float(base.get(key)) / pace
		for key: String in PACED_SPEEDS[script_name]:
			checks[key] = float(base.get(key)) * pace
		for key: String in FIXED[script_name]:
			checks[key] = float(base.get(key))
		for key: String in checks:
			if not is_equal_approx(float(b.get(key)), checks[key]):
				stats_ok = false
				bad.append("%s.%s %.3f != %.3f" % [b.display_name, key, float(b.get(key)), checks[key]])
		base.free()
	_check(hp_ok, "%s: max HP = base x room x%.1f curve x output modifier, once: %s" % [label, curve, ", ".join(shown)])
	_check(stats_ok, "%s: damage, cooldowns, projectile and move speed on the unchanged miniboss curve %s" % [label, bad])
	# A second scaling pass changes nothing.
	var before: Array[float] = []
	for b in bosses:
		before.append(b.health.max_health)
		_dungeon._scale_enemy(b, false, 2.0)
	var after: Array[float] = []
	for b in bosses:
		after.append(b.health.max_health)
	_check(before == after, "%s: scaling again changes nothing" % label)


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
