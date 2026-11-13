extends SceneTree
## Headless check of the combat pacing pass (Issue #47): Mage base speed and the
## capped speed bonus, enemy move-speed scaling (move/attack pace split, bounded
## catch-up, MAX_PURSUER_SPEED below the Mage's base speed), the Blood Monster's
## telegraphed dash, the Goblin's attack cycle (normal swings, then the
## telegraphed sword strike) and the casters'
## preferred range band.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_enemy_attacks.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const GOBLIN := "res://scenes/enemies/giant_goblin.tscn"
const BLOOD_MONSTER := "res://scenes/enemies/blood_monster.tscn"
const DEMON := "res://scenes/enemies/demon.tscn"
const PURSUERS: Array[String] = [GOBLIN, "res://scenes/enemies/demon.tscn", BLOOD_MONSTER,
		"res://scenes/enemies/brood_mother.tscn", "res://scenes/enemies/hexcaller.tscn", "res://scenes/enemies/abyss_warden.tscn"]
const CASTERS: Array[String] = ["res://scenes/enemies/demon_caster.tscn", "res://scenes/enemies/water_caster.tscn"]

var _failures := 0


## Stand-in Mage: in the "player" group, records the damage it takes.
class Dummy extends Node2D:
	var taken := 0.0
	var hits := 0

	func _init() -> void:
		add_to_group(&"player")

	func take_damage(amount: float) -> void:
		taken += amount
		hits += 1


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_test_player_speed()
	await _test_enemy_speed_scaling()
	await _test_blood_monster_dash()
	await _test_blood_monster_sidestep()
	await _test_dash_telegraph_drawn()
	_test_goblin_swing_mapping()
	await _test_goblin_cycle()
	_test_goblin_geometry()
	for tier in [Difficulty.Tier.NORMAL, Difficulty.Tier.HARD, Difficulty.Tier.ABYSSAL]:
		await _test_goblin_dash_timeline(tier)
	await _test_goblin_swing_area()
	await _test_goblin_step_out()
	await _test_goblin_anti_kiting()
	await _test_caster_band()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Speed -----------------------------------------------------------------------------------------

func _mage_base_speed() -> float:
	var mage := (load("res://scenes/mage/mage.tscn") as PackedScene).instantiate() as Mage
	var speed := mage.speed
	mage.free()
	return speed


func _test_player_speed() -> void:
	var base := _mage_base_speed()
	_check(is_equal_approx(base, 185.0), "Mage base speed %.0f (Issue #51 tempo: 150 -> 185)" % base)
	_check(is_equal_approx(RunState.ITEMS[&"swift_boots"]["speed"], 0.08) and is_equal_approx(RunState.ITEMS[&"bloodstone"]["speed"], 0.03)
			and is_equal_approx(RunState.RELICS[&"wind_relic"]["speed"], 0.05), "speed bonuses: Boots +8%, Bloodstone +3%, Wind Relic +5%")
	var run := RunState.new()
	run.configure(Difficulty.Tier.NORMAL)
	_check(is_equal_approx(run.move_speed_multiplier(), 1.0), "no bonus: x1.0")
	run.collected[&"swift_boots"] = 1
	run.relics.append(&"wind_relic")
	_check(is_equal_approx(run.move_speed_multiplier(), 1.13), "typical (1 Boots + Wind Relic): x1.13")
	run.collected[&"swift_boots"] = RunState.MAX_STACKS
	run.collected[&"bloodstone"] = RunState.MAX_STACKS
	_check(is_equal_approx(run.move_speed_multiplier(), 1.38), "early maximum (3 Boots, 3 Bloodstones, 1 Wind Relic): x1.38")
	for i in 20:
		run.relics.append(&"wind_relic")
	_check(is_equal_approx(run.move_speed_multiplier(), RunState.MAX_MOVE_SPEED_MULTIPLIER) and is_equal_approx(RunState.MAX_MOVE_SPEED_MULTIPLIER, 1.4),
			"21 Wind Relics stay at the x1.40 cap (%.2f)" % run.move_speed_multiplier())
	run.free()


func _test_enemy_speed_scaling() -> void:
	var base := _mage_base_speed()
	_check(LevelScaling.MAX_PURSUER_SPEED < base, "pursuer speed cap %.0f is below the Mage's base speed %.0f" % [LevelScaling.MAX_PURSUER_SPEED, base])
	_check(is_equal_approx(LevelScaling.enemy_move_pace(1), 1.0) and is_equal_approx(LevelScaling.enemy_move_pace(3), 1.02)
			and is_equal_approx(LevelScaling.enemy_move_pace(99), 1.0 + LevelScaling.MOVE_PACE_CAP), "regular move pace: +1%/level, capped at +10% (Issue #55)")
	_check(is_equal_approx(LevelScaling.enemy_pace(99), 1.0 + LevelScaling.PACE_CAP) and is_equal_approx(LevelScaling.PACE_CAP, 0.25),
			"regular attack pace capped at +25% (Issue #55)")
	_check(is_equal_approx(LevelScaling.player_catchup(1.0), 1.0) and is_equal_approx(LevelScaling.player_catchup(1.1), 1.05)
			and is_equal_approx(LevelScaling.player_catchup(10.0), 1.0 + LevelScaling.CATCHUP_CAP) and is_equal_approx(LevelScaling.player_catchup(0.5), 1.0),
			"catch-up: half the Mage's bonus, never below x1, capped at +10%")
	# Worst case: Abyssal, deep endless level, Mage at the speed cap.
	var run := RunState.new()
	run.configure(Difficulty.Tier.ABYSSAL)
	run.dungeon_level = 50
	for i in 20:
		run.relics.append(&"wind_relic")
	var move := run.enemy_move_pace_multiplier()
	_check(is_equal_approx(move, 1.1 * 1.1 * 1.1 * Tempo.ENEMY_MOVE), "worst-case move pace x%.3f (Abyssal x level cap x catch-up cap x tempo 1.25)" % move)
	_check(is_equal_approx(run.enemy_pace_multiplier(), 1.2 * 1.25 * Tempo.ENEMY_ATTACK), "attack pace: Abyssal x level cap x tempo 1.15 (x%.2f)" % run.enemy_pace_multiplier())
	var speeds := {}
	for path in PURSUERS:
		var enemy := (load(path) as PackedScene).instantiate() as Enemy
		root.add_child(enemy)
		var unscaled := enemy.speed
		var cooldown := enemy.attack_cooldown
		enemy.apply_scaling(1.0, 1.0, run.enemy_pace_multiplier(), 1.0, move)
		speeds[path] = enemy.speed
		if path == DEMON:
			_check(is_equal_approx(enemy.speed, enemy.speed_cap) and enemy.speed <= base * 1.14 + 0.001,
					"demon.tscn fallback speed (targets without base_walk_speed): %.0f -> %.1f at the highest scaling (its own cap)" % [unscaled, enemy.speed])
		else:
			_check(enemy.speed <= LevelScaling.MAX_PURSUER_SPEED + 0.001 and enemy.speed < base and enemy.speed >= unscaled,
					"%s: %.0f -> %.1f at the highest scaling (< Mage base %.0f)" % [path.get_file(), unscaled, enemy.speed, base])
		_check(is_equal_approx(enemy.attack_cooldown, cooldown / run.enemy_pace_multiplier()), "%s: attack rate uses the attack pace" % path.get_file())
		enemy.free()
	_check(speeds[DEMON] > speeds[GOBLIN] and speeds[GOBLIN] > speeds[BLOOD_MONSTER],
			"roles kept: Demon faster than Goblin, Goblin faster than Blood Monster")
	run.free()
	# Without a move multiplier apply_scaling() keeps the old single-pace behaviour (still capped).
	var goblin := (load(GOBLIN) as PackedScene).instantiate() as Enemy
	root.add_child(goblin)
	goblin.apply_scaling(1.0, 1.0, 2.0)
	_check(is_equal_approx(goblin.speed, LevelScaling.MAX_PURSUER_SPEED), "a single pace multiplier is capped too (%.1f)" % goblin.speed)
	goblin.free()
	await _test_demon_speed(base)


## Demon: walks at 0.9 x the Mage's base walking speed (permanent speed bonuses
## count; the Speed Potion, slows and run speed scaling do not).
func _test_demon_speed(mage_base: float) -> void:
	var mage := (load("res://scenes/mage/mage.tscn") as PackedScene).instantiate() as Mage
	root.add_child(mage)
	mage.global_position = Vector2(-3000, 0)
	var demon := (load(DEMON) as PackedScene).instantiate() as Enemy
	root.add_child(demon)
	demon.global_position = Vector2(-3000, -200)  # inside its 260 px detection
	await _frames(2)
	_check(is_equal_approx(demon.player_speed_ratio, 0.9), "Demon paces itself at 0.9x the Mage's speed")
	_check(is_equal_approx(demon.walk_speed(), 0.9 * mage_base), "Demon walks %.1f px/s (0.9 x %.0f)" % [demon.walk_speed(), mage_base])
	var start := demon.global_position
	await _frames(30)
	var measured := start.distance_to(demon.global_position) / 0.5
	_check(absf(measured - 0.9 * mage_base) <= 3.0, "Demon really moves at %.1f px/s towards the Mage" % measured)
	mage.speed_multiplier = 1.25  # Speed Potion active
	_check(is_equal_approx(demon.walk_speed(), 0.9 * mage_base), "Speed Potion on the Mage: Demon speed unchanged (%.1f)" % demon.walk_speed())
	mage.apply_slow(0.6, 2.0)
	_check(is_equal_approx(demon.walk_speed(), 0.9 * mage_base), "slowed Mage: Demon speed unchanged (%.1f)" % demon.walk_speed())
	mage.base_speed_multiplier = 1.13  # Boots + Wind Relic
	_check(is_equal_approx(demon.walk_speed(), 0.9 * mage_base * 1.13), "permanent speed bonuses: Demon follows them (%.1f)" % demon.walk_speed())
	mage.base_speed_multiplier = 1.0
	var run := RunState.new()
	run.configure(Difficulty.Tier.ABYSSAL)
	run.dungeon_level = 20
	demon.apply_scaling(1.0, 1.0, run.enemy_pace_multiplier(), 1.0, run.enemy_move_pace_multiplier(), run.enemy_recovery_multiplier())
	_check(is_equal_approx(demon.walk_speed(), 0.9 * mage_base), "run speed scaling (Abyssal L20, tempo) does not change it (%.1f)" % demon.walk_speed())
	run.free()
	demon.free()
	mage.free()


# --- Blood Monster dash ------------------------------------------------------------------------------

func _spawn(path: String, pos: Vector2) -> Enemy:
	var enemy := (load(path) as PackedScene).instantiate() as Enemy
	root.add_child(enemy)
	enemy.global_position = pos
	return enemy


func _dummy(pos: Vector2) -> Dummy:
	var d := Dummy.new()
	root.add_child(d)
	d.global_position = pos
	return d


func _test_blood_monster_dash() -> void:
	var dummy := _dummy(Vector2(200, 0))
	var monster := _spawn(BLOOD_MONSTER, Vector2.ZERO) as BloodMonster
	_check(monster != null and monster.elite and not ((monster as Object) is Goblin), "the Blood Monster scene uses BloodMonster (not the Goblin script)")
	var opening := monster.opening_delay
	var frames := await _frames_until(func() -> bool: return monster.phase != TelegraphedMelee.Phase.CHASE, 600)
	_check(frames / 60.0 >= opening - 0.05, "no dash during the %.1f s opening delay (started after %.2f s)" % [opening, frames / 60.0])
	_check(monster.phase == TelegraphedMelee.Phase.WINDUP and monster.dash().aim.is_equal_approx(Vector2.RIGHT)
			and is_equal_approx(monster.dash().distance, monster.dash_distance) and is_equal_approx(monster.dash().hit_radius, monster.dash_hit_radius),
			"windup: aim locked on the Mage, lane = dash length x hit width")
	var start := monster.global_position
	var windup := await _frames_until(func() -> bool: return monster.phase != TelegraphedMelee.Phase.WINDUP, 300)
	_check(windup / 60.0 >= monster.special_windup - 0.02, "the telegraph lasts the full %.2f s windup (%.2f s)" % [monster.special_windup, windup / 60.0])
	_check(is_zero_approx(dummy.taken), "no damage during the windup")
	_check(monster.global_position.distance_to(start) < 1.0, "it stands still while winding up")
	var active := await _frames_until(func() -> bool: return monster.phase != TelegraphedMelee.Phase.ACTIVE, 300)
	var travelled := monster.global_position.distance_to(start)
	_check(dummy.hits == 1 and is_equal_approx(dummy.taken, monster.special_damage), "the dash hits exactly once (%d hit, %.1f damage)" % [dummy.hits, dummy.taken])
	_check(travelled >= monster.dash_distance - 1.0 and travelled <= monster.dash_distance + monster.dash_speed / 60.0 + 1.0,
			"it dashes the locked distance (%.0f px)" % travelled)
	_check(monster.dash_speed > monster.speed * 4.0, "the dash (%.0f px/s) is far faster than walking (%.0f px/s)" % [monster.dash_speed, monster.speed])
	var recover_pos := monster.global_position
	var recover := await _frames_until(func() -> bool: return monster.phase != TelegraphedMelee.Phase.RECOVER, 300)
	_check(recover / 60.0 >= monster.special_recover - 0.02 and monster.global_position.distance_to(recover_pos) < 1.0 and dummy.hits == 1,
			"recovery: stands still for %.2f s without hitting" % (recover / 60.0))
	# Cooldown: keep the Mage in range; the next dash waits for special_cooldown.
	# Rooted so it cannot walk inside its minimum dash range while the cooldown runs.
	monster.speed = 0.0
	dummy.global_position = monster.global_position + Vector2(-200, 0)
	var next := await _frames_until(func() -> bool: return monster.phase == TelegraphedMelee.Phase.WINDUP, 600)
	var since := (windup + active + recover + next) / 60.0
	_check(next < 600 and since >= monster.special_cooldown - 0.05,
			"the next dash respects the %.1f s cooldown (%.2f s)" % [monster.special_cooldown, since])
	monster.free()
	dummy.free()


func _test_blood_monster_sidestep() -> void:
	var dummy := _dummy(Vector2(200, 0))
	var monster := _spawn(BLOOD_MONSTER, Vector2.ZERO) as BloodMonster
	await _frames(2)
	_check(monster.begin_special(), "setup: dash telegraph started")
	await _frames(10)
	dummy.global_position = Vector2(200, monster.dash_hit_radius + 30.0)
	await _frames_until(func() -> bool: return monster.phase == TelegraphedMelee.Phase.RECOVER, 300)
	_check(is_zero_approx(dummy.taken), "a perpendicular sidestep during the windup avoids the dash")
	monster.free()
	dummy.free()


## Issue #51 Stage 4 fix: TelegraphedMelee redraws every physics frame again
## (a Stage 3 edit had left queue_redraw() unreachable, so the regular Blood
## Monster's dash lane was never drawn). Counts real _draw() passes: the lane is
## drawn throughout the windup, erased right after it, and gone with the monster
## if it dies mid-windup. The Brood Mother's charge lane keeps working.
func _test_dash_telegraph_drawn() -> void:
	var dummy := _dummy(Vector2(200, 0))
	var monster := _spawn(BLOOD_MONSTER, Vector2.ZERO) as BloodMonster
	var draws := {"windup": 0, "after": 0}
	monster.draw.connect(func() -> void:
		if monster.phase == TelegraphedMelee.Phase.WINDUP:
			draws["windup"] += 1
		elif draws["windup"] > 0:
			draws["after"] += 1)
	await _frames(2)
	_check(monster.begin_special(), "lane setup: dash telegraph started")
	await _frames(1)
	_check(monster.dash().aim.is_equal_approx((dummy.global_position - monster.global_position).normalized())
			and is_equal_approx(monster.dash().distance, monster.dash_distance) and is_equal_approx(monster.dash().hit_radius, monster.dash_hit_radius),
			"Blood Monster: lane from its feet towards the Mage, dash length x hit width")
	var windup := await _frames_until(func() -> bool: return monster.phase != TelegraphedMelee.Phase.WINDUP, 300)
	_check(draws["windup"] >= windup - 2, "Blood Monster: the dash lane is drawn every frame of the windup (%d draws / %d frames)" % [draws["windup"], windup])
	_check(monster.z_index > -10 and monster.z_as_relative, "Blood Monster: the lane is drawn on the monster (z %d), above the room floor (z -10)" % monster.z_index)
	await _frames(2)
	_check(draws["after"] >= 1, "Blood Monster: the lane is erased (redrawn without it) once the windup ends")
	monster.free()
	# Killed mid-windup: the lane goes with the monster.
	monster = _spawn(BLOOD_MONSTER, Vector2.ZERO) as BloodMonster
	await _frames(2)
	monster.begin_special()
	await _frames(10)
	monster.take_damage(1.0e9)
	await _frames(1)
	_check(not is_instance_valid(monster), "Blood Monster: killed during the windup -> lane removed with it")
	await _frames(60)
	# Brood Mother (miniboss) charge lane.
	var mother := _spawn("res://scenes/enemies/brood_mother.tscn", Vector2.ZERO) as BroodMother
	var mother_draws := [0]
	mother.draw.connect(func() -> void:
		if mother.state == Miniboss.State.WINDUP and mother.current_attack == &"charge":
			mother_draws[0] += 1)
	await _frames(2)
	_check(mother.begin_charge(), "Brood Mother: charge telegraph started")
	var mw := await _frames_until(func() -> bool: return mother.state != Miniboss.State.WINDUP, 300)
	_check(mother_draws[0] >= mw - 2, "Brood Mother: charge lane drawn every frame of the windup (%d / %d)" % [mother_draws[0], mw])
	mother.free()
	dummy.free()


# --- Goblin attack cycle ------------------------------------------------------------------------------

## Expected normal swings before the special: tier -> [Lv 1-2, Lv 3-4, Lv 5+].
const GOBLIN_SWINGS := {
	Difficulty.Tier.NORMAL: [3, 2, 2],
	Difficulty.Tier.HARD: [2, 2, 1],
	Difficulty.Tier.ABYSSAL: [2, 1, 1],
}


func _test_goblin_swing_mapping() -> void:
	var all_ok := true
	var table_ok := true
	for tier: int in GOBLIN_SWINGS:
		# configure() works once per RunState: one run per tier.
		var run := RunState.new()
		run.configure(tier)
		var previous := 3
		for level in range(1, 31):
			run.dungeon_level = level
			var swings := run.goblin_swings_before_special()
			all_ok = all_ok and swings >= 1 and swings <= 3 and swings <= previous
			previous = swings
			var bracket := 0 if level <= 2 else (1 if level <= 4 else 2)
			table_ok = table_ok and swings == GOBLIN_SWINGS[tier][bracket]
		run.free()
	_check(table_ok, "swings before the special follow the difficulty x level table")
	_check(all_ok, "always 1-3 and never more on a deeper level")
	for bracket in 3:
		var n: int = GOBLIN_SWINGS[Difficulty.Tier.NORMAL][bracket]
		var h: int = GOBLIN_SWINGS[Difficulty.Tier.HARD][bracket]
		var a: int = GOBLIN_SWINGS[Difficulty.Tier.ABYSSAL][bracket]
		_check(n >= h and h >= a, "bracket %d: Normal %d >= Hard %d >= Abyssal %d" % [bracket, n, h, a])


## Rooted goblin next to the dummy (inside its contact range) with `swings` swings per cycle.
func _cycle_goblin(swings: int, dummy_pos: Vector2 = Vector2(30, 0)) -> Array:
	var dummy := _dummy(dummy_pos)
	var goblin := _spawn(GOBLIN, Vector2.ZERO) as Goblin
	goblin.speed = 0.0
	goblin.swings_before_special = swings
	return [goblin, dummy]


func _test_goblin_cycle() -> void:
	for swings in [1, 2, 3]:
		var pair := _cycle_goblin(swings)
		var goblin: Goblin = pair[0]
		var dummy: Dummy = pair[1]
		var waited := await _frames_until(func() -> bool: return goblin.phase == TelegraphedMelee.Phase.WINDUP, 900)
		_check(waited < 900 and goblin.swings_total == swings and dummy.hits == swings
				and is_equal_approx(dummy.taken, goblin.contact_damage * swings),
				"N=%d: exactly %d normal swing(s) hit before the special (%d swings, %d hits)" % [swings, swings, goblin.swings_total, dummy.hits])
		goblin.free()
		dummy.free()
	# Full cycle with 2 swings: swings -> telegraph -> strike -> recovery -> swings again.
	var pair := _cycle_goblin(2)
	var goblin: Goblin = pair[0]
	var dummy: Dummy = pair[1]
	await _frames_until(func() -> bool: return goblin.phase == TelegraphedMelee.Phase.WINDUP, 900)
	_check(goblin.swing_phase == Goblin.Swing.NONE and goblin.swings_done == 0 and goblin.swings_total == 2,
			"the special starts only after the last swing has recovered")
	var hits := dummy.hits
	var windup := 0
	var swing_during_special := false
	while goblin.phase == TelegraphedMelee.Phase.WINDUP and windup < 300:
		swing_during_special = swing_during_special or goblin.swing_phase != Goblin.Swing.NONE
		await physics_frame
		windup += 1
	_check(dummy.hits == hits and windup / 60.0 >= goblin.special_windup - 0.02,
			"no damage during the %.2f s warning (%.2f s)" % [goblin.special_windup, windup / 60.0])
	var active := 0
	while goblin.phase == TelegraphedMelee.Phase.ACTIVE and active < 300:
		swing_during_special = swing_during_special or goblin.swing_phase != Goblin.Swing.NONE
		await physics_frame
		active += 1
	_check(is_equal_approx(goblin.strike_active, 0.12) and active / 60.0 <= goblin.strike_active + 0.04,
			"the strike's active window is unchanged (%.2f s)" % (active / 60.0))
	_check(dummy.hits == hits + 1 and is_equal_approx(dummy.taken, goblin.contact_damage * 2 + goblin.special_damage),
			"the strike hits once for %.0f" % goblin.special_damage)
	var recover := 0
	while goblin.phase == TelegraphedMelee.Phase.RECOVER and recover < 300:
		swing_during_special = swing_during_special or goblin.swing_phase != Goblin.Swing.NONE
		await physics_frame
		recover += 1
	_check(not swing_during_special and dummy.hits == hits + 1, "no other attack starts during the special or its recovery")
	var resumed := await _frames_until(func() -> bool: return goblin.swings_total >= 3 and goblin.swing_phase == Goblin.Swing.RECOVER, 300)
	_check(resumed < 300 and goblin.phase == TelegraphedMelee.Phase.CHASE and dummy.hits == hits + 2,
			"after recovery the goblin swings normally again")
	await _frames_until(func() -> bool: return goblin.phase == TelegraphedMelee.Phase.WINDUP, 600)
	_check(goblin.swings_total == 4, "the next special follows after 2 more swings (%d swings total)" % goblin.swings_total)
	goblin.free()
	dummy.free()


## Issue #51 Goblin Dash timeline on difficulty `tier` (scaled like a deep
## dungeon level, plus a 3x pace stand-in for a future Tempo system): tracking
## 0.30 s, locked warning 0.35 s, anticipation 0.30 s (standing still, distinct
## state), strike 0.12 s that still lunges and hits once.
func _test_goblin_dash_timeline(tier: int) -> void:
	var label := Difficulty.display_name(tier)
	var data := Difficulty.data(tier)
	var dummy := _dummy(Vector2(100, 0))
	var goblin := _spawn(GOBLIN, Vector2.ZERO) as Goblin
	var pace: float = data["enemy_pace"] * LevelScaling.enemy_pace(8) * 3.0
	goblin.apply_scaling(1.0, 1.0, pace)
	_check(is_equal_approx(goblin.special_track_time, 0.3) and is_equal_approx(goblin.special_lock_time, 0.35)
			and is_equal_approx(goblin.special_anticipation, 0.3) and is_equal_approx(goblin.special_windup, 0.95),
			"%s Goblin Dash: 0.30 tracking + 0.35 locked + 0.30 anticipation = 0.95 s windup, even at %.2fx pace" % [label, pace])
	await physics_frame
	var origin := goblin.global_position
	goblin.begin_special()
	var counts := {&"track": 0, &"locked": 0, &"anticipation": 0, &"active": 0}
	var order: Array[StringName] = []
	var moved := 0.0
	var hit_in_windup := false
	for i in 200:
		var key: StringName
		match goblin.phase:
			TelegraphedMelee.Phase.WINDUP:
				key = &"anticipation" if goblin.is_anticipating() else (&"locked" if goblin.is_aim_locked() else &"track")
				moved = maxf(moved, goblin.global_position.distance_to(origin))
				hit_in_windup = hit_in_windup or dummy.hits > 0
			TelegraphedMelee.Phase.ACTIVE:
				key = &"active"
			_:
				break
		counts[key] += 1
		if order.is_empty() or order.back() != key:
			order.append(key)
		await physics_frame
	var t := func(k: StringName) -> float: return counts[k] / 60.0
	_check(order == [&"track", &"locked", &"anticipation", &"active"],
			"%s Goblin Dash: phases run tracking -> locked -> anticipation -> strike, each exactly once (%s)" % [label, order])
	_check(absf(t.call(&"track") - 0.3) <= 0.017 and absf(t.call(&"locked") - 0.35) <= 0.017
			and absf(t.call(&"anticipation") - 0.3) <= 0.017 and absf(t.call(&"active") - 0.12) <= 0.017,
			"%s Goblin Dash timeline: tracking %.2f s, locked %.2f s, anticipation %.2f s, strike %.2f s"
			% [label, t.call(&"track"), t.call(&"locked"), t.call(&"anticipation"), t.call(&"active")])
	var reaction: float = t.call(&"locked") + t.call(&"anticipation")
	var total: float = t.call(&"track") + reaction
	_check(reaction >= 0.65 - 0.017 and reaction > 0.33 + 0.25 and absf(total - 0.95) <= 0.04,
			"%s Goblin Dash: %.2f s to react after the lock (was 0.30-0.33 s), %.2f s total warning" % [label, reaction, total])
	_check(moved < 0.5 and not hit_in_windup, "%s Goblin Dash: the goblin stands still and deals no damage during the whole warning" % label)
	_check(dummy.hits == 1 and is_equal_approx(dummy.taken, goblin.special_damage)
			and goblin.global_position.distance_to(origin) > goblin.lunge * 0.8 and goblin.lunge > 0.0,
			"%s Goblin Dash: the strike still lunges (%.0f of %.0f px) and hits once for %.0f" % [label, goblin.global_position.distance_to(origin), goblin.lunge, dummy.taken])
	goblin.free()
	dummy.free()


func _test_goblin_geometry() -> void:
	var goblin := _spawn(GOBLIN, Vector2(400, 400)) as Goblin
	_check(is_equal_approx(goblin.strike_length, 80.0 * 1.35) and is_equal_approx(goblin.strike_half_width, 18.0 * 1.35),
			"strike area is 1.35x the original 80 x 36 (%.0f x %.1f)" % [goblin.strike_length, goblin.strike_half_width * 2.0])
	_check(goblin.special_max_range <= goblin.lunge_max + goblin.lunge_stop and goblin.lunge_stop < goblin.strike_length,
			"engagement range %.0f px: the lunge plus blade always reaches past the Mage" % goblin.special_max_range)
	var strike_ok := true
	var swing_ok := true
	for aim: Vector2 in [Vector2.RIGHT, Vector2(1, 1).normalized(), Vector2.UP]:
		goblin.aim = aim
		goblin.swing_aim = aim
		var strike := goblin.strike_polygon()
		var sector := goblin.swing_polygon()
		for x in range(-140, 141, 6):
			for y in range(-140, 141, 6):
				var local := Vector2(x, y) + Vector2(0.5, 0.5)
				strike_ok = strike_ok and Geometry2D.is_point_in_polygon(local, strike) == goblin.in_strike_area(goblin.global_position + local)
				# The drawn arc is a 12-segment approximation: skip points on its rim.
				if absf(local.length() - goblin.swing_reach) > 1.0:
					swing_ok = swing_ok and Geometry2D.is_point_in_polygon(local, sector) == goblin.in_swing_area(goblin.global_position + local)
	_check(strike_ok, "telegraph / slash rectangle and the strike hitbox are the same area (3 aims)")
	_check(swing_ok, "the drawn swing sector and the swing hitbox are the same area")
	goblin.free()


## One swing aimed RIGHT: the dummy triggers it from 30 px, then moves to `local`
## during the windup. Returns the damage taken from that swing.
func _swing_at(local: Vector2) -> float:
	var pair := _cycle_goblin(3)
	var goblin: Goblin = pair[0]
	var dummy: Dummy = pair[1]
	await _frames_until(func() -> bool: return goblin.swing_phase == Goblin.Swing.WINDUP, 300)
	dummy.global_position = local
	await _frames_until(func() -> bool: return goblin.swing_phase == Goblin.Swing.RECOVER, 300)
	var taken := dummy.taken
	goblin.free()
	dummy.free()
	return taken


func _test_goblin_swing_area() -> void:
	var goblin := _spawn(GOBLIN, Vector2.ZERO) as Goblin
	_check(is_equal_approx(goblin.swing_reach, 60.0) and is_equal_approx(goblin.swing_half_angle, 70.0),
			"swing area: %.0f px reach, %.0f degree arc (was 48 px, 120 degrees)" % [goblin.swing_reach, goblin.swing_half_angle * 2.0])
	_check(is_equal_approx(goblin.swing_windup, 0.25) and is_equal_approx(goblin.swing_recover, 0.3)
			and is_equal_approx(goblin.attack_cooldown, 1.0) and is_equal_approx(goblin.contact_damage, 12.0),
			"swing timing (0.25 s / 0.3 s / 1.0 s cooldown) and damage 12 unchanged")
	_check(goblin.swing_slash_time > 0.0 and goblin.swing_slash_time <= goblin.swing_recover,
			"the slash effect (%.2f s) ends within the recovery" % goblin.swing_slash_time)
	_check(is_equal_approx(goblin.special_windup, 0.95) and is_equal_approx(goblin.special_damage, 14.0) and is_equal_approx(goblin.strike_active, 0.12)
			and is_equal_approx(goblin.strike_length, 108.0) and is_equal_approx(goblin.strike_half_width, 24.3)
			and is_equal_approx(goblin.lunge_max, 150.0) and is_equal_approx(goblin.lunge_stop, 30.0),
			"the special strike: 0.95 s warning (Issue #51), unchanged 0.12 s strike, 14 damage, 108 x 48.6, 150 px lunge")
	goblin.free()
	var cases := [
		[Vector2(55, 0), true, "55 px straight ahead"],
		[Vector2.from_angle(deg_to_rad(65.0)) * 57.0, true, "57 px at 65 degrees"],
		[Vector2.from_angle(deg_to_rad(-65.0)) * 57.0, true, "57 px at -65 degrees"],
		[Vector2(63, 0), false, "63 px straight ahead (beyond reach)"],
		[Vector2.from_angle(deg_to_rad(76.0)) * 40.0, false, "40 px at 76 degrees (outside the arc)"],
		[Vector2(-30, 0), false, "behind the goblin"],
	]
	for c: Array in cases:
		var taken := await _swing_at(c[0])
		var hit := taken > 0.0
		_check(hit == c[1] and (not hit or is_equal_approx(taken, 12.0)),
				"%s: %s" % [c[2], "hit for 12" if c[1] else "not hit"])


func _test_goblin_step_out() -> void:
	var pair := _cycle_goblin(1)
	var goblin: Goblin = pair[0]
	var dummy: Dummy = pair[1]
	await _frames_until(func() -> bool: return goblin.is_aim_locked(), 600)
	var taken := dummy.taken
	dummy.global_position = Vector2(30, goblin.strike_half_width + 20.0)
	await _frames_until(func() -> bool: return goblin.phase == TelegraphedMelee.Phase.RECOVER, 300)
	_check(is_equal_approx(dummy.taken, taken), "stepping out of the rectangle after the aim locks avoids the strike")
	goblin.free()
	dummy.free()
	# A Mage that walks out of the swing during its windup is not hit either.
	pair = _cycle_goblin(3)
	goblin = pair[0]
	dummy = pair[1]
	await _frames_until(func() -> bool: return goblin.swing_phase == Goblin.Swing.WINDUP, 300)
	dummy.global_position = Vector2(-60, 0)
	await _frames_until(func() -> bool: return goblin.swing_phase == Goblin.Swing.RECOVER, 300)
	_check(goblin.swings_total == 1 and dummy.hits == 0, "a normal swing can be dodged during its windup")
	goblin.free()
	dummy.free()


## Keeps the dummy at `offset` from the goblin every physics frame (a Mage that
## kites at a fixed distance) until `until` holds or `max_frames` pass. Returns the frames waited.
func _kite(goblin: Goblin, dummy: Dummy, offset: Vector2, until: Callable, max_frames: int) -> int:
	for i in max_frames:
		if until.call():
			return i
		dummy.global_position = goblin.global_position + offset
		await physics_frame
	return max_frames


## A goblin (3 swings per cycle, normal speed) chased by nothing but a kiting Mage.
func _kite_goblin() -> Array:
	var dummy := _dummy(Vector2(120, 0))
	var goblin := _spawn(GOBLIN, Vector2.ZERO) as Goblin
	goblin.swings_before_special = 3
	return [goblin, dummy]


func _test_goblin_anti_kiting() -> void:
	# Kiting at 120 px: no swing ever lands, yet the special follows after the patience.
	var pair := _kite_goblin()
	var goblin: Goblin = pair[0]
	var dummy: Dummy = pair[1]
	var waited := await _kite(goblin, dummy, Vector2(120, 0), func() -> bool: return goblin.phase == TelegraphedMelee.Phase.WINDUP, 600)
	var limit := maxf(goblin.opening_delay, goblin.kite_patience) + 0.1
	_check(waited < 600 and waited / 60.0 <= limit and goblin.swings_total == 0 and goblin.special_from_kiting,
			"kiting at 120 px: the special starts after %.2f s without any swing (patience %.1f s)" % [waited / 60.0, goblin.kite_patience])
	_check(goblin.lunge > 0.0 and goblin.lunge <= goblin.lunge_max, "the strike lunges towards the kiting Mage (%.0f px)" % goblin.lunge)
	# While tracking, the aim follows the Mage; after the lock it does not.
	var tracked := await _kite(goblin, dummy, Vector2(110, 40), func() -> bool: return goblin.is_aim_locked(), 120)
	var locked_aim := goblin.aim
	var expected := Vector2(110, 40).normalized()
	_check(tracked / 60.0 <= goblin.special_track_time + 0.05 and locked_aim.distance_to(expected) < 0.05,
			"the aim follows the Mage for %.2f s, then locks" % goblin.special_track_time)
	var locked_reach := goblin.strike_reach()
	var origin := goblin.strike_origin()
	# Sidestep after the lock: perpendicular to the locked aim, out of the rectangle.
	dummy.global_position = origin + locked_aim * 120.0 + locked_aim.orthogonal() * (goblin.strike_half_width + 30.0)
	var hits := dummy.hits
	var aim_kept := true
	while goblin.phase == TelegraphedMelee.Phase.WINDUP or goblin.phase == TelegraphedMelee.Phase.ACTIVE:
		aim_kept = aim_kept and goblin.aim.is_equal_approx(locked_aim) and is_equal_approx(goblin.strike_reach(), locked_reach)
		await physics_frame
	_check(aim_kept, "aim and reach stay locked until the strike ends")
	_check(dummy.hits == hits, "a sidestep after the lock dodges the lunging strike")
	_check(goblin.global_position.distance_to(origin) > goblin.lunge * 0.8, "the goblin lunged %.0f px along the locked aim" % goblin.global_position.distance_to(origin))
	# Recovery, then back to the normal cycle: the next close Mage gets swings first.
	await _frames_until(func() -> bool: return goblin.phase == TelegraphedMelee.Phase.CHASE, 300)
	await _frames(2)
	_check(goblin.swings_done == 0 and goblin.lunge == 0.0, "after recovery the swing count restarts")
	await _kite(goblin, dummy, Vector2(25, 0), func() -> bool: return goblin.swings_total >= 1, 300)
	_check(goblin.swings_total == 1 and goblin.phase == TelegraphedMelee.Phase.CHASE and not goblin.special_from_kiting,
			"a Mage in melee range is met with normal swings again")
	goblin.free()
	dummy.free()

	# A late reaction is punished: standing through the locked warning and only
	# running straight away during the anticipation is still hit.
	pair = _kite_goblin()
	goblin = pair[0]
	dummy = pair[1]
	await _kite(goblin, dummy, Vector2(120, 0), func() -> bool: return goblin.is_aim_locked(), 600)
	var run_dir := goblin.aim
	await _frames_until(func() -> bool: return goblin.is_anticipating(), 120)
	while goblin.phase == TelegraphedMelee.Phase.WINDUP or goblin.phase == TelegraphedMelee.Phase.ACTIVE:
		dummy.global_position += run_dir * 150.0 / 60.0
		await physics_frame
	_check(dummy.hits == 1 and is_equal_approx(dummy.taken, goblin.special_damage),
			"running straight away only during the anticipation does not escape the strike (%.0f damage)" % dummy.taken)
	goblin.free()
	dummy.free()
	# Reacting at the lock (0.65 s before the strike) escapes even straight away at base speed.
	pair = _kite_goblin()
	goblin = pair[0]
	dummy = pair[1]
	await _kite(goblin, dummy, Vector2(120, 0), func() -> bool: return goblin.is_aim_locked(), 600)
	run_dir = goblin.aim
	while goblin.phase == TelegraphedMelee.Phase.WINDUP or goblin.phase == TelegraphedMelee.Phase.ACTIVE:
		dummy.global_position += run_dir * 150.0 / 60.0
		await physics_frame
	_check(dummy.hits == 0, "reacting at the lock: walking straight away at base speed escapes (0.65 s reaction window)")
	goblin.free()
	dummy.free()

	# No attacks from unreasonable distances: kiting beyond the engagement range.
	pair = _kite_goblin()
	goblin = pair[0]
	dummy = pair[1]
	var far := goblin.special_max_range + 50.0
	var frames := await _kite(goblin, dummy, Vector2(far, 0), func() -> bool: return goblin.phase != TelegraphedMelee.Phase.CHASE, 300)
	_check(frames == 300 and goblin.swings_total == 0, "no special from %.0f px (engagement range %.0f px)" % [far, goblin.special_max_range])
	# Once it gets within range (patience already spent), the special follows at once.
	frames = await _kite(goblin, dummy, Vector2(150, 0), func() -> bool: return goblin.phase == TelegraphedMelee.Phase.WINDUP, 60)
	_check(frames <= 2, "within %.0f px the special starts at once after the patience ran out" % goblin.special_max_range)
	goblin.free()
	dummy.free()


# --- Casters -----------------------------------------------------------------------------------------

func _test_caster_band() -> void:
	for path in CASTERS:
		var caster := (load(path) as PackedScene).instantiate() as RangedEnemy
		var reach := caster.projectile_speed * caster.projectile.lifetime
		_check(caster.detection_radius >= caster.attack_range and caster.retreat_distance < caster.attack_range and reach >= caster.attack_range,
				"%s: detection %.0f >= range %.0f > retreat %.0f, bolt reach %.0f" % [path.get_file(), caster.detection_radius, caster.attack_range,
				caster.retreat_distance, reach])
		caster.free()
	# Water Caster (the long-range one): too close -> backs off; in the band -> holds and fires.
	var dummy := _dummy(Vector2.ZERO)
	var caster := _spawn(CASTERS[1], Vector2(120, 0)) as RangedEnemy
	await _frames(30)
	_check(caster.global_position.x > 120.0, "too close: the caster backs away (%.0f px)" % caster.global_position.x)
	var band := (caster.retreat_distance + caster.attack_range) / 2.0
	caster.global_position = Vector2(band, 0)
	caster._attack_cooldown_left = 0.0
	var shots := [0]
	caster.fired.connect(func(_p: Projectile) -> void: shots[0] += 1)
	await _frames(60)
	_check(absf(caster.global_position.x - band) < 2.0 and shots[0] >= 1, "inside the band (%.0f px) it holds position and fires" % band)
	caster.global_position = Vector2(caster.attack_range + 20.0, 0)
	await _frames(20)
	_check(caster.global_position.x < caster.attack_range + 20.0, "out of range but detected: it walks back into range")
	for child in root.get_children():
		if child is Projectile:
			child.queue_free()
	caster.free()
	dummy.free()


# --- Helpers -----------------------------------------------------------------------------------------

## Waits physics frames until `condition` holds (or `max_frames`); returns the frames waited.
func _frames_until(condition: Callable, max_frames: int) -> int:
	for i in max_frames:
		if condition.call():
			return i
		await physics_frame
	return max_frames


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
