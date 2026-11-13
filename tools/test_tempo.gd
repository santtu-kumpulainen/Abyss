extends SceneTree
## Headless check of Issue #51 Stage 5 (game tempo, section K): the Tempo
## constants, the Mage / Fire Ball values, RunState folding the tempo into the
## enemy multipliers (recovery never compounded with difficulty or level pace),
## and, for every enemy scene scaled through the Dungeon exactly as in a run:
## walk speed x1.25 (capped), cooldowns /1.15, projectile speeds x1.15,
## post-attack recovery pauses /1.15, while every telegraph / windup / delay,
## the Goblin Dash timings, the dash / charge / wave speeds, HP, XP and gold stay
## unchanged.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_tempo.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const DUNGEON := "res://scenes/dungeon/dungeon.tscn"
const ENEMIES: Array[String] = [
	"res://scenes/enemies/demon.tscn",
	"res://scenes/enemies/demon_caster.tscn",
	"res://scenes/enemies/giant_goblin.tscn",
	"res://scenes/enemies/blood_monster.tscn",
	"res://scenes/enemies/water_caster.tscn",
	"res://scenes/enemies/brood_mother.tscn",
	"res://scenes/enemies/hexcaller.tscn",
	"res://scenes/enemies/water_caster_boss.tscn",
	"res://scenes/enemies/abyss_warden.tscn",
]
## Post-attack recovery pauses (divided by Tempo.ENEMY_RECOVERY).
const RECOVERY := [&"special_recover", &"swing_recover", &"recover_time", &"charge_recover"]
## Property name parts of telegraph / windup / delay timings (never scaled).
const TELEGRAPH_PARTS := ["windup", "telegraph", "track_time", "lock_time", "anticipation", "delay", "strike_active",
		"wave_cast", "warning", "slash_time"]
## Movement speeds of attacks that tempo never changes.
const FIXED_SPEEDS := [&"dash_speed", &"charge_speed", &"wave_speed"]
## Projectile speeds (x attack pace).
const PROJECTILE_SPEEDS := [&"projectile_speed", &"bolt_speed", &"fan_speed", &"volley_speed"]

var _failures := 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_test_constants()
	_test_player()
	_test_run_multipliers()
	await _test_enemies()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_constants() -> void:
	_check(is_equal_approx(Tempo.ENEMY_MOVE, 1.25) and is_equal_approx(Tempo.ENEMY_ATTACK, 1.15) and is_equal_approx(Tempo.ENEMY_RECOVERY, 1.15),
			"Tempo: enemy move x1.25, attack x1.15, recovery /1.15")
	_check(is_equal_approx(LevelScaling.MAX_PURSUER_SPEED, 175.0), "pursuer speed cap 140 -> 175")


func _test_player() -> void:
	var mage := (load("res://scenes/mage/mage.tscn") as PackedScene).instantiate() as Mage
	_check(is_equal_approx(mage.speed, 185.0), "Mage walk speed 150 -> 185")
	_check(is_equal_approx(mage.dash_distance, 130.0) and is_equal_approx(mage.dash_duration, 0.15)
			and is_equal_approx(mage.dash_cooldown, 2.35) and is_equal_approx(mage.dash_invulnerability, 0.20),
			"dash 130 px in 0.15 s, cooldown 2.35 s, invulnerability 0.20 s unchanged")
	_check(LevelScaling.MAX_PURSUER_SPEED < mage.speed, "pursuers stay slower than the Mage (175 < 185)")
	mage.free()
	var fire := load("res://scenes/spells/fire_ball/fire_ball.tres") as Spell
	_check(is_equal_approx(fire.speed, 400.0) and is_equal_approx(fire.lifetime, 1.2) and is_equal_approx(fire.cooldown, 0.31)
			and is_equal_approx(fire.damage, 10.0), "Fire Ball: speed 400, lifetime 1.2 s, cooldown 0.31 s, damage 10 unchanged")
	_check(is_equal_approx(fire.speed * fire.lifetime, 320.0 * 1.5), "Fire Ball range kept (%.0f px)" % (fire.speed * fire.lifetime))


func _test_run_multipliers() -> void:
	var run := RunState.new()
	run.configure(Difficulty.Tier.NORMAL)
	run.dungeon_level = 1
	_check(is_equal_approx(run.enemy_pace_multiplier(), 1.15) and is_equal_approx(run.enemy_move_pace_multiplier(), 1.25)
			and is_equal_approx(run.enemy_recovery_multiplier(), 1.15), "Normal L1: attack pace x1.15, move x1.25, recovery /1.15")
	_check(is_equal_approx(run.enemy_health_multiplier(), 1.0) and is_equal_approx(run.enemy_damage_multiplier(), RunState.ENEMY_DAMAGE_FACTOR),
			"Normal L1: HP and damage multipliers untouched by tempo")
	run.free()
	run = RunState.new()
	run.configure(Difficulty.Tier.ABYSSAL)
	run.dungeon_level = 20
	_check(is_equal_approx(run.enemy_recovery_multiplier(), 1.15), "Abyssal L20: recovery still exactly /1.15 (not compounded)")
	_check(is_equal_approx(run.enemy_pace_multiplier(), Difficulty.data(Difficulty.Tier.ABYSSAL)["enemy_pace"] * LevelScaling.enemy_pace(20) * 1.15),
			"Abyssal L20: attack pace = difficulty x level (capped) x 1.15")
	run.free()


func _test_enemies() -> void:
	var old_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(DUNGEON)
	for i in 600:
		if current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready():
			break
		await process_frame
	await physics_frame
	var dungeon := current_scene as Dungeon
	var run := dungeon.run_state
	# The Dungeon already configured its run (configure() works once): set the worst case directly.
	run.difficulty = Difficulty.Tier.ABYSSAL
	run.dungeon_level = 10
	_check(is_equal_approx(run.enemy_pace_multiplier(), 1.2 * LevelScaling.enemy_pace(10) * 1.15),
			"enemy checks run on Abyssal L10 (attack pace x%.3f)" % run.enemy_pace_multiplier())
	for path in ENEMIES:
		var name := path.get_file().get_basename()
		var enemy := (load(path) as PackedScene).instantiate() as Enemy
		enemy.target_group = &"nobody"
		var holder := Node2D.new()
		root.add_child(holder)
		holder.add_child(enemy)
		# Each enemy on its own level curve (Issue #55: regular / miniboss / boss).
		var category := LevelScaling.category_of(enemy)
		var pace := run.enemy_pace_multiplier(category)
		var move := run.enemy_move_pace_multiplier(category)
		var before := _snapshot(enemy)
		dungeon._scale_enemy(enemy, false)
		var after := _snapshot(enemy)
		var telegraph_ok := true
		var recovery_ok := true
		var fixed_ok := true
		var projectile_ok := true
		var bad: Array[String] = []
		for key: StringName in before:
			var b: float = before[key]
			var a: float = after[key]
			if RECOVERY.has(key):
				if not is_equal_approx(a, b / Tempo.ENEMY_RECOVERY):
					recovery_ok = false
					bad.append(String(key))
			elif _is_telegraph(key):
				if not is_equal_approx(a, b):
					telegraph_ok = false
					bad.append(String(key))
			elif FIXED_SPEEDS.has(key):
				if not is_equal_approx(a, b):
					fixed_ok = false
					bad.append(String(key))
			elif PROJECTILE_SPEEDS.has(key):
				if not is_equal_approx(a, b * pace):
					projectile_ok = false
					bad.append(String(key))
		_check(recovery_ok, "%s: recovery pauses / 1.15 only %s" % [name, _keys(before, RECOVERY)])
		_check(telegraph_ok, "%s: every telegraph / windup / delay unchanged (%d values) %s" % [name, _count_telegraphs(before), bad])
		_check(fixed_ok and projectile_ok, "%s: dash / charge / wave speeds unchanged, projectile speeds x pace %s" % [name, bad])
		var cap := enemy.speed_cap if enemy.speed_cap > 0.0 else LevelScaling.MAX_PURSUER_SPEED
		_check(is_equal_approx(enemy.speed, minf(before[&"speed"] * move, maxf(before[&"speed"], cap))),
				"%s: walk speed %.0f -> %.1f (x%.3f incl. tempo 1.25, capped at %.0f)" % [name, before[&"speed"], enemy.speed, move, cap])
		_check(is_equal_approx(enemy.attack_cooldown, before[&"attack_cooldown"] / pace), "%s: attack cooldown / %.3f (incl. tempo 1.15)" % [name, pace])
		_check(enemy.xp_reward == int(before[&"xp_reward"]) and enemy.currency_reward == int(before[&"currency_reward"]),
				"%s: XP and gold unchanged" % name)
		if enemy is Goblin:
			var g := enemy as Goblin
			_check(is_equal_approx(g.special_track_time, 0.30) and is_equal_approx(g.special_lock_time, 0.35)
					and is_equal_approx(g.special_anticipation, 0.30) and is_equal_approx(g.special_windup, 0.95)
					and is_equal_approx(g.strike_active, 0.12), "Goblin Dash 0.30 + 0.35 + 0.30 = 0.95 s, strike 0.12 s (Stage 2c) kept")
		if enemy is BloodMonster:
			var bm := enemy as BloodMonster
			_check(is_equal_approx(bm.special_windup, 0.9) and is_equal_approx(bm.death_blast_delay, 0.6),
					"Blood Monster: 0.9 s dash windup and 0.6 s death blast warning unchanged")
		holder.free()


## Every float export of `enemy` (plus max HP, XP and gold).
func _snapshot(enemy: Enemy) -> Dictionary:
	var out := {}
	for prop in enemy.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and prop["type"] == TYPE_FLOAT:
			out[StringName(prop["name"])] = float(enemy.get(prop["name"]))
	out[&"xp_reward"] = float(enemy.xp_reward)
	out[&"currency_reward"] = float(enemy.currency_reward)
	out[&"max_health"] = enemy.health.max_health
	return out


func _is_telegraph(key: StringName) -> bool:
	var s := String(key)
	if s.begins_with("_"):
		return false
	for part: String in TELEGRAPH_PARTS:
		if s.contains(part):
			return true
	return false


func _count_telegraphs(snapshot: Dictionary) -> int:
	return snapshot.keys().filter(func(k: StringName) -> bool: return _is_telegraph(k)).size()


func _keys(snapshot: Dictionary, names: Array) -> Array:
	return names.filter(func(k: StringName) -> bool: return snapshot.has(k))


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
