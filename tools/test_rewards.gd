extends SceneTree
## Headless check of enemy XP/currency rewards, run-level progression and
## leveling in the dungeon run (scenes/dungeon/dungeon.tscn).
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_rewards.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENE := "res://scenes/dungeon/dungeon.tscn"
const HALL := 0
const CRYPT := 1
const CAVE := 2

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_test_run_state_unit()

	change_scene_to_file(SCENE)
	await _frames(3)
	_bind()
	var base_max_hp := _mage.health.max_health
	_check(_run.level == 1 and _run.xp == 0 and _run.currency == 0, "run starts at Lv 1, 0 XP, 0 currency")
	_check(_hud_text() == "Lv 1   XP 0/50   Gold 0", "HUD shows starting level/XP/currency (%s)" % _hud_text())

	# --- Per-enemy reward values ---
	var goblin := load("res://scenes/enemies/giant_goblin.tscn").instantiate() as Enemy
	var demon := load("res://scenes/enemies/demon.tscn").instantiate() as Enemy
	var blood := load("res://scenes/enemies/blood_monster.tscn").instantiate() as Enemy
	var caster := load("res://scenes/enemies/demon_caster.tscn").instantiate() as Enemy
	_check(goblin.xp_reward == 10 and goblin.currency_reward == 5, "Giant Goblin uses default rewards (10 XP, 5)")
	_check(demon.xp_reward == 15 and demon.currency_reward == 8, "Demon overrides rewards (15 XP, 8)")
	_check(blood.xp_reward == 25 and blood.currency_reward == 12, "Blood Monster overrides rewards (25 XP, 12)")
	_check(caster.xp_reward == 20 and caster.currency_reward == 10, "Demon Caster overrides rewards (20 XP, 10)")
	for e in [goblin, demon, blood, caster]:
		e.free()

	# --- Hall: rewards granted exactly once per death ---
	var hall := _dungeon.current_room
	hall.start_encounter()
	await _frames(1)
	var enemies := hall.get_node(^"Enemies").get_children()
	var first := enemies[0] as Enemy
	first.take_damage(10.0)
	_check(_run.xp == 0 and _run.currency == 0, "damage alone grants no reward")
	first.take_damage(9999.0)
	first.take_damage(9999.0)
	first.died.emit()  # duplicate death signal before the enemy is freed
	await _frames(2)
	_check(_run.xp == 10 and _run.currency == 5, "one kill grants rewards once (XP %d, currency %d)" % [_run.xp, _run.currency])
	await _kill_all(hall)
	_check(_run.xp == 30 and _run.currency == 15 and _run.level == 1, "Hall cleared: 30 XP, 15 currency, Lv 1")
	_check(_hud_text() == "Lv 1   XP 30/50   Gold 15", "HUD updates after kills (%s)" % _hud_text())

	# --- Crypt: persists across transition; level-up at 50 XP ---
	var run_before := _run
	_mage.take_damage(30.0)
	_dungeon.enter_room(CRYPT, &"DoorLeft")
	await _frames(2)
	var crypt := _dungeon.current_room
	_check(_dungeon.run_state == run_before and _run.xp == 30 and _run.currency == 15,
			"XP and currency persist into the Crypt")
	var hp_before := _mage.health.current
	var goblins := crypt.get_node(^"Enemies").get_children().filter(func(e: Node) -> bool: return e.name.begins_with("GiantGoblin"))
	(goblins[0] as Enemy).take_damage(9999.0)
	await _frames(2)
	_check(_run.level == 1 and _run.xp == 40, "Lv 1 at 40 XP (below threshold)")
	(goblins[1] as Enemy).take_damage(9999.0)
	await _frames(2)
	_check(_run.level == 2 and _run.xp == 0 and _run.xp_to_next_level() == 100,
			"Lv 2 reached at 50 XP, next threshold 100 (Lv %d, XP %d)" % [_run.level, _run.xp])
	_check(is_equal_approx(_mage.health.max_health, base_max_hp + 20.0), "level-up: Mage max HP +20 (%.0f)" % _mage.health.max_health)
	_check(is_equal_approx(_mage.health.current, hp_before + 20.0), "level-up: Mage restores 20 HP (%.0f)" % _mage.health.current)
	var bar := _mage.get_node(^"HealthBar") as ProgressBar
	_check(is_equal_approx(bar.max_value, _mage.health.max_health) and is_equal_approx(bar.value, _mage.health.current),
			"Mage health bar reflects the level-up")
	await _kill_all(crypt)
	_check(_run.level == 2 and _run.xp == 35 and _run.currency == 42, "Crypt cleared: Lv 2, 35 XP, 42 currency")

	# --- Revisiting a cleared room grants nothing ---
	_dungeon.enter_room(HALL, &"DoorRight")
	await _frames(3)
	_dungeon.enter_room(CRYPT, &"DoorLeft")
	await _frames(3)
	_check(_run.xp == 35 and _run.currency == 42, "revisiting cleared rooms grants no extra rewards")

	# --- Cave ---
	_dungeon.enter_room(CAVE, &"DoorBottom")
	await _frames(2)
	await _kill_all(_dungeon.current_room)
	_check(_run.level == 2 and _run.xp == 90 and _run.currency == 70, "Cave cleared (incl. Demon Caster): Lv 2, 90 XP, 70 currency")
	_check(_hud_text() == "Lv 2   XP 90/100   Gold 70", "HUD after full run (%s)" % _hud_text())

	# --- Restart resets the run ---
	_mage.take_damage(9999.0)
	await _frames(1)
	(current_scene.get_node(^"GameOverOverlay") as GameOverOverlay).restart()
	await _frames(3)
	_bind()
	_check(_run != run_before and _run.level == 1 and _run.xp == 0 and _run.currency == 0,
			"Restart resets XP, currency and level")
	_check(is_equal_approx(_mage.health.max_health, base_max_hp) and is_equal_approx(_mage.health.current, base_max_hp),
			"Restart resets Mage max HP")
	_check(_hud_text() == "Lv 1   XP 0/50   Gold 0", "HUD reset after Restart (%s)" % _hud_text())

	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_run_state_unit() -> void:
	var run := RunState.new()
	var levels: Array[int] = []
	run.leveled_up.connect(func(l: int) -> void: levels.append(l))
	run.add_rewards(49, 3)
	_check(run.level == 1 and run.xp == 49 and levels.is_empty(), "RunState: 49 XP stays Lv 1")
	run.add_rewards(51, 0)  # 100 total: 50 -> Lv 2, 50 left (< 100)
	_check(run.level == 2 and run.xp == 50 and levels == [2] and run.currency == 3,
			"RunState: level-up carries leftover XP (Lv %d, XP %d, %s)" % [run.level, run.xp, levels])
	run.add_rewards(500, 0)  # Lv 3 is the cap: excess XP is discarded, no Lv 4+
	_check(run.level == 3 and run.xp == 0 and levels == [2, 3] and run.is_max_level(),
			"RunState: capped at Lv 3, excess XP discarded (Lv %d, XP %d, %s)" % [run.level, run.xp, levels])
	run.add_rewards(999, 0)
	_check(run.level == 3 and run.xp == 0 and levels == [2, 3], "RunState: more XP at cap emits no level-up")
	run.reset()
	_check(run.level == 1 and run.xp == 0 and run.currency == 0, "RunState: reset() clears progression")
	run.free()


func _bind() -> void:
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage
	_run = _dungeon.run_state


func _kill_all(room: Room) -> void:
	for enemy in room.get_node(^"Enemies").get_children():
		(enemy as Enemy).take_damage(9999.0)
	await _frames(2)


func _hud_text() -> String:
	return (current_scene.get_node(^"RunHud/RunLabel") as Label).text


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
