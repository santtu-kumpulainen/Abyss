extends SceneTree
## Headless check of Mage level progression (Lv 1-3 cap, level bonuses) and the
## starting-room anvil UpgradeStation in the dungeon run (scenes/dungeon/dungeon.tscn).
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_progression.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SEED := 4242
const SCENE := "res://scenes/dungeon/dungeon.tscn"
const FIRE_BALL := "res://scenes/spells/fire_ball/fire_ball.tres"
const HALL := 0

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	RunState.seed_override = SEED
	var fire_ball := load(FIRE_BALL) as Spell
	var base_damage := fire_ball.damage
	var base_cooldown := fire_ball.cooldown

	var scene_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(SCENE)
	await _wait_for_scene(scene_id)
	_bind()
	var base_max_hp := _mage.health.max_health
	var station := _station()
	_check(station != null and station.run_state == _run, "Hall (starting room) has an UpgradeStation bound to the RunState")
	_check(is_equal_approx(_cast_damage(), base_damage) and is_equal_approx(_cast_cooldown(), base_cooldown),
			"Lv 1: Fire Ball at base damage/cooldown")
	_check(_dungeon.current_room.state == Room.State.IDLE, "station does not start the Hall encounter")

	# --- Station interaction: out of range, insufficient gold ---
	station.set_open(true)
	_check(not station.is_open, "menu cannot open while the Mage is out of range")
	await _move_mage(station.global_position + Vector2(50, 0))
	_check(station.is_usable() and (station.get_node(^"Prompt") as Label).visible, "prompt shows when the Mage is near")
	station.set_open(true)
	_check(station.is_open and (station.get_node(^"Menu") as CanvasLayer).visible, "menu opens near the station")
	var menu_text := (station.get_node(^"Menu/Panel/MenuLabel") as Label).text
	_check(menu_text.contains("Lv 1   Gold 0") and menu_text.contains("Vitality (0/3) - 100 gold, Lv 1: +20 max HP per stack")
			and menu_text.contains("Quick Cast (0/3) - 200 gold, Lv 2: -5% spell cooldown per stack  [requires Lv 2]")
			and menu_text.contains("Ember Core (0/3) - 300 gold, Lv 3: +10% spell damage per stack  [requires Lv 3]"),
			"menu lists gold, upgrade names, costs, required levels and effects")
	_check(not station.purchase(&"vitality") and _run.currency == 0 and not _run.is_purchased(&"vitality")
			and is_equal_approx(_mage.health.max_health, base_max_hp), "insufficient gold blocks purchase")

	# --- Purchases and level requirements ---
	_run.add_rewards(0, 1000)
	_mage.take_damage(30.0)
	var hp_before := _mage.health.current
	_check(station.purchase(&"vitality") and _run.currency == 900, "Vitality (Lv 1): 100 gold deducted once (gold %d)" % _run.currency)
	_check(is_equal_approx(_mage.health.max_health, base_max_hp + 20.0) and is_equal_approx(_mage.health.current, hp_before + 20.0),
			"Vitality: +20 max HP and +20 HP")
	_check(not station.purchase(&"vitality") and _run.currency == 900 and is_equal_approx(_mage.health.max_health, base_max_hp + 20.0),
			"an upgrade cannot be bought twice on one dungeon level")
	_check(not station.purchase(&"quick_cast") and not station.purchase(&"ember_core") and _run.currency == 900
			and _run.purchased.size() == 1 and is_equal_approx(_cast_cooldown(), base_cooldown) and is_equal_approx(_cast_damage(), base_damage),
			"Lv 1: Quick Cast (Lv 2) and Ember Core (Lv 3) blocked despite enough gold")
	_check((station.get_node(^"Menu/Panel/MenuLabel") as Label).text.contains("Ember Core requires Lv 3."), "menu explains the level requirement")

	# --- Station is locked during combat, Hall encounter still works ---
	_dungeon.current_room.start_encounter()
	await _frames(1)
	_check(_dungeon.current_room.state == Room.State.COMBAT and not station.is_open and not station.is_usable(),
			"station closes and is unusable during combat")
	await _kill_all(_dungeon.current_room)
	_check(_dungeon.current_room.state == Room.State.CLEARED and station.is_usable(), "station usable again after the room is cleared")

	# --- Level progression with bonuses ---
	var levels_before := _run.level
	var gold_before := _run.currency
	_run.add_rewards(_run.xp_to_next_level() - _run.xp, 0)
	_check(levels_before == 1 and _run.level == 2 and is_equal_approx(_mage.health.max_health, base_max_hp + 30.0),
			"Lv 2: +10 max HP (%.0f)" % _mage.health.max_health)
	_check(is_equal_approx(_cast_damage(), base_damage * 1.05), "Lv 2: +5%% spell damage (%.2f)" % _cast_damage())
	station.set_open(true)
	_check(station.purchase(&"quick_cast") and _run.currency == gold_before - 200 and is_equal_approx(_cast_cooldown(), base_cooldown * 0.95),
			"Lv 2: Quick Cast for 200 gold, -5%% cooldown (%.3f)" % _cast_cooldown())
	_check(not station.purchase(&"ember_core") and _run.currency == gold_before - 200, "Lv 2: Ember Core still blocked")
	_run.add_rewards(10000, 0)
	_check(_run.level == 4 and _run.xp == 0 and is_equal_approx(_mage.health.max_health, base_max_hp + 50.0),
			"Lv 4 cap: no level-ups past the cap (Lv %d, max HP %.0f)" % [_run.level, _mage.health.max_health])
	_check(is_equal_approx(_cast_damage(), base_damage * 1.15), "Lv 4: +15%% level damage total (%.2f)" % _cast_damage())
	_check(station.purchase(&"ember_core") and _run.currency == 415, "Lv 4: Ember Core for 300 gold (gold %d)" % _run.currency)
	_check(is_equal_approx(_cast_damage(), base_damage * 1.25), "Ember Core: +10%% stacks with level bonus (%.2f)" % _cast_damage())
	_check(is_equal_approx(fire_ball.damage, base_damage) and is_equal_approx(fire_ball.cooldown, base_cooldown)
			and _mage.caster.spell == fire_ball and _mage.caster.get_cast_spell() != fire_ball,
			"shared Fire Ball resource is not modified")
	var shot := _mage.caster.try_cast(_mage.caster.global_position + Vector2(0, -100))
	_check(shot != null and is_equal_approx(shot.spell.damage, base_damage * 1.25), "cast projectile carries the upgraded damage")
	_check(_mage.health.current <= _mage.health.max_health, "HP never exceeds max HP")
	_check(_hud_text() == "Lv 4 (MAX)   Gold 415", "HUD shows max level (%s)" % _hud_text())

	# --- Persistence across rooms ---
	_dungeon.enter_room(_scene_room(_dungeon, "crypt_room"), _dungeon.entry_door(_scene_room(_dungeon, "crypt_room")))
	await _frames(3)
	_check(_run.level == 4 and _run.is_purchased(&"ember_core") and _run.currency == 415
			and is_equal_approx(_mage.health.max_health, base_max_hp + 50.0) and is_equal_approx(_cast_damage(), base_damage * 1.25),
			"level, gold, upgrades and stats persist into the Crypt")
	_check(not station.is_open and not station.is_usable(), "station is closed after leaving the Hall")

	# --- Restart resets everything ---
	_mage.take_damage(9999.0)
	await _frames(1)
	scene_id = current_scene.get_instance_id() if current_scene else 0
	(current_scene.get_node(^"GameOverOverlay") as GameOverOverlay).restart()
	await _wait_for_scene(scene_id)
	_bind()
	_check(_run.level == 1 and _run.xp == 0 and _run.currency == 0 and _run.purchased.is_empty(),
			"Restart resets level, XP, gold and upgrades")
	_check(is_equal_approx(_mage.health.max_health, base_max_hp) and is_equal_approx(_cast_damage(), base_damage)
			and is_equal_approx(_cast_cooldown(), base_cooldown), "Restart resets Mage stats")
	_check(_station() != null and _station().run_state == _run and _hud_text() == "Lv 1   XP 0/50   Gold 0",
			"fresh station and HUD after Restart")

	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	RunState.seed_override = 0
	quit(1 if _failures > 0 else 0)


func _bind() -> void:
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage
	_run = _dungeon.run_state


func _station() -> UpgradeStation:
	return _dungeon.current_room.get_node_or_null(^"Decor/UpgradeStation") as UpgradeStation


func _cast_damage() -> float:
	return _mage.caster.get_cast_spell().damage


func _cast_cooldown() -> float:
	return _mage.caster.get_cast_spell().cooldown


func _move_mage(pos: Vector2) -> void:
	_mage.global_position = pos
	await _frames(3)


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


## Scene changes are deferred: waits until a new, ready scene (not `old_id`) is current.
func _wait_for_scene(old_id: int) -> void:
	for i in 600:
		if current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready():
			break
		await process_frame
	await _frames(2)


## Index of the room built from res://scenes/rooms/<name>.tscn (seeded layout, Issue #45).
func _scene_room(dungeon: Dungeon, name: String) -> int:
	for i in dungeon.rooms.size():
		if dungeon.rooms[i].scene.resource_path == "res://scenes/rooms/%s.tscn" % name:
			return i
	return -1
