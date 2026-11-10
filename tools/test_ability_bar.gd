extends SceneTree
## Headless check of the Issue #49 ability bar and Ancient Seal crystals
## (Stage 5):
## - slot order: default, saving/loading (progression.cfg), invalid data;
## - drag-and-drop swap, keys 1-3 following the slots, invalid drops;
## - quantities, empty slots, potion use by key, Home Teleport start/cancel;
## - dash cooldown display, seal crystals, the Anvil keeping keys 1-4;
## - pause, clicks on the bar not attacking, and a new run after death.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_ability_bar.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SEED := 4949
const DUNGEON_SCENE := "res://scenes/dungeon/dungeon.tscn"
const SLOTS_TEST_PATH := "user://progression_test_slots.cfg"
const HEALTH := &"health_potion"
const SPEED := &"speed_potion"
const TELEPORT := &"home_teleport"

var _failures := 0
var _dungeon: Dungeon
var _bar: AbilityBar
var _mage: Mage
var _run: RunState
var _prog: ProgressionStore


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_test_persistence()
	RunState.seed_override = SEED
	_prog = ProgressionStore.instance(self)
	_prog.ability_slots = ProgressionStore.default_ability_slots()
	await _load()
	_test_layout()
	await _test_quantities_and_keys()
	await _test_drag_and_keys()
	await _test_anvil_keys()
	await _test_teleport_slot()
	await _test_dash_display()
	_test_seals()
	await _test_pause_and_clicks()
	await _test_new_run()
	_prog.ability_slots = ProgressionStore.default_ability_slots()
	RunState.seed_override = 0
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Persistence -------------------------------------------------------------------

func _test_persistence() -> void:
	var defaults := ProgressionStore.default_ability_slots()
	_check(defaults == [HEALTH, SPEED, TELEPORT], "default order: Health, Speed, Teleport")
	var invalid := {
		"missing": null, "wrong type": 7, "too short": [HEALTH, SPEED], "too long": [HEALTH, SPEED, TELEPORT, HEALTH],
		"unknown id": [HEALTH, SPEED, &"mana_potion"], "duplicate": [HEALTH, HEALTH, TELEPORT],
		"wrong element type": [HEALTH, SPEED, 3], "outdated id": ["health_potion", "speed_potion", "recall_scroll"],
	}
	var all_default := true
	for label: String in invalid:
		all_default = all_default and ProgressionStore.parse_ability_slots(invalid[label]) == defaults \
				and not ProgressionStore.is_valid_ability_slots(invalid[label])
	_check(all_default, "invalid or outdated orders fall back to the default (%s)" % ", ".join(invalid.keys()))
	_check(ProgressionStore.parse_ability_slots(PackedStringArray(["home_teleport", "health_potion", "speed_potion"]))
			== [TELEPORT, HEALTH, SPEED], "a saved order of strings is read")

	_remove(SLOTS_TEST_PATH)
	var store := _store()
	store.load_progress()
	_check(store.ability_slots == defaults, "no saved file: default order")
	_check(not store.set_ability_slots([HEALTH, HEALTH, SPEED]) and store.ability_slots == defaults, "an invalid order is refused")
	_check(store.set_ability_slots([SPEED, TELEPORT, HEALTH]) and FileAccess.file_exists(SLOTS_TEST_PATH), "a valid order is saved")
	var restarted := _store()
	restarted.load_progress()
	_check(restarted.ability_slots == [SPEED, TELEPORT, HEALTH], "the order survives a restart (new store, load)")
	var config := ConfigFile.new()
	config.load(SLOTS_TEST_PATH)
	var saved_keys := config.get_section_keys("preferences")
	_check(saved_keys == PackedStringArray(["ability_slots"]) and not config.has_section("consumables"),
			"only the order is saved, never quantities")
	var corrupt_ok := true
	for bad: Variant in [42, ["health_potion"], ["a", "b", "c"], "health_potion,speed_potion,home_teleport"]:
		config.set_value("preferences", "ability_slots", bad)
		config.save(SLOTS_TEST_PATH)
		var loaded := _store()
		loaded.load_progress()
		corrupt_ok = corrupt_ok and loaded.ability_slots == defaults
		loaded.free()
	_check(corrupt_ok, "corrupt saved orders fall back to the default")
	store.free()
	restarted.free()
	_remove(SLOTS_TEST_PATH)


func _store() -> ProgressionStore:
	var store := ProgressionStore.new()
	store._initialized = true
	store.save_path = SLOTS_TEST_PATH
	return store


# --- Layout and quantities ------------------------------------------------------------

func _test_layout() -> void:
	_check(_bar != null and _bar.dungeon == _dungeon, "the Dungeon has an ability bar bound to it")
	var keys := [_bar.dash_slot().key_text, _bar.slot(0).key_text, _bar.slot(1).key_text, _bar.slot(2).key_text]
	_check(keys == ["Space", "1", "2", "3"], "keys shown: Space, 1, 2, 3")
	_check(_bar.slot_order() == [HEALTH, SPEED, TELEPORT] and _bar.slot(0).item == HEALTH and _bar.slot(2).item == TELEPORT,
			"default slots: Health, Speed, Teleport")
	var rect := (_bar.get_node(^"%Bar") as Control).get_global_rect()
	var view := (root as Viewport).get_visible_rect()
	_check(rect.end.y <= view.end.y and rect.position.y > view.end.y - 70 and absf(rect.get_center().x - view.get_center().x) < 1.0,
			"the bar sits at the bottom centre (%s)" % rect)
	_check(rect.position.x > 140.0, "the bar does not overlap the minimap (bottom-left)")
	_check(not _bar.is_mage_behind(), "at the start spawn the Mage is not behind the bar (no fade)")


func _test_quantities_and_keys() -> void:
	for i in 3:
		_check(_bar.slot(i).displayed()["quantity"] == 0 and not _bar.slot(i).displayed()["usable"], "slot %d empty at the start" % (i + 1))
	_check(not _bar.use_slot(0), "an empty slot does nothing")
	_run.add_rewards(0, 5000)
	_run.buy_consumable(HEALTH)
	_run.buy_consumable(HEALTH)
	_check(_bar.slot(0).displayed()["quantity"] == 2, "buying updates the quantity at once (2)")
	_check(not _bar.slot(0).displayed()["usable"], "Health Potion at full HP: shown unusable")
	await _key(KEY_1)
	_check(_run.consumable_count(HEALTH) == 2, "key 1 at full HP spends nothing")
	_mage.take_damage(_mage.health.max_health * 0.5 / _mage.damage_taken_multiplier)
	_check(_bar.slot(0).displayed()["usable"], "damaged: the Health Potion slot lights up")
	var hp := _mage.health.current
	await _key(KEY_1)
	_check(_run.consumable_count(HEALTH) == 1 and _mage.health.current > hp and _bar.slot(0).displayed()["quantity"] == 1,
			"key 1 drinks a Health Potion (2 -> 1)")
	_run.buy_consumable(SPEED)
	await _key(KEY_2)
	_check(_run.consumable_count(SPEED) == 0 and _run.is_speed_potion_active(), "key 2 drinks a Speed Potion")
	await _frames(2)
	_check(String(_bar.slot(1).displayed()["timer"]).begins_with("02:5") and _bar.slot(1).displayed()["quantity"] == 0,
			"the Speed slot shows the remaining time (%s) and 0 left" % _bar.slot(1).displayed()["timer"])
	_run.advance_speed_potion(1000.0)
	await _frames(1)
	_check(_bar.slot(1).displayed()["timer"] == "", "the timer disappears when the potion runs out")


# --- Drag and drop ------------------------------------------------------------------

func _test_drag_and_keys() -> void:
	var first := _bar.slot(0)
	var third := _bar.slot(2)
	var data: Variant = first._get_drag_data(Vector2(10, 10))
	_check(data is Dictionary and data["ability_slot"] == 0, "dragging slot 1 carries its position")
	_check(_bar.dash_slot()._get_drag_data(Vector2(10, 10)) == null, "the Dash slot cannot be dragged")
	_check(not first._can_drop_data(Vector2.ZERO, data) and not _bar.dash_slot()._can_drop_data(Vector2.ZERO, data)
			and not third._can_drop_data(Vector2.ZERO, {"other": 1}) and not third._can_drop_data(Vector2.ZERO, "slot"),
			"no drop on itself, on the Dash slot or with foreign data")
	_check(not _bar.swap_slots(0, 5) and not _bar.swap_slots(-1, 1) and _bar.slot_order() == [HEALTH, SPEED, TELEPORT],
			"invalid swaps change nothing")
	_check(third._can_drop_data(Vector2.ZERO, data), "slot 3 accepts slot 1")
	third._drop_data(Vector2.ZERO, data)
	_check(_bar.slot_order() == [TELEPORT, SPEED, HEALTH] and first.item == TELEPORT and third.item == HEALTH,
			"drop swaps: Teleport, Speed, Health")
	_check(_prog.ability_slots == [TELEPORT, SPEED, HEALTH], "the new order is stored in the progression")
	_check(_bar.slot(0).displayed()["quantity"] == 0 and _bar.slot(2).displayed()["quantity"] == 1, "quantities follow their items")
	_check(_bar.slot(0).key_text == "1" and _bar.slot(2).key_text == "3", "keys stay with the slot positions")
	var hp := _mage.health.current
	await _key(KEY_1)
	_check(_run.consumable_count(HEALTH) == 1, "key 1 now uses the Home Teleport slot (no potion drunk)")
	await _key(KEY_3)
	_check(_run.consumable_count(HEALTH) == 0 and _mage.health.current > hp, "key 3 now drinks the Health Potion")

	# A real mouse drag through the GUI (press, move, release).
	await _mouse_drag(_bar.slot(0), _bar.slot(1))
	var dragged := _bar.slot_order() == [SPEED, TELEPORT, HEALTH]
	print("INFO: GUI mouse drag in headless mode %s (checked in a windowed run)" % ("worked" if dragged else "is not delivered"))
	if dragged:
		_check(true, "a mouse drag from slot 1 to slot 2 swaps them")
	_prog.set_ability_slots([HEALTH, SPEED, TELEPORT])
	_bar.refresh()


# --- Anvil --------------------------------------------------------------------------

func _test_anvil_keys() -> void:
	_dungeon.enter_room(_dungeon.start_room)
	await _frames(3)
	var station := _dungeon.current_room.get_node_or_null(^"Decor/UpgradeStation") as UpgradeStation
	_check(station != null, "setup: start-room anvil")
	_mage.global_position = station.global_position + Vector2(50, 0)
	await _frames(3)
	_run.buy_consumable(HEALTH)
	_mage.take_damage(_mage.health.max_health * 0.5 / _mage.damage_taken_multiplier)
	station.set_open(true)
	var vitality := _run.upgrade_stacks(&"vitality")
	await _key(KEY_1)
	_check(_run.upgrade_stacks(&"vitality") == vitality + 1 and _run.consumable_count(HEALTH) == 1,
			"anvil open: key 1 buys Vitality, no potion is used")
	await _key(KEY_2)
	_check(_run.consumable_count(HEALTH) == 1 and _run.is_purchased(&"vitality"), "anvil open: keys 1-3 never use slots")
	station.set_open(false)
	await _key(KEY_1)
	_check(_run.consumable_count(HEALTH) == 0, "anvil closed: key 1 uses slot 1 again")
	_mage.health.increase_max_health(0.0, _mage.health.max_health)


# --- Home Teleport slot --------------------------------------------------------------

func _test_teleport_slot() -> void:
	_run.buy_consumable(TELEPORT)
	var idle := -1
	for i in _dungeon.rooms.size():
		if i != _dungeon.start_room and i != _dungeon.boss_index() and not _dungeon.is_visited(i):
			idle = i
			break
	_dungeon.enter_room(idle)
	await _frames(3)
	_check(_bar.slot(2).displayed()["usable"] and _bar.slot(2).displayed()["quantity"] == 1, "Teleport slot: 1, usable away from home")
	await _key(KEY_3)
	var tp := _dungeon.home_teleport
	_check(tp.is_casting() and absf(_bar.slot(2).displayed()["cast"] - tp.cast_progress()) < 0.03,
			"key 3 starts the cast; the slot shows it (%.2f)" % _bar.slot(2).displayed()["cast"])
	await _frames(45)
	var shown: float = _bar.slot(2).displayed()["cast"]
	_check(absf(shown - tp.cast_progress()) < 0.03 and shown > 0.4, "the slot follows the cast progress (%.2f)" % shown)
	await _key(KEY_3)
	_check(not tp.is_casting() and _bar.slot(2).displayed()["cast"] == -1.0 and _run.consumable_count(TELEPORT) == 1,
			"key 3 again cancels; item kept, the slot clears at once")
	await _key(KEY_3)
	for i in 120:
		if not tp.is_busy():
			break
		await physics_frame
	await _frames(1)
	_check(_dungeon.current_index == _dungeon.start_room and _bar.slot(2).displayed()["quantity"] == 0
			and _bar.slot(2).displayed()["cast"] == -1.0, "a full cast teleports home; the slot shows 0")


# --- Dash and seals -------------------------------------------------------------------

func _test_dash_display() -> void:
	_check(_bar.dash_slot().displayed()["cooldown"] == 0.0 and _bar.dash_slot().displayed()["available"], "Dash slot ready")
	_mage.try_dash(Vector2.RIGHT)
	_check(_bar.dash_slot().displayed()["cooldown"] > 0.99, "dash_started empties the Dash slot at once")
	await _frames(30)
	_check(absf(_bar.dash_slot().displayed()["cooldown"] - (1.0 - _mage.dash_cooldown_ratio())) < 0.02,
			"the Dash slot follows the Mage's cooldown")
	for i in 200:
		if _mage.dash_ready():
			break
		await physics_frame
	await _frames(1)
	_check(_bar.dash_slot().displayed()["cooldown"] == 0.0, "ready again: the shade is gone")
	_check(not _bar.is_animating(), "nothing animates when idle (signal-driven, no polling refresh)")
	_mage.end_run()
	_bar.refresh()
	_check(not _bar.dash_slot().displayed()["available"], "after end_run(): the Dash slot is shown unavailable")
	_mage.resume_run()
	_bar.refresh()


func _test_seals() -> void:
	var states := _bar.seals().states()
	_check(states.size() == 4 and not states.has(true), "four dark seal crystals")
	var sources := _run.seal_sources()
	_run.collect_seal(sources[2])
	states = _bar.seals().states()
	_check(states == [false, false, true, false], "collecting a seal lights its crystal (%s)" % [states])
	_run.collect_seal(sources[0])
	var matches := true
	for i in sources.size():
		matches = matches and _bar.seals().states()[i] == _run.is_seal_collected(sources[i])
	_check(matches and _run.seals_collected() == 2, "the crystals match RunState")


# --- Pause, clicks, new run ----------------------------------------------------------

func _test_pause_and_clicks() -> void:
	_run.buy_consumable(SPEED)
	paused = true
	await _key(KEY_2)
	_check(_run.consumable_count(SPEED) == 1, "paused: keys do nothing")
	paused = false
	await _frames(1)

	# Real hover/drag needs a window: headless runs deliver no GUI mouse
	# events (checked in a windowed run instead). Here: the wiring.
	var in_group := true
	for i in 3:
		in_group = in_group and _bar.slot(i).is_in_group(Mage.HUD_CLICK_GROUP) and _bar.slot(i).mouse_filter == Control.MOUSE_FILTER_STOP
	_check(in_group and _bar.dash_slot().is_in_group(Mage.HUD_CLICK_GROUP), "every slot takes its clicks and is marked as non-attack HUD")
	Input.action_press(&"attack")
	_check(_mage.is_attack_held(), "attack is held when no HUD control is under the mouse")
	Input.action_release(&"attack")
	_check(not _mage.is_attack_held(), "released: no attack")


func _test_new_run() -> void:
	_prog.set_ability_slots([SPEED, HEALTH, TELEPORT])
	_mage.take_damage(1000000.0)
	await _frames(2)
	_check(_mage.is_dead() and not _bar.dash_slot().displayed()["available"], "dead: the Dash slot is unavailable")
	var old_id := current_scene.get_instance_id()
	(current_scene.get_node(^"GameOverOverlay") as GameOverOverlay).restart()
	for i in 600:
		if current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready():
			break
		await physics_frame
	await _frames(3)
	_bind()
	_check(_bar.slot_order() == [SPEED, HEALTH, TELEPORT] and _bar.slot(0).item == SPEED, "a new run keeps the saved order")
	var empty := true
	for i in 3:
		empty = empty and _bar.slot(i).displayed()["quantity"] == 0
	_check(empty and _run.consumables.is_empty(), "a new run starts with empty slots")
	_check(not _bar.seals().states().has(true) and _bar.dash_slot().displayed()["available"], "seals dark and Dash ready again")


# --- Helpers --------------------------------------------------------------------------

func _load() -> void:
	var old_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(DUNGEON_SCENE)
	for i in 600:
		if current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready():
			break
		await physics_frame
	await _frames(2)
	_bind()


func _bind() -> void:
	_dungeon = current_scene as Dungeon
	_bar = _dungeon.get_node(^"AbilityBar") as AbilityBar
	_mage = _dungeon.mage
	_run = _dungeon.run_state


## Presses and releases physical key `code` (both its actions see it, like a real key).
func _key(code: Key) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(1)
	var release := InputEventKey.new()
	release.physical_keycode = code
	Input.parse_input_event(release)
	await _frames(1)


func _motion(pos: Vector2, button_mask := 0) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	motion.button_mask = button_mask
	(root as Viewport).push_input(motion)


func _mouse_drag(from: Control, to: Control) -> void:
	var start := from.get_global_rect().get_center()
	var end := to.get_global_rect().get_center()
	_motion(start)
	await _frames(1)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	press.global_position = start
	(root as Viewport).push_input(press)
	await _frames(1)
	for i in range(1, 11):
		_motion(start.lerp(end, i / 10.0), MOUSE_BUTTON_MASK_LEFT)
		await _frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = end
	release.global_position = end
	(root as Viewport).push_input(release)
	await _frames(2)


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
