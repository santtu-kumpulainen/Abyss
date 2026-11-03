extends SceneTree
## Headless check of run completion (scenes/dungeon/dungeon.tscn): the boss
## death triggers the victory state once, the victory screen offers exactly one
## relic whose bonus applies once, the run summary is accurate, and New Run /
## Main Menu -> Start Run both start a clean run.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_run_completion.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENE := "res://scenes/dungeon/dungeon.tscn"
const BOSS := Vector2i(2, 0)
const BOOTS_ROOM := Vector2i(0, 4)
const SECOND_ROOM := Vector2i(1, 4)

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState
var _base_hp := 0.0
var _base_damage := 0.0
var _base_speed := 0.0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	change_scene_to_file(SCENE)
	await _wait_for_scene(0)
	_base_hp = _mage.health.max_health
	_base_damage = _mage.caster.get_cast_spell().damage
	_base_speed = _mage.speed
	_check(_dungeon.victory_delay > 0.0 and _overlay() != null and not _overlay().visible, "dungeon has a hidden VictoryOverlay")
	await _test_victory_and_summary()
	await _test_new_run_resets()
	await _test_vital_relic()
	await _test_wind_relic_and_menu()
	await _test_no_victory_after_mage_death()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## Run A: clear two rooms, collect an item, buy an upgrade, kill the boss,
## choose the Ember Relic; checks victory-once, relic-once and the summary.
func _test_victory_and_summary() -> void:
	_check(not _run.choose_relic(&"ember_relic") and _run.relic.is_empty(), "no relic can be chosen before the boss dies")
	var enemies := 0
	enemies += await _clear_room(_dungeon.index_at(BOOTS_ROOM))
	var boots := _pickup(_dungeon.current_room)
	_check(boots != null and boots.collect(), "setup: Swift Boots collected")
	enemies += await _clear_room(_dungeon.index_at(SECOND_ROOM))
	_check(_run.enemies_defeated == enemies and enemies > 0, "enemies defeated counted per encounter kill (%d)" % _run.enemies_defeated)
	_run.add_rewards(0, 100)
	_check(_run.purchase(&"vitality"), "setup: Vitality purchased")
	while _run.level < RunState.MAX_LEVEL:
		_run.add_rewards(_run.xp_to_next_level(), 0)

	var victories := [0]
	_dungeon.victory_started.connect(func() -> void: victories[0] += 1)
	var boss_index := _dungeon.index_at(BOSS)
	_dungeon.enter_room(boss_index, &"DoorBottom")
	await _frames(2)
	var boss := _boss(_dungeon.current_room)
	_check(boss != null and not _dungeon.victory, "boss fight started, no victory yet")
	# A volley in flight when the boss dies must not hit the Mage afterwards.
	boss.begin_attack(&"volley")
	await _wait_until(func() -> bool: return boss.state != Boss.State.WINDUP)
	_check(not _hostile_shots().is_empty(), "setup: boss bolts in flight")
	var hp := _mage.health.current
	var gold := _run.currency
	boss.take_damage(99999.0)
	await _frames(2)
	_check(_dungeon.victory and _run.boss_defeated and victories[0] == 1, "boss death triggers the victory state once")
	_check(_run.currency == gold + 150, "boss reward granted once (%d -> %d)" % [gold, _run.currency])
	_check(_hostile_shots().is_empty() and _all_shots().is_empty(), "all projectiles removed on victory")
	_check(_mage.invulnerable and not _mage.is_physics_processing() and _mage.velocity == Vector2.ZERO,
			"Mage stops (no movement/casting) after victory")
	_mage.take_damage(50.0)
	_check(is_equal_approx(_mage.health.current, hp), "Mage takes no damage after victory")
	_check(not _overlay().visible and not paused, "victory screen waits for the encounter to settle")
	_dungeon._start_victory()
	_check(victories[0] == 1, "re-triggering victory does nothing")

	await _wait_until(func() -> bool: return _overlay().is_open, 240)
	_check(_overlay().visible and paused, "victory screen opens and pauses the game")
	_check(_relic_buttons().size() == 3, "three relic choices offered (%d)" % _relic_buttons().size())
	_check(not (_overlay().get_node(^"%Actions") as Control).visible, "New Run / Main Menu appear only after choosing a relic")
	_overlay().open(_dungeon)
	_dungeon._open_victory_overlay()
	_check(_relic_buttons().size() == 3 and victories[0] == 1, "victory screen cannot be opened twice")

	# --- Relic: exactly one, applied once ---
	var max_hp := _mage.health.max_health
	var damage_before := _mage.caster.get_cast_spell().damage
	(_relic_buttons()[1] as Button).pressed.emit()
	_check(_run.relic == &"ember_relic", "pressing a relic button selects it (%s)" % _run.relic)
	var expected_damage := _base_damage * (1.0 + 0.1 * 2 + 0.2)
	_check(is_equal_approx(_mage.caster.get_cast_spell().damage, expected_damage) and damage_before < expected_damage,
			"Ember Relic: +20%% Fire Ball damage (%.2f -> %.2f)" % [damage_before, _mage.caster.get_cast_spell().damage])
	_check(not _overlay().choose_relic(&"vital_relic") and not _run.choose_relic(&"ember_relic") and _run.relic == &"ember_relic"
			and is_equal_approx(_mage.health.max_health, max_hp), "a second relic choice is rejected")
	_run.changed.emit()
	_run.changed.emit()
	_check(is_equal_approx(_mage.caster.get_cast_spell().damage, expected_damage) and is_equal_approx(_mage.speed_multiplier, 1.15),
			"relic bonus does not stack on recalculation")

	# --- Summary ---
	var summary := _dungeon.run_summary()
	_check(summary["level"] == 3 and summary["rooms_cleared"] == 3 and summary["rooms_total"] == 25
			and summary["enemies_defeated"] == enemies + 1 and summary["items"] == [&"swift_boots"]
			and summary["upgrades"] == [&"vitality"] and summary["relic"] == &"ember_relic", "run summary values are accurate (%s)" % summary)
	var text := (_overlay().get_node(^"%SummaryLabel") as Label).text
	_check((_overlay().get_node(^"%SummaryLabel") as Label).visible and text.contains("Mage level: 3") and text.contains("Rooms cleared: 3 / 25")
			and text.contains("Enemies defeated: %d" % (enemies + 1)) and text.contains("Items: Swift Boots")
			and text.contains("Anvil upgrades: Vitality") and text.contains("Relic: Ember Relic"), "summary screen shows the values:\n%s" % text)
	_check((_overlay().get_node(^"%Actions") as Control).visible, "New Run / Main Menu shown with the summary")


## New Run from the victory screen starts a clean run.
func _test_new_run_resets() -> void:
	var old_id := current_scene.get_instance_id()
	(_overlay().get_node(^"%NewRunButton") as Button).pressed.emit()
	await _wait_for_scene(old_id)
	_check_fresh_run("New Run")


## Run B: Vital Relic raises max HP by 30 and heals 30, capped at the new max.
func _test_vital_relic() -> void:
	await _win_fast()
	_mage.invulnerable = false
	_mage.take_damage(10.0)
	_mage.invulnerable = true
	var max_hp := _mage.health.max_health
	_check(_overlay().choose_relic(&"vital_relic"), "Vital Relic chosen")
	_check(is_equal_approx(_mage.health.max_health, max_hp + 30.0) and is_equal_approx(_mage.health.current, max_hp + 20.0),
			"Vital Relic: +30 max HP, heal 30 capped at the new max (%.0f/%.0f)" % [_mage.health.current, _mage.health.max_health])
	_check(not _overlay().choose_relic(&"vital_relic") and is_equal_approx(_mage.health.max_health, max_hp + 30.0), "Vital Relic applies only once")
	_check(is_equal_approx(_mage.speed_multiplier, 1.0) and is_equal_approx(_mage.caster.get_cast_spell().damage, _base_damage * 1.2),
			"Vital Relic changes no other stats")
	_check(_dungeon.run_summary()["items"].is_empty() and _dungeon.run_summary()["upgrades"].is_empty()
			and (_overlay().get_node(^"%SummaryLabel") as Label).text.contains("Items: none"), "summary lists no items/upgrades when none were taken")
	await _restart_via_game_over_path()


## Run C: Wind Relic speed, then Main Menu -> Start Run gives a clean run.
func _test_wind_relic_and_menu() -> void:
	await _win_fast()
	_check(_overlay().choose_relic(&"wind_relic") and is_equal_approx(_mage.speed_multiplier, 1.1), "Wind Relic: +10%% move speed (%.2f)" % _mage.speed_multiplier)
	var old_id := current_scene.get_instance_id()
	(_overlay().get_node(^"%MainMenuButton") as Button).pressed.emit()
	await _wait_until(func() -> bool: return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(1)
	_check(current_scene is MainMenu and not paused, "Main Menu loads the menu scene, unpaused")
	old_id = current_scene.get_instance_id()
	# Start Run opens the run setup panel; Begin Run starts the run.
	(current_scene.get_node(^"%StartButton") as Button).pressed.emit()
	(current_scene.get_node(^"%BeginButton") as Button).pressed.emit()
	await _wait_for_scene(old_id)
	_check(current_scene is Dungeon, "Start Run loads the dungeon")
	_check_fresh_run("Main Menu -> Start Run")


## If the Mage is already dead, the boss's death does not open the victory screen.
func _test_no_victory_after_mage_death() -> void:
	while _run.level < RunState.MAX_LEVEL:
		_run.add_rewards(_run.xp_to_next_level(), 0)
	_dungeon.enter_room(_dungeon.index_at(BOSS), &"DoorBottom")
	await _frames(2)
	var boss := _boss(_dungeon.current_room)
	_mage.take_damage(9999.0)
	await _frames(1)
	boss.take_damage(99999.0)
	await _frames(90)
	_check(_mage.is_dead() and not _dungeon.victory and not _overlay().is_open and not paused
			and (current_scene.get_node(^"GameOverOverlay") as CanvasLayer).visible, "dead Mage: Game Over, no victory screen")


## Fresh run, boss killed, victory screen open.
func _win_fast() -> void:
	while _run.level < RunState.MAX_LEVEL:
		_run.add_rewards(_run.xp_to_next_level(), 0)
	_dungeon.enter_room(_dungeon.index_at(BOSS), &"DoorBottom")
	await _frames(2)
	_boss(_dungeon.current_room).take_damage(99999.0)
	await _wait_until(func() -> bool: return _overlay().is_open, 240)


## Leaves a won (paused) run through Game Over's restart path, which must unpause.
func _restart_via_game_over_path() -> void:
	var old_id := current_scene.get_instance_id()
	(current_scene.get_node(^"GameOverOverlay") as GameOverOverlay).restart()
	await _wait_for_scene(old_id)
	_check(not paused, "Restart after a won run unpauses the game")


func _check_fresh_run(label: String) -> void:
	_check(not paused and not _overlay().is_open and not _overlay().visible, "%s: unpaused, victory screen closed" % label)
	_check(_run.level == 1 and _run.xp == 0 and _run.currency == 0, "%s: level, XP and gold reset" % label)
	_check(_run.collected.is_empty() and _run.purchased.is_empty() and _run.relic.is_empty(), "%s: items, purchases and relic reset" % label)
	_check(not _run.boss_defeated and not _dungeon.victory and _run.enemies_defeated == 0, "%s: boss state and counters reset" % label)
	_check(_dungeon.current_index == _dungeon.start_room and _dungeon.rooms_cleared_count() == 0 and _dungeon.final_anvil == null
			and not _dungeon.is_visited(_dungeon.index_at(BOSS)) and not _dungeon.is_visited(_dungeon.index_at(BOOTS_ROOM)),
			"%s: room clear/discovery state reset" % label)
	_check(is_equal_approx(_mage.health.max_health, _base_hp) and is_equal_approx(_mage.health.current, _base_hp)
			and is_equal_approx(_mage.speed_multiplier, 1.0) and is_equal_approx(_mage.caster.get_cast_spell().damage, _base_damage)
			and is_equal_approx(_mage.speed, _base_speed), "%s: Mage health, speed and damage reset" % label)
	_check(not _mage.invulnerable and _mage.is_physics_processing() and not _mage.is_dead(), "%s: Mage controllable and vulnerable" % label)


## Clears room `index`; returns how many encounter enemies were killed.
func _clear_room(index: int) -> int:
	_dungeon.enter_room(index)
	await _frames(1)
	var room := _dungeon.current_room
	room.start_encounter()
	var count := room.get_node(^"Enemies").get_child_count()
	for enemy in room.get_node(^"Enemies").get_children():
		(enemy as Enemy).take_damage(99999.0)
	await _frames(2)
	_check(room.state == Room.State.CLEARED, "setup: room %d cleared" % index)
	return count


func _overlay() -> VictoryOverlay:
	return current_scene.get_node_or_null(^"VictoryOverlay") as VictoryOverlay


func _relic_buttons() -> Array:
	return (_overlay().get_node(^"%RelicChoices") as Node).get_children()


func _boss(room: Room) -> Boss:
	for child in room.get_node(^"Enemies").get_children():
		if child is Boss and not child.is_queued_for_deletion():
			return child
	return null


func _pickup(room: Room) -> ItemPickup:
	for child in room.get_node(^"Decor").get_children():
		if child is ItemPickup and not child.is_queued_for_deletion():
			return child
	return null


func _all_shots() -> Array:
	return current_scene.get_children().filter(func(n: Node) -> bool: return n is Projectile and not n.is_queued_for_deletion())


func _hostile_shots() -> Array:
	return _all_shots().filter(func(p: Projectile) -> bool: return p.hostile_to_player)


func _bind() -> void:
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage
	_run = _dungeon.run_state


## Scene changes are deferred; waits until a new, ready scene (not `old_id`) is current, then binds.
func _wait_for_scene(old_id: int) -> void:
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_bind()


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
