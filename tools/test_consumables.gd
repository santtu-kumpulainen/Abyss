extends SceneTree
## Headless check of the Issue #49 consumables (Stage 1): RunState inventory
## caps and prices, purchase refusal independent of any UI, spending, the Speed
## Potion (x1.25 after the x1.40 upgrade cap, x1.6 overall cap, 180 s of active
## play, refresh without stacking, expiry, carry-over between dungeon levels,
## reset), the Health Potion (25% max HP, Blood Pact halving, max HP cap, not
## spent at full HP), the anvil Supplies section (keys 5-7, Twin Cast still 4000
## gold) and the inventory being cleared by death -> restart.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_consumables.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SEED := 4949
const SCENE := "res://scenes/dungeon/dungeon.tscn"
const NORMAL := Difficulty.Tier.NORMAL

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	RunState.seed_override = SEED
	_test_catalog()
	_test_inventory_limits()
	_test_speed_potion_unit()
	_test_speed_cap()
	_test_level_carry_and_reset()
	await _test_scene()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	RunState.seed_override = 0
	quit(1 if _failures > 0 else 0)


func _new_run(gold: int = 0) -> RunState:
	var run := RunState.new()
	run.configure(NORMAL)
	run.currency = gold
	return run


# --- RunState -------------------------------------------------------------------

func _test_catalog() -> void:
	var run := _new_run()
	_check(run.consumable_price(&"health_potion") == 120 and run.consumable_max(&"health_potion") == 3, "Health Potion: 120 gold, max 3")
	_check(run.consumable_price(&"speed_potion") == 150 and run.consumable_max(&"speed_potion") == 3, "Speed Potion: 150 gold, max 3")
	_check(run.consumable_price(&"home_teleport") == 200 and run.consumable_max(&"home_teleport") == 1, "Home Teleport: 200 gold, max 1")
	_check(RunState.CONSUMABLES.keys() == [&"health_potion", &"speed_potion", &"home_teleport"], "shop order: Health, Speed, Teleport")
	_check(run.UPGRADES[&"twin_cast"]["prices"] == [4000] and run.upgrade_max_stacks(&"twin_cast") == 1, "Twin Cast unchanged: one per-run stack for 4000 gold")
	run.free()


func _test_inventory_limits() -> void:
	var run := _new_run(10000)
	var bought := 0
	for i in 5:
		if run.buy_consumable(&"health_potion"):
			bought += 1
	_check(bought == 3 and run.consumable_count(&"health_potion") == 3, "Health Potion stops at 3 (%d bought)" % bought)
	_check(run.currency == 10000 - 3 * 120, "only successful purchases cost gold (%d)" % run.currency)
	_check(run.buy_consumable(&"home_teleport") and not run.buy_consumable(&"home_teleport") and run.consumable_count(&"home_teleport") == 1,
			"Home Teleport stops at 1")
	var gold := run.currency
	_check(not run.can_buy_consumable(&"home_teleport") and run.currency == gold, "a refused purchase deducts nothing")
	_check(not run.buy_consumable(&"unknown_item") and run.currency == gold, "unknown consumables are refused")

	var poor := _new_run(119)
	_check(not poor.buy_consumable(&"health_potion") and poor.currency == 119 and poor.consumable_count(&"health_potion") == 0, "too little gold: refused, nothing changes")
	poor.currency = 120
	_check(poor.buy_consumable(&"health_potion") and poor.currency == 0, "exact price: bought")
	# Consumables have no once-per-dungeon-level rule.
	poor.currency = 240
	_check(poor.buy_consumable(&"health_potion") and poor.buy_consumable(&"health_potion"), "several of one consumable on the same level")

	_check(run.use_consumable(&"health_potion") and run.consumable_count(&"health_potion") == 2, "use removes exactly one")
	run.use_consumable(&"health_potion")
	run.use_consumable(&"health_potion")
	_check(not run.use_consumable(&"health_potion") and run.consumable_count(&"health_potion") == 0 and not run.consumables.has(&"health_potion"),
			"none left: use refused, count stays 0")
	_check(run.buy_consumable(&"health_potion"), "an emptied slot can be refilled")
	run.free()
	poor.free()


func _test_speed_potion_unit() -> void:
	var run := _new_run(10000)
	_check(not run.use_speed_potion() and not run.is_speed_potion_active(), "no Speed Potion owned: nothing happens")
	run.buy_consumable(&"speed_potion")
	run.buy_consumable(&"speed_potion")
	_check(run.use_speed_potion() and is_equal_approx(run.speed_potion_remaining, 180.0) and run.consumable_count(&"speed_potion") == 1,
			"drink: 180 s, one spent")
	_check(is_equal_approx(run.effective_move_speed_multiplier(), 1.25) and is_equal_approx(run.move_speed_multiplier(), 1.0),
			"active: x1.25 effective, upgrade multiplier untouched")
	_check(not run.use_speed_potion() and run.consumable_count(&"speed_potion") == 1, "not spent while the effect is still full")
	run.advance_speed_potion(100.0)
	_check(is_equal_approx(run.speed_potion_remaining, 80.0), "timer counts down (80 s left)")
	_check(run.use_speed_potion() and is_equal_approx(run.speed_potion_remaining, 180.0) and is_equal_approx(run.effective_move_speed_multiplier(), 1.25),
			"re-drink refreshes to 180 s without stacking (x1.25)")
	var expired := [0]
	run.speed_potion_expired.connect(func() -> void: expired[0] += 1)
	run.advance_speed_potion(179.0)
	_check(run.is_speed_potion_active() and expired[0] == 0, "still active 1 s before the end")
	run.advance_speed_potion(5.0)
	_check(not run.is_speed_potion_active() and run.speed_potion_remaining == 0.0 and expired[0] == 1, "expires once after 180 s")
	_check(is_equal_approx(run.effective_move_speed_multiplier(), 1.0), "after expiry the multiplier is exactly the previous x1.0")
	run.advance_speed_potion(10.0)
	_check(expired[0] == 1, "no repeated expiry signal")
	run.free()


func _test_speed_cap() -> void:
	var run := _new_run(10000)
	run.collect_item(&"swift_boots")
	_check(is_equal_approx(run.move_speed_multiplier(), 1.08), "setup: Swift Boots x1.08")
	run.buy_consumable(&"speed_potion")
	run.use_speed_potion()
	_check(is_equal_approx(run.effective_move_speed_multiplier(), 1.08 * 1.25), "potion applies after the upgrade sum (x%.3f)" % run.effective_move_speed_multiplier())
	# Push the upgrade multiplier to its x1.40 cap.
	for i in 30:
		run.relics.append(&"wind_relic")
	_check(is_equal_approx(run.move_speed_multiplier(), 1.4), "setup: upgrades at the x1.40 cap")
	_check(is_equal_approx(run.effective_move_speed_multiplier(), RunState.MAX_MOVE_SPEED_WITH_POTION) and is_equal_approx(RunState.MAX_MOVE_SPEED_WITH_POTION, 1.6),
			"potion at the upgrade cap stays at x1.6, not x1.75 (x%.3f)" % run.effective_move_speed_multiplier())
	_check(is_equal_approx(run.enemy_move_pace_multiplier(), _pace_without_potion(run)), "enemy catch-up pacing ignores the potion")
	run.free()


## enemy_move_pace_multiplier() of an identical run without the potion.
func _pace_without_potion(run: RunState) -> float:
	var remaining := run.speed_potion_remaining
	run.speed_potion_remaining = 0.0
	var pace := run.enemy_move_pace_multiplier()
	run.speed_potion_remaining = remaining
	return pace


func _test_level_carry_and_reset() -> void:
	var run := _new_run(10000)
	run.buy_consumable(&"health_potion")
	run.buy_consumable(&"home_teleport")
	run.buy_consumable(&"speed_potion")
	run.buy_consumable(&"speed_potion")
	run.use_speed_potion()
	run.advance_speed_potion(30.0)
	run.boss_defeated = true
	run.choose_relic(&"vital_relic")
	_check(run.begin_next_level() and run.dungeon_level == 2, "setup: next dungeon level")
	_check(run.consumable_count(&"health_potion") == 1 and run.consumable_count(&"home_teleport") == 1 and run.consumable_count(&"speed_potion") == 1,
			"inventory carries over to the next dungeon level")
	_check(is_equal_approx(run.speed_potion_remaining, 150.0) and is_equal_approx(run.effective_move_speed_multiplier(), 1.25),
			"Speed Potion timer carries over (150 s left)")
	run.reset()
	_check(run.consumables.is_empty() and run.speed_potion_remaining == 0.0 and is_equal_approx(run.effective_move_speed_multiplier(), 1.0),
			"reset(): inventory and Speed Potion cleared")
	run.free()


# --- Dungeon scene --------------------------------------------------------------

func _test_scene() -> void:
	await _load_dungeon()
	_check(is_equal_approx(_mage.speed_multiplier, 1.0) and _run.consumables.is_empty(), "new run: no consumables, x1.0 speed")
	var base_speed := _mage.speed

	# Anvil Supplies section.
	var station := _dungeon.current_room.get_node_or_null(^"Decor/UpgradeStation") as UpgradeStation
	_check(station != null, "the starting room has an anvil")
	_mage.global_position = station.global_position + Vector2(50, 0)
	await _frames(3)
	station.set_open(true)
	var text := station._menu_label.text
	_check(text.contains("SUPPLIES") and text.contains("[5] Health Potion (0/3) - 120 gold") and text.contains("[6] Speed Potion (0/3) - 150 gold")
			and text.contains("[7] Home Teleport (0/1) - 200 gold"), "anvil lists the supplies with keys 5-7, count and price")
	_check(text.contains("[1] Vitality") and text.contains("[4] Twin Cast"), "upgrade lines and keys 1-4 are unchanged")
	_check(not station.purchase_supply(&"health_potion") and station._menu_label.text.contains("Not enough gold"), "anvil: no gold -> refused with a reason")
	_run.add_rewards(0, 5000)
	var gold := _run.currency
	_check(station.purchase_supply(&"home_teleport") and _run.currency == gold - 200, "anvil: Home Teleport bought")
	_check(not station.purchase_supply(&"home_teleport") and station._menu_label.text.contains("inventory full") and _run.currency == gold - 200,
			"anvil: second Home Teleport refused (inventory full), no gold taken")
	_check(station._menu_label.text.contains("Home Teleport (1/1)") and station._menu_label.text.contains("[full]"), "anvil menu shows 1/1 [full]")
	gold = _run.currency
	await _press(&"buy_supply_1")
	_check(_run.consumable_count(&"health_potion") == 1 and _run.currency == gold - 120, "key 5 (buy_supply_1) buys a Health Potion")
	await _press(&"upgrade_1")
	_check(_run.consumable_count(&"health_potion") == 1 and _run.upgrade_stacks(&"vitality") == 1, "key 1 in the open anvil still buys Vitality")
	for i in 3:
		station.purchase_supply(&"health_potion")
		station.purchase_supply(&"speed_potion")
	_check(_run.consumable_count(&"health_potion") == 3 and _run.consumable_count(&"speed_potion") == 3, "anvil: 3 Health + 3 Speed Potions bought")
	gold = _run.currency
	await _press(&"buy_supply_1")
	_check(_run.consumable_count(&"health_potion") == 3 and _run.currency == gold, "key 5 at a full inventory buys nothing")
	station.set_open(false)

	# Health Potion.
	_check(not _dungeon.use_health_potion() and _run.consumable_count(&"health_potion") == 3, "Health Potion not spent at full HP")
	var max_hp := _mage.health.max_health
	_mage.take_damage(max_hp * 0.5 / _mage.damage_taken_multiplier)
	await _frames(1)
	var before := _mage.health.current
	_check(_dungeon.use_health_potion() and is_equal_approx(_mage.health.current, before + max_hp * 0.25) and _run.consumable_count(&"health_potion") == 2,
			"Health Potion heals 25%% of max HP (%.1f -> %.1f of %.1f)" % [before, _mage.health.current, max_hp])
	_mage.health.increase_max_health(0.0, max_hp)
	_mage.take_damage(max_hp * 0.1 / _mage.damage_taken_multiplier)
	_dungeon.use_health_potion()
	_check(is_equal_approx(_mage.health.current, max_hp) and _run.consumable_count(&"health_potion") == 1, "Health Potion never heals above max HP")
	_run.pact = &"blood_pact"
	_mage.take_damage(max_hp * 0.5 / _mage.damage_taken_multiplier)
	before = _mage.health.current
	_dungeon.use_health_potion()
	_check(is_equal_approx(_mage.health.current, before + max_hp * 0.125), "Blood Pact halves the Health Potion (+%.1f)" % (_mage.health.current - before))
	_run.pact = &""

	# Speed Potion on the Mage.
	_check(_dungeon.use_speed_potion() and is_equal_approx(_mage.speed_multiplier, 1.25) and is_equal_approx(_mage.speed, base_speed),
			"Speed Potion: Mage x1.25, base speed unchanged")
	_check(is_equal_approx(_mage.base_speed_multiplier, 1.0) and is_equal_approx(_mage.base_walk_speed(), base_speed),
			"Speed Potion: the Mage's base walking speed (what the Demon follows) is unchanged")
	var remaining := _run.speed_potion_remaining
	await _frames(30)
	_check(_run.speed_potion_remaining < remaining, "the Dungeon counts the potion down with active play")
	_run.advance_speed_potion(_run.speed_potion_remaining + 1.0)
	await _frames(1)
	_check(is_equal_approx(_mage.speed_multiplier, 1.0) and is_equal_approx(_mage.speed, base_speed), "expiry restores x1.0 on the Mage")
	_dungeon.use_speed_potion()
	_check(_run.is_speed_potion_active() and _run.consumable_count(&"speed_potion") == 1, "setup: potion active before death")

	# Death -> restart: a fresh RunState without consumables.
	_mage.take_damage(100000.0)
	await _frames(2)
	var frozen := _run.speed_potion_remaining
	await _frames(10)
	_check(is_equal_approx(_run.speed_potion_remaining, frozen), "the potion timer stops while dead")
	var old_id := current_scene.get_instance_id()
	(current_scene.get_node(^"GameOverOverlay") as GameOverOverlay).restart()
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage
	_run = _dungeon.run_state
	_check(_run.consumables.is_empty() and not _run.is_speed_potion_active() and is_equal_approx(_mage.speed_multiplier, 1.0),
			"restart after death: no consumables, no Speed Potion")


func _load_dungeon() -> void:
	var old_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(SCENE)
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage
	_run = _dungeon.run_state


func _press(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(2)
	var release := InputEventAction.new()
	release.action = action
	Input.parse_input_event(release)
	await _frames(1)


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
