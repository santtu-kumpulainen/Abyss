extends SceneTree
## Headless check of the Issue #55 Stage 4 regular-enemy level scaling on real
## enemy scenes scaled through Dungeon._scale_enemy() (levels 1, 3, 5 and 10):
## - HP +8%, damage +12%, attack pace +2.5% (cap +25%), move +1% (cap +10%)
##   per dungeon level, on top of the unchanged Tempo baselines (move x1.25,
##   attack x1.15, recovery /1.15) and difficulty multipliers;
## - the pace shortens attack cooldowns and speeds up projectiles, once;
## - move speed: difficulty, catch-up (half the Mage's speed bonus, max +10%) and
##   the walking-speed limits (MAX_PURSUER_SPEED 175, Demon 210) are unchanged;
## - telegraphs / windups never scale, recovery pauses only by the fixed tempo;
## - scaling an enemy a second time changes nothing, and enemies of a room the
##   Dungeon builds are scaled exactly once.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_regular_scaling.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const DUNGEON := "res://scenes/dungeon/dungeon.tscn"
const LEVELS: Array[int] = [1, 3, 5, 10]
const REGULAR := LevelScaling.Category.REGULAR

var _failures := 0
var _dungeon: Dungeon
var _holder: Node2D


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_test_constants()
	await _load_dungeon()
	_test_goblin()
	_test_ranged()
	_test_speed_limits_and_catchup()
	_test_once()
	await _test_room_built_by_dungeon()
	_holder.free()
	RunState.seed_override = 0
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_constants() -> void:
	_check(is_equal_approx(LevelScaling.HEALTH_PER_LEVEL, 0.08) and is_equal_approx(LevelScaling.DAMAGE_PER_LEVEL, 0.12)
			and is_equal_approx(LevelScaling.PACE_PER_LEVEL, 0.025) and is_equal_approx(LevelScaling.PACE_CAP, 0.25)
			and is_equal_approx(LevelScaling.MOVE_PACE_PER_LEVEL, 0.01) and is_equal_approx(LevelScaling.MOVE_PACE_CAP, 0.1),
			"regular curve: +8% HP, +12% damage, +2.5% pace (cap 25%), +1% move (cap 10%) per level")
	_check(is_equal_approx(Tempo.ENEMY_MOVE, 1.25) and is_equal_approx(Tempo.ENEMY_ATTACK, 1.15) and is_equal_approx(Tempo.ENEMY_RECOVERY, 1.15),
			"Tempo baselines unchanged (move x1.25, attack x1.15, recovery /1.15)")
	_check(is_equal_approx(LevelScaling.MAX_PURSUER_SPEED, 175.0) and is_equal_approx(LevelScaling.CATCHUP_WEIGHT, 0.5)
			and is_equal_approx(LevelScaling.CATCHUP_CAP, 0.1), "speed limit 175 and catch-up (x0.5, max +10%) unchanged")
	# Caps: reached on level 11, never exceeded.
	_check(is_equal_approx(LevelScaling.enemy_pace(11, REGULAR), 1.25) and is_equal_approx(LevelScaling.enemy_pace(50, REGULAR), 1.25)
			and is_equal_approx(LevelScaling.enemy_pace(10, REGULAR), 1.225), "attack pace reaches its +25% cap on level 11 and stays there")
	_check(is_equal_approx(LevelScaling.enemy_move_pace(11, REGULAR), 1.1) and is_equal_approx(LevelScaling.enemy_move_pace(50, REGULAR), 1.1)
			and is_equal_approx(LevelScaling.enemy_move_pace(10, REGULAR), 1.09), "move growth reaches its +10% cap on level 11 and stays there")
	_check(is_equal_approx(LevelScaling.enemy_health(50, REGULAR), 1.0 + 0.08 * 49) and is_equal_approx(LevelScaling.enemy_damage(50, REGULAR), 1.0 + 0.12 * 49),
			"HP and damage growth are uncapped (level 50: x%.2f / x%.2f)" % [LevelScaling.enemy_health(50, REGULAR), LevelScaling.enemy_damage(50, REGULAR)])


## Goblin (melee, telegraphed special) on every tier and level.
func _test_goblin() -> void:
	for tier: int in Difficulty.TIERS:
		var data := Difficulty.data(tier)
		var shown: Array[String] = []
		var ok := true
		for level in LEVELS:
			var steps := level - 1
			var base := _spawn("giant_goblin") as Goblin
			var goblin := _scaled("giant_goblin", tier, level) as Goblin
			var hp: float = data["enemy_health"] * (1.0 + 0.08 * steps)
			var dmg: float = data["enemy_damage"] * (1.0 + 0.12 * steps) * RunState.ENEMY_DAMAGE_FACTOR
			var pace: float = data["enemy_pace"] * (1.0 + minf(0.025 * steps, 0.25)) * Tempo.ENEMY_ATTACK
			var move: float = data["enemy_move_pace"] * (1.0 + minf(0.01 * steps, 0.1)) * Tempo.ENEMY_MOVE
			ok = ok and is_equal_approx(goblin.health.max_health, base.health.max_health * hp)
			ok = ok and is_equal_approx(goblin.contact_damage, base.contact_damage * dmg)
			ok = ok and is_equal_approx(goblin.special_damage, base.special_damage * dmg)
			ok = ok and is_equal_approx(goblin.attack_cooldown, base.attack_cooldown / pace)
			ok = ok and is_equal_approx(goblin.special_cooldown, base.special_cooldown / pace)
			ok = ok and is_equal_approx(goblin.speed, minf(base.speed * move, LevelScaling.MAX_PURSUER_SPEED))
			# Never scaled by level or pace: telegraph and windup times; recovery only by the fixed tempo.
			ok = ok and goblin.special_track_time == base.special_track_time and goblin.special_lock_time == base.special_lock_time \
					and goblin.special_anticipation == base.special_anticipation and goblin.special_windup == base.special_windup
			ok = ok and is_equal_approx(goblin.swing_recover, base.swing_recover / Tempo.ENEMY_RECOVERY) \
					and is_equal_approx(goblin.special_recover, base.special_recover / Tempo.ENEMY_RECOVERY)
			shown.append("L%d HP %.1f dmg %.2f speed %.1f cd %.3f" % [level, goblin.health.max_health, goblin.contact_damage,
					goblin.speed, goblin.special_cooldown])
			base.free()
			goblin.free()
		_check(ok, "%s Goblin: %s" % [Difficulty.display_name(tier), "; ".join(shown)])


## Ranged enemies: the pace shortens the cooldown and speeds up the projectile once.
func _test_ranged() -> void:
	for name: String in ["demon_caster", "water_caster"]:
		var shown: Array[String] = []
		var ok := true
		for level in LEVELS:
			var steps := level - 1
			var base := _spawn(name) as RangedEnemy
			var caster := _scaled(name, Difficulty.Tier.NORMAL, level) as RangedEnemy
			var pace := (1.0 + minf(0.025 * steps, 0.25)) * Tempo.ENEMY_ATTACK
			var dmg := (1.0 + 0.12 * steps) * RunState.ENEMY_DAMAGE_FACTOR
			ok = ok and is_equal_approx(caster.attack_cooldown, base.attack_cooldown / pace)
			ok = ok and is_equal_approx(caster.projectile_speed, base.projectile_speed * pace)
			ok = ok and is_equal_approx(caster.projectile_damage, base.projectile_damage * dmg)
			ok = ok and is_equal_approx(caster.speed, base.speed * (1.0 + minf(0.01 * steps, 0.1)) * Tempo.ENEMY_MOVE)
			shown.append("L%d cd %.3f s, bolt %.1f px/s" % [level, caster.attack_cooldown, caster.projectile_speed])
			base.free()
			caster.free()
		_check(ok, "Normal %s: %s" % [name, "; ".join(shown)])


func _test_speed_limits_and_catchup() -> void:
	var run := _dungeon.run_state
	# Catch-up: half the Mage's speed bonus, at most +10%.
	run.collected[&"swift_boots"] = 1
	run.dungeon_level = 5
	var boots := run.enemy_move_pace_multiplier()
	_check(is_equal_approx(boots, 1.04 * 1.04 * Tempo.ENEMY_MOVE), "Swift Boots (+8%%): enemies +4%% catch-up on top (x%.4f)" % boots)
	run.collected[&"swift_boots"] = 3
	var capped := run.enemy_move_pace_multiplier()
	_check(is_equal_approx(capped, 1.04 * 1.1 * Tempo.ENEMY_MOVE), "+24%% Mage speed: catch-up capped at +10%% (x%.4f)" % capped)
	run.collected.erase(&"swift_boots")
	# Deepest regular move multiplier: Abyssal x level cap x catch-up cap x tempo.
	run.difficulty = Difficulty.Tier.ABYSSAL
	run.dungeon_level = 20
	run.collected[&"swift_boots"] = 3
	var deepest := run.enemy_move_pace_multiplier()
	_check(is_equal_approx(deepest, 1.1 * 1.1 * 1.1 * Tempo.ENEMY_MOVE), "deepest regular move multiplier x%.4f (Abyssal, level 20, full catch-up)" % deepest)
	var goblin := _spawn("giant_goblin")
	var base_speed := goblin.speed
	_dungeon._scale_enemy(goblin, false)
	_check(is_equal_approx(goblin.speed, base_speed * deepest) and goblin.speed < LevelScaling.MAX_PURSUER_SPEED,
			"Goblin at the deepest multiplier: %.1f px/s, below the 175 limit and the Mage's 185" % goblin.speed)
	goblin.free()
	# A faster pursuer is held at MAX_PURSUER_SPEED; the Demon at its own 210.
	var fast := _spawn("giant_goblin")
	fast.speed = 150.0
	_dungeon._scale_enemy(fast, false)
	_check(is_equal_approx(fast.speed, LevelScaling.MAX_PURSUER_SPEED), "a 150 px/s pursuer is held at 175 (%.1f)" % fast.speed)
	fast.free()
	var demon := _spawn("demon")
	_check(is_equal_approx(demon.speed_cap, 210.0), "the Demon keeps its 210 speed cap")
	_dungeon._scale_enemy(demon, false)
	_check(is_equal_approx(demon.speed, 210.0), "Demon at the deepest multiplier: held at 210 (%.1f)" % demon.speed)
	demon.free()
	run.collected.erase(&"swift_boots")
	run.difficulty = Difficulty.Tier.NORMAL
	for level in LEVELS:
		run.dungeon_level = level
		var d := _scaled("demon", Difficulty.Tier.NORMAL, level)
		var want := minf(160.0 * (1.0 + minf(0.01 * (level - 1), 0.1)) * Tempo.ENEMY_MOVE, 210.0)
		_check(is_equal_approx(d.speed, want), "Normal Demon on level %d: %.1f px/s" % [level, d.speed])
		d.free()
	run.dungeon_level = 1


## A second apply_scaling / _scale_enemy changes nothing.
func _test_once() -> void:
	var goblin := _scaled("giant_goblin", Difficulty.Tier.NORMAL, 10)
	var before := [goblin.health.max_health, goblin.contact_damage, goblin.speed, goblin.attack_cooldown]
	_dungeon._scale_enemy(goblin, false, 1.5)
	var again := goblin.apply_scaling(2.0, 2.0, 2.0, 1.0, 2.0, 2.0)
	_check(not again and [goblin.health.max_health, goblin.contact_damage, goblin.speed, goblin.attack_cooldown] == before,
			"scaling an enemy again changes nothing (HP, damage, speed, cooldown)")
	goblin.free()
	var caster := _scaled("demon_caster", Difficulty.Tier.NORMAL, 10) as RangedEnemy
	var bolt := caster.projectile_speed
	_dungeon._scale_enemy(caster, false)
	_check(is_equal_approx(caster.projectile_speed, bolt), "the projectile speed is paced once (%.1f px/s)" % bolt)
	caster.free()
	_dungeon.run_state.dungeon_level = 1


## Enemies of a room the Dungeon builds on level 5 are scaled exactly once.
func _test_room_built_by_dungeon() -> void:
	var run := _dungeon.run_state
	run.dungeon_level = 5
	var index := -1
	for i in _dungeon.rooms.size():
		var spec := _dungeon.rooms[i]
		if i != _dungeon.current_index and not spec.is_boss and not spec.is_treasure() and not _dungeon._room_cache.has(i) \
				and not _dungeon._minibosses.has(i):
			index = i
			break
	_check(index >= 0, "setup: an unbuilt regular combat room")
	if index < 0:
		return
	# Enemies register (and are scaled) once the room enters the tree: on entry.
	_dungeon.enter_room(index, _dungeon.entry_door(index))
	for i in 3:
		await physics_frame
	var room := _dungeon.current_room
	_check(_dungeon.current_index == index, "setup: the Mage entered that room")
	var move := (1.0 + 0.01 * 4) * Tempo.ENEMY_MOVE
	var pace := (1.0 + 0.025 * 4) * Tempo.ENEMY_ATTACK
	var ok := true
	var count := 0
	for node in room.find_children("*", "Enemy", true, false):
		var enemy := node as Enemy
		if LevelScaling.category_of(enemy) != REGULAR:
			continue
		var base := (load(enemy.scene_file_path) as PackedScene).instantiate() as Enemy
		ok = ok and enemy.scaled and is_equal_approx(enemy.speed, minf(base.speed * move, maxf(base.speed,
				enemy.speed_cap if enemy.speed_cap > 0.0 else LevelScaling.MAX_PURSUER_SPEED)))
		ok = ok and is_equal_approx(enemy.attack_cooldown, base.attack_cooldown / pace)
		base.free()
		count += 1
	_check(count > 0 and ok, "level 5 room built by the Dungeon: %d regular enemies scaled once (move x%.3f, pace x%.3f)" % [count, move, pace])
	run.dungeon_level = 1


func _load_dungeon() -> void:
	RunState.seed_override = 4242
	change_scene_to_file(DUNGEON)
	for i in 600:
		if current_scene != null and current_scene.is_node_ready():
			break
		await physics_frame
	for i in 3:
		await physics_frame
	_dungeon = current_scene as Dungeon
	_holder = Node2D.new()
	_holder.position = Vector2(-5000, -5000)
	_holder.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(_holder)


func _spawn(name: String) -> Enemy:
	var enemy := (load("res://scenes/enemies/%s.tscn" % name) as PackedScene).instantiate() as Enemy
	_holder.add_child(enemy)
	return enemy


## `name` scaled by the Dungeon on difficulty `tier`, dungeon level `level` (no catch-up, no output modifier).
func _scaled(name: String, tier: int, level: int) -> Enemy:
	_dungeon.run_state.difficulty = tier
	_dungeon.run_state.dungeon_level = level
	var enemy := _spawn(name)
	_dungeon._scale_enemy(enemy, false)
	_dungeon.run_state.difficulty = Difficulty.Tier.NORMAL
	return enemy


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
