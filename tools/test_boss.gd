extends SceneTree
## Headless check of the boss fight (Abyss Warden in the Level 3 boss room) and
## the collectible run items in the dungeon run (scenes/dungeon/dungeon.tscn):
## boss attacks/damage/health/death, door locking, reward-once, Mage death and
## Restart, item pickups applying once, persisting between rooms and resetting.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_boss.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENE := "res://scenes/dungeon/dungeon.tscn"
const ANTECHAMBER := Vector2i(2, 1)
const BOSS := Vector2i(2, 0)
const BOOTS_ROOM := Vector2i(0, 4)
const HEART_ROOM := Vector2i(0, 0)
const SHARD_ROOM := Vector2i(4, 0)

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	change_scene_to_file(SCENE)
	await _frames(3)
	_bind()
	await _test_boss_fight()
	await _test_boss_mage_death_and_restart()
	await _test_items()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_boss_fight() -> void:
	_run.add_rewards(150, 0)
	_check(_run.level == 3, "setup: Lv 3")
	var boss_index := _dungeon.index_at(BOSS)
	_dungeon.enter_room(boss_index, &"DoorBottom")
	await _frames(2)
	var room := _dungeon.current_room
	var boss := _boss(room)
	var exit := room.get_node(^"Doors/DoorBottom") as Door
	_check(boss != null and room.state == Room.State.COMBAT and room.enemies_remaining == 1,
			"boss room starts the fight on arrival with the Abyss Warden")
	_check(exit.locked and not exit.is_open(), "boss room exit is locked during the fight")
	var bar := boss.get_node(^"BossBar/Bar") as HealthBar
	_check(bar.visible and is_equal_approx(bar.max_value, 700.0) and is_equal_approx(bar.value, 700.0)
			and (boss.get_node(^"BossBar/NameLabel") as Label).text == "Abyss Warden", "boss health bar shows 700/700 and the name")
	_check(boss.target == _mage, "boss targets the Mage from the boss room entrance")

	# --- Volley: telegraph, then 3 aimed bolts; the centre one hits the Mage ---
	var hp := _mage.health.current
	_check(boss.begin_attack(&"volley") and boss.phase == Boss.Phase.WINDUP and _boss_shots(boss).is_empty(),
			"volley telegraphs before firing (no bolts during wind-up)")
	_check(not boss.begin_attack(&"slam"), "boss cannot start a second attack during a wind-up")
	await _wait_until(func() -> bool: return boss.phase != Boss.Phase.WINDUP)
	var shots := _boss_shots(boss)
	_check(shots.size() == 3 and shots.all(func(p: Projectile) -> bool: return p.hostile_to_player and is_equal_approx(p.spell.damage, 10.0)),
			"volley fires 3 hostile bolts of 10 damage (%d)" % shots.size())
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	await _wait_until(func() -> bool: return _boss_shots(boss).is_empty(), 180)
	_check(is_equal_approx(_mage.health.current, hp - 10.0), "aimed centre bolt hits the Mage once (HP %.0f -> %.0f)" % [hp, _mage.health.current])
	boss.process_mode = Node.PROCESS_MODE_INHERIT

	# --- Slam: area damage only inside the telegraphed radius ---
	await _wait_until(func() -> bool: return boss.phase == Boss.Phase.CHASE)
	_mage.global_position = boss.global_position + Vector2(0, 80)
	await _frames(1)
	hp = _mage.health.current
	var hits: Array[bool] = []
	boss.attack_resolved.connect(func(_a: StringName, hit: bool) -> void: hits.append(hit))
	boss.speed = 0.0
	boss.contact_damage = 0.0
	_check(boss.begin_attack(&"slam"), "slam starts")
	await _wait_until(func() -> bool: return boss.phase != Boss.Phase.WINDUP)
	_check(hits == [true] and is_equal_approx(_mage.health.current, hp - 22.0), "slam hits the Mage inside its radius for 22 (HP %.0f)" % _mage.health.current)
	await _wait_until(func() -> bool: return boss.phase == Boss.Phase.CHASE)
	_mage.global_position = boss.global_position + Vector2(0, 200)
	await _frames(1)
	hp = _mage.health.current
	boss.begin_attack(&"slam")
	await _wait_until(func() -> bool: return boss.phase != Boss.Phase.WINDUP)
	_check(hits == [true, false] and is_equal_approx(_mage.health.current, hp), "Mage outside the slam radius takes no damage")

	# --- Enraged ring ---
	await _wait_until(func() -> bool: return boss.phase == Boss.Phase.CHASE)
	_check(not boss.is_enraged(), "not enraged at full health")
	boss.take_damage(360.0)
	_check(boss.is_enraged() and is_equal_approx(bar.value, 340.0), "enraged at <= 50%% HP; bar follows damage (%.0f)" % bar.value)
	await _clear_shots(boss)
	boss.begin_attack(&"ring")
	await _wait_until(func() -> bool: return boss.phase != Boss.Phase.WINDUP)
	_check(_boss_shots(boss).size() == 10, "ring fires 10 bolts in all directions")
	_check(not exit.is_open() and room.state == Room.State.COMBAT, "doors stay locked while the boss lives")

	# --- Death, unlock, reward once ---
	var gold := _run.currency
	_check(not _run.boss_defeated, "boss not marked defeated before death")
	boss.take_damage(9999.0)
	await _frames(2)
	_check(room.state == Room.State.CLEARED and exit.is_open() and room.enemies_remaining == 0,
			"boss death clears the room and unlocks the exit")
	_check(_run.currency == gold + 150 and _run.boss_defeated, "boss grants 150 gold once (%d -> %d)" % [gold, _run.currency])
	_check(_boss_shots_any().is_empty(), "boss bolts are removed when it dies")
	_check(_message().contains("Victory"), "victory is announced (%s)" % _message())
	_check(_room_hud_text() == room.cleared_text, "room HUD shows the victory text")
	gold = _run.currency
	_dungeon.enter_room(_dungeon.index_at(ANTECHAMBER), &"DoorTop")
	await _frames(2)
	_dungeon.enter_room(boss_index, &"DoorBottom")
	await _frames(2)
	_check(_dungeon.current_room == room and room.state == Room.State.CLEARED and _boss(room) == null
			and _run.currency == gold and exit.is_open(), "revisiting the boss room grants nothing and stays open")


func _test_boss_mage_death_and_restart() -> void:
	await _restart()
	_run.add_rewards(150, 0)
	var boss_index := _dungeon.index_at(BOSS)
	_check(not _dungeon.is_visited(boss_index) and not _run.boss_defeated, "Restart resets the boss room and boss flag")
	_dungeon.enter_room(boss_index, &"DoorBottom")
	await _frames(2)
	var boss := _boss(_dungeon.current_room)
	_check(boss != null and is_equal_approx(boss.health.current, 700.0), "fresh boss at full health after Restart")
	boss.begin_attack(&"volley")
	_mage.take_damage(9999.0)
	await _frames(60)
	_check(_mage.is_dead() and (current_scene.get_node(^"GameOverOverlay") as CanvasLayer).visible, "Mage death during the fight shows Game Over")
	_check(is_instance_valid(boss) and boss.target == null and _run.currency == 0, "boss stops targeting the dead Mage, no reward")
	await _restart()
	_check(_run.level == 1 and _run.currency == 0 and not _run.boss_defeated and _dungeon.current_index == _dungeon.start_room,
			"Restart after dying in the boss fight starts a fresh run")


func _test_items() -> void:
	var base_hp := _mage.health.max_health
	var base_damage := _mage.caster.get_cast_spell().damage
	_check(is_equal_approx(_mage.speed_multiplier, 1.0) and not _items_label().visible, "no items at the start of a run")

	# --- Swift Boots: hidden during combat, collected once after clearing ---
	var boots_index := _dungeon.index_at(BOOTS_ROOM)
	_dungeon.enter_room(boots_index, &"DoorRight")
	await _frames(2)
	var room := _dungeon.current_room
	var pickup := _pickup(room)
	_check(pickup != null and pickup.item_id == &"swift_boots" and pickup.run_state == _run, "Swift Boots pickup placed in its room")
	_check(not pickup.visible and not pickup.is_active(), "pickup hidden while the room is in combat")
	_mage.global_position = pickup.global_position
	await _frames(3)
	_check(not _run.is_collected(&"swift_boots"), "pickup cannot be collected during combat")
	_mage.global_position = pickup.global_position + Vector2(0, 150)
	await _frames(2)
	await _kill_all(room)
	_check(room.state == Room.State.CLEARED and pickup.visible and pickup.is_active(), "pickup appears once the room is cleared")
	_mage.global_position = pickup.global_position
	await _frames(3)
	_check(_run.is_collected(&"swift_boots") and not is_instance_valid(pickup), "touching the pickup collects it and removes it")
	_check(is_equal_approx(_mage.speed_multiplier, 1.15), "Swift Boots: +15%% move speed (%.2f)" % _mage.speed_multiplier)
	_check(not _run.collect_item(&"swift_boots"), "an item cannot be collected twice")
	_run.changed.emit()
	_run.changed.emit()
	_check(is_equal_approx(_mage.speed_multiplier, 1.15), "repeated recalculation does not stack the bonus")
	_check(_items_label().visible and _items_label().text.contains("Swift Boots (+15% move speed)"), "HUD lists the item (%s)" % _items_label().text)

	# --- Heart Crystal and Ember Shard ---
	_dungeon.enter_room(_dungeon.index_at(HEART_ROOM), &"DoorBottom")
	await _frames(2)
	await _kill_all(_dungeon.current_room)
	var heart := _pickup(_dungeon.current_room)
	_check(heart != null and heart.item_id == &"heart_crystal", "Heart Crystal pickup placed in its room")
	_check(heart.collect() and is_equal_approx(_mage.health.max_health, base_hp + 25.0), "Heart Crystal: +25 max HP (%.0f)" % _mage.health.max_health)
	_check(not heart.collect() and is_equal_approx(_mage.health.max_health, base_hp + 25.0), "Heart Crystal applies only once")
	_dungeon.enter_room(_dungeon.index_at(SHARD_ROOM), &"DoorBottom")
	await _frames(2)
	await _kill_all(_dungeon.current_room)
	var shard := _pickup(_dungeon.current_room)
	_check(shard != null and shard.collect(), "Ember Shard collected")
	var expected := base_damage * (1.0 + 0.1 * (_run.level - 1) + 0.15)
	_check(is_equal_approx(_mage.caster.get_cast_spell().damage, expected), "Ember Shard: +15%% Fire Ball damage (%.2f)" % _mage.caster.get_cast_spell().damage)
	_check(_items_label().text.split("\n").size() == 3, "HUD lists all three items")

	# --- Persistence and no farming ---
	_dungeon.enter_room(boots_index, &"DoorRight")
	await _frames(3)
	_check(_pickup(_dungeon.current_room) == null and is_equal_approx(_mage.speed_multiplier, 1.15)
			and is_equal_approx(_mage.health.max_health, base_hp + 25.0) and _run.collected.size() == 3,
			"items persist between rooms; revisiting gives no new pickup")

	# --- Restart resets items ---
	await _restart()
	_check(_run.collected.is_empty() and is_equal_approx(_mage.speed_multiplier, 1.0)
			and is_equal_approx(_mage.health.max_health, base_hp) and is_equal_approx(_mage.caster.get_cast_spell().damage, base_damage)
			and not _items_label().visible, "Restart resets items and their effects")
	_dungeon.enter_room(_dungeon.index_at(BOOTS_ROOM), &"DoorRight")
	await _frames(2)
	_check(_pickup(_dungeon.current_room) != null, "item pickup is back after Restart")


func _bind() -> void:
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage
	_run = _dungeon.run_state


func _restart() -> void:
	if not _mage.is_dead():
		_mage.take_damage(9999.0)
		await _frames(1)
	(current_scene.get_node(^"GameOverOverlay") as GameOverOverlay).restart()
	await _frames(3)
	_bind()


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


func _boss_shots(boss: Boss) -> Array:
	return _boss_shots_any().filter(func(p: Projectile) -> bool: return p.source == boss)


func _boss_shots_any() -> Array:
	return current_scene.get_children().filter(func(n: Node) -> bool:
		return n is Projectile and (n as Projectile).hostile_to_player and not n.is_queued_for_deletion())


func _clear_shots(boss: Boss) -> void:
	for shot: Projectile in _boss_shots(boss):
		shot.queue_free()
	await _frames(1)


func _kill_all(room: Room) -> void:
	for enemy in room.get_node(^"Enemies").get_children():
		(enemy as Enemy).take_damage(9999.0)
	await _frames(2)


func _items_label() -> Label:
	return current_scene.get_node(^"RunHud/ItemsLabel") as Label


func _message() -> String:
	return (current_scene.get_node(^"RunHud/MessageLabel") as Label).text


func _room_hud_text() -> String:
	return (current_scene.get_node(^"RoomHud/StatusLabel") as Label).text


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
