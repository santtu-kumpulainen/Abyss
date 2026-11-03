extends SceneTree
## Headless check of the room combat loop in res://scenes/test/room_test.tscn.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_room_combat.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENE := "res://scenes/test/room_test.tscn"

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	change_scene_to_file(SCENE)
	await _frames(3)

	# --- Initial state ---
	var room := current_scene.get_node(^"ArenaRoom") as Room
	var mage := current_scene.get_node(^"Mage") as Mage
	var hud_label := current_scene.get_node(^"RoomHud/StatusLabel") as Label
	_check(room.state == Room.State.IDLE, "room starts IDLE")
	_check(room.enemies_remaining == 3, "3 encounter enemies tracked")
	_check(_doors_locked(room) == 0, "doors start unlocked")
	_check(_active_enemies(room) == 0, "enemies start inactive")
	_check(not hud_label.visible, "HUD hidden while idle")

	# --- Encounter start: Mage walks into the trigger ---
	mage.global_position = Vector2(576, 400)
	await _frames(3)
	_check(room.state == Room.State.COMBAT, "entering trigger starts COMBAT")
	_check(_doors_locked(room) == 3, "all doors locked in combat")
	_check(_door_shapes_enabled(room) == 3, "locked door colliders enabled")
	_check(_active_enemies(room) == 3, "enemies active in combat")
	_check(hud_label.visible and hud_label.text == "Enemies remaining: 3", "HUD shows 3 remaining")

	# --- Kill enemies one by one ---
	var enemies := room.get_node(^"Enemies").get_children()
	for i in enemies.size():
		(enemies[i] as Enemy).take_damage(9999.0)
		await _frames(2)
		var left := enemies.size() - i - 1
		_check(room.enemies_remaining == left, "remaining count = %d" % left)
		if left > 0:
			_check(room.state == Room.State.COMBAT, "still COMBAT with %d left" % left)
			_check(_doors_locked(room) == 3, "doors locked with %d left" % left)
			_check(hud_label.text == "Enemies remaining: %d" % left, "HUD shows %d remaining" % left)
	_check(room.state == Room.State.CLEARED, "room CLEARED after last kill")
	_check(_doors_locked(room) == 0, "doors unlocked when cleared")
	_check(_door_shapes_enabled(room) == 0, "door colliders disabled when cleared")
	_check(hud_label.text == "Room cleared", "HUD shows Room cleared")
	_check(not mage.is_dead() and mage.is_physics_processing(), "Mage alive and controllable")

	# --- Mage death mid-encounter, then Restart ---
	var old_scene := current_scene
	reload_current_scene()
	await _frames(3)
	_check(current_scene != old_scene, "scene reloaded for second run")
	room = current_scene.get_node(^"ArenaRoom") as Room
	mage = current_scene.get_node(^"Mage") as Mage
	room.start_encounter()
	await _frames(1)
	(room.get_node(^"Enemies").get_child(0) as Enemy).take_damage(9999.0)
	await _frames(2)
	_check(room.enemies_remaining == 2 and room.state == Room.State.COMBAT, "mid-encounter: 2 left")
	mage.take_damage(9999.0)
	await _frames(1)
	var overlay := current_scene.get_node(^"GameOverOverlay") as GameOverOverlay
	_check(mage.is_dead() and overlay.visible, "Game Over shown on Mage death")
	old_scene = current_scene
	overlay.restart()
	await _frames(3)
	_check(current_scene != old_scene, "Restart reloaded the scene")
	room = current_scene.get_node(^"ArenaRoom") as Room
	mage = current_scene.get_node(^"Mage") as Mage
	overlay = current_scene.get_node(^"GameOverOverlay") as GameOverOverlay
	hud_label = current_scene.get_node(^"RoomHud/StatusLabel") as Label
	_check(room.state == Room.State.IDLE, "after Restart: room IDLE")
	_check(room.enemies_remaining == 3, "after Restart: 3 enemies")
	_check(_active_enemies(room) == 0, "after Restart: enemies inactive")
	_check(_doors_locked(room) == 0, "after Restart: doors unlocked")
	_check(not hud_label.visible, "after Restart: HUD hidden")
	_check(not mage.is_dead() and mage.health.current == mage.health.max_health, "after Restart: Mage full health")
	_check(not overlay.visible, "after Restart: Game Over hidden")

	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1


func _doors_locked(room: Room) -> int:
	return room.get_doors().filter(func(d: Door) -> bool: return d.locked).size()


func _door_shapes_enabled(room: Room) -> int:
	return room.get_doors().filter(
		func(d: Door) -> bool: return not (d.get_node(^"CollisionShape2D") as CollisionShape2D).disabled
	).size()


func _active_enemies(room: Room) -> int:
	return room.get_node(^"Enemies").get_children().filter(
		func(e: Node) -> bool: return e.can_process()
	).size()
