extends SceneTree
## Headless check of the boss fight (Abyss Warden in the Level 3 boss room) and
## its three health phases, the pre-boss anvil, and the collectible run items in the dungeon run (scenes/dungeon/dungeon.tscn):
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
	await _wait_for_scene(0)
	await _test_boss_fight()
	await _test_boss_mage_death_and_restart()
	await _test_items()
	await _test_final_anvil()
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
	_check(bar.visible and is_equal_approx(bar.max_value, 2100.0) and is_equal_approx(bar.value, 2100.0)
			and _boss_label(boss) == "Abyss Warden  -  Phase 1", "boss health bar shows 2100/2100, name and Phase 1 (%s)" % _boss_label(boss))
	_check(boss.phase == 1 and boss.current_volley_count() == 3 and is_equal_approx(boss.slam_radius, 200.0)
			and is_equal_approx(boss.current_slam_windup(), 1.4), "boss starts in Phase 1: 3-bolt volley, 200 px slam, 1.4 s wind-up")
	_check(boss.target == _mage, "boss targets the Mage from the boss room entrance")

	# --- Volley: telegraph, then 3 aimed bolts; the centre one hits the Mage ---
	var hp := _mage.health.current
	_check(boss.begin_attack(&"volley") and boss.state == Boss.State.WINDUP and _boss_shots(boss).is_empty(),
			"volley telegraphs before firing (no bolts during wind-up)")
	_check(not boss.begin_attack(&"slam"), "boss cannot start a second attack during a wind-up")
	await _wait_until(func() -> bool: return boss.state != Boss.State.WINDUP)
	var shots := _boss_shots(boss)
	_check(shots.size() == 3 and shots.all(func(p: Projectile) -> bool: return p.hostile_to_player and is_equal_approx(p.spell.damage, 10.0)),
			"volley fires 3 hostile bolts of 10 damage (%d)" % shots.size())
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	await _wait_until(func() -> bool: return _boss_shots(boss).is_empty(), 180)
	_check(is_equal_approx(_mage.health.current, hp - 10.0), "aimed centre bolt hits the Mage once (HP %.0f -> %.0f)" % [hp, _mage.health.current])
	boss.process_mode = Node.PROCESS_MODE_INHERIT

	# --- Slam: area damage only inside the telegraphed radius ---
	await _wait_until(func() -> bool: return boss.state == Boss.State.CHASE)
	_mage.global_position = boss.global_position + Vector2(0, 80)
	await _frames(1)
	hp = _mage.health.current
	var hits: Array[bool] = []
	boss.attack_resolved.connect(func(_a: StringName, hit: bool) -> void: hits.append(hit))
	boss.speed = 0.0
	boss.contact_damage = 0.0
	_check(boss.begin_attack(&"slam") and is_equal_approx(boss._windup_total, 1.4), "Phase 1 slam starts with a 1.4 s telegraph")
	await _wait_until(func() -> bool: return boss.state != Boss.State.WINDUP)
	_check(hits == [true] and is_equal_approx(_mage.health.current, hp - 22.0), "slam hits the Mage inside its radius for 22 (HP %.0f)" % _mage.health.current)
	await _wait_until(func() -> bool: return boss.state == Boss.State.CHASE)
	_mage.global_position = boss.global_position + Vector2(0, 210)
	await _frames(1)
	hp = _mage.health.current
	boss.begin_attack(&"slam")
	await _wait_until(func() -> bool: return boss.state != Boss.State.WINDUP)
	_check(hits == [true, false] and is_equal_approx(_mage.health.current, hp), "Mage just outside the 200 px slam radius takes no damage")
	# Escape from point-blank range at the Mage's base walking speed.
	await _wait_until(func() -> bool: return boss.state == Boss.State.CHASE)
	_mage.global_position = boss.global_position + Vector2(0, 30)
	await _frames(1)
	hp = _mage.health.current
	boss.begin_attack(&"slam")
	while boss.state == Boss.State.WINDUP:
		_mage.global_position += Vector2(0, _mage.speed / Engine.physics_ticks_per_second)
		await physics_frame
	_check(hits == [true, false, false] and is_equal_approx(_mage.health.current, hp),
			"Mage walking away from point-blank range escapes the slam (%.0f px)" % boss.global_position.distance_to(_mage.global_position))

	# --- Phases: 66% / 33% thresholds, entered once each, in order ---
	await _wait_until(func() -> bool: return boss.state == Boss.State.CHASE)
	_check(boss.phase_for_ratio(1.0) == 1 and boss.phase_for_ratio(0.67) == 1 and boss.phase_for_ratio(0.66) == 2
			and boss.phase_for_ratio(0.34) == 2 and boss.phase_for_ratio(0.33) == 3 and boss.phase_for_ratio(0.01) == 3,
			"phase thresholds: > 66% P1, <= 66% P2, <= 33% P3")
	var phases: Array[int] = []
	boss.phase_changed.connect(func(p: int) -> void: phases.append(p))
	boss.take_damage(700.0)
	_check(boss.phase == 1 and phases.is_empty() and is_equal_approx(bar.value, 1400.0), "still Phase 1 at 1400 HP (66.7%)")
	boss.take_damage(14.0)
	_check(boss.phase == 2 and phases == [2] and _boss_label(boss).ends_with("Phase 2") and _message().contains("Phase 2"),
			"Phase 2 at exactly 66%% HP (1386), announced (%s)" % _message())
	boss.take_damage(50.0)
	boss.take_damage(50.0)
	_check(boss.phase == 2 and phases == [2], "further damage in Phase 2 does not re-trigger the transition")
	_check(boss.current_volley_count() == 5 and is_equal_approx(boss.current_slam_windup(), 1.5), "Phase 2: 5-bolt volley, 1.5 s slam wind-up")
	await _clear_shots(boss)
	boss.begin_attack(&"volley")
	await _wait_until(func() -> bool: return boss.state != Boss.State.WINDUP)
	_check(_boss_shots(boss).size() == 5, "Phase 2 volley fires 5 bolts (%d)" % _boss_shots(boss).size())
	await _wait_until(func() -> bool: return boss.state == Boss.State.CHASE)
	boss.take_damage(boss.health.current - 693.0)
	_check(boss.phase == 3 and phases == [2, 3] and _boss_label(boss).ends_with("Phase 3"), "Phase 3 at exactly 33% HP (693)")
	boss.take_damage(100.0)
	_check(phases == [2, 3], "no further phase changes in Phase 3")
	_check(boss.current_volley_count() == 8 and is_equal_approx(boss.current_slam_windup(), 1.6), "Phase 3: 8-bolt volley, 1.6 s slam wind-up")
	await _clear_shots(boss)
	boss.begin_attack(&"volley")
	await _wait_until(func() -> bool: return boss.state != Boss.State.WINDUP)
	var dirs: Array = _boss_shots(boss).map(func(p: Projectile) -> Vector2: return p.direction)
	_check(dirs.size() == 8, "Phase 3 volley fires 8 bolts (%d)" % dirs.size())
	var aim := boss._aim
	_check(dirs.all(func(d: Vector2) -> bool: return absf(rad_to_deg(d.angle_to(aim))) >= 5.9),
			"Phase 3 volley leaves a gap on the aim line (even count, 12 deg spacing)")
	await _wait_until(func() -> bool: return boss.state == Boss.State.CHASE)
	await _clear_shots(boss)
	boss.begin_attack(&"ring")
	await _wait_until(func() -> bool: return boss.state != Boss.State.WINDUP)
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
	_check(boss != null and is_equal_approx(boss.health.current, 2100.0) and boss.phase == 1, "fresh boss at full health, Phase 1 after Restart")
	var phases: Array[int] = []
	boss.phase_changed.connect(func(p: int) -> void: phases.append(p))
	boss.take_damage(1500.0)
	_check(boss.phase == 3 and phases == [2, 3], "a damage spike from Phase 1 to 3 still enters Phase 2 then 3, once each (%s)" % [phases])
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


func _test_final_anvil() -> void:
	await _restart()
	var ante_index := _dungeon.index_at(ANTECHAMBER)
	var boss_index := _dungeon.index_at(BOSS)
	_check(_dungeon.final_anvil == null and not _dungeon.all_rooms_cleared(), "no pre-boss anvil at the start of a run")
	# Clear every non-boss room except the antechamber.
	for i in _dungeon.rooms.size():
		if i == ante_index or i == boss_index:
			continue
		await _clear_room(i)
	_check(not _dungeon.all_rooms_cleared() and _dungeon.final_anvil == null, "anvil still unavailable with one non-boss room left")
	_dungeon.enter_room(ante_index, &"DoorBottom")
	await _frames(2)
	var ante := _dungeon.current_room
	_check(_stations(ante).is_empty(), "antechamber has no anvil before the full clear")
	await _kill_all(ante)
	var anvil := _dungeon.final_anvil
	_check(_dungeon.all_rooms_cleared() and anvil != null and _stations(ante) == [anvil] and anvil.run_state == _run,
			"clearing the last room adds one anvil to the antechamber, bound to the run")
	_check(_message().contains("anvil"), "the anvil is announced (%s)" % _message())
	_check(not _dungeon.is_cleared(boss_index) and not _dungeon.is_visited(boss_index), "boss room untouched by the anvil")
	# Usable with the normal upgrade logic.
	_mage.global_position = anvil.global_position + Vector2(0, 50)
	await _frames(3)
	anvil.set_open(true)
	var gold := _run.currency
	_check(anvil.is_usable() and anvil.is_open and anvil.purchase(&"vitality") and _run.currency == gold - 100
			and _run.is_purchased(&"vitality"), "pre-boss anvil sells upgrades through the shared RunState (gold %d)" % _run.currency)
	_check(not anvil.purchase(&"vitality") and _run.currency == gold - 100, "duplicate purchase still blocked")
	# Revisits and repeated clears do not duplicate it.
	_dungeon.enter_room(_dungeon.index_at(Vector2i(2, 2)), &"DoorTop")
	await _frames(2)
	_dungeon.enter_room(ante_index, &"DoorBottom")
	await _frames(2)
	_dungeon._on_room_cleared()
	_check(_dungeon.final_anvil == anvil and _stations(ante) == [anvil] and not anvil.is_open, "anvil stays (single, closed) on revisit")
	# Boss room is still a normal fight with no anvil inside.
	_dungeon.enter_room(boss_index, &"DoorBottom")
	await _frames(2)
	_check(_dungeon.current_room.state == Room.State.COMBAT and _stations(_dungeon.current_room).is_empty(),
			"boss room has no anvil and its fight starts normally")
	await _restart()
	_check(_dungeon.final_anvil == null and _run.purchased.is_empty() and _run.currency == 0, "Restart removes the pre-boss anvil and purchases")


func _clear_room(index: int) -> void:
	_dungeon.enter_room(index)
	await _frames(1)
	_dungeon.current_room.start_encounter()
	await _kill_all(_dungeon.current_room)


func _stations(room: Room) -> Array:
	return room.find_children("*", "UpgradeStation", true, false).filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())


func _bind() -> void:
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage
	_run = _dungeon.run_state


func _restart() -> void:
	if not _mage.is_dead():
		_mage.take_damage(9999.0)
		await _frames(1)
	var old_id := current_scene.get_instance_id()
	(current_scene.get_node(^"GameOverOverlay") as GameOverOverlay).restart()
	await _wait_for_scene(old_id)


## Scene changes are deferred; waits until a new, ready scene (not `old_id`) is current, then binds.
func _wait_for_scene(old_id: int) -> void:
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_bind()


func _boss(room: Room) -> Boss:
	for child in room.get_node(^"Enemies").get_children():
		if child is Boss and not child.is_queued_for_deletion():
			return child
	return null


func _boss_label(boss: Boss) -> String:
	return (boss.get_node(^"BossBar/NameLabel") as Label).text


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
