extends SceneTree
## Headless check of room transitions and the fixed dungeon run
## (scenes/dungeon/dungeon.tscn: Hall -right- Crypt -top- Cave, the start of the 5x5 grid).
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_dungeon.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENE := "res://scenes/dungeon/dungeon.tscn"
const HALL := 0
const CRYPT := 1
const CAVE := 2

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(SCENE)
	await _wait_for_scene(scene_id)
	_bind()

	# --- Start: Hall, Mage at PlayerSpawn, only the linked door can open ---
	var hall := _dungeon.current_room
	_check(_dungeon.current_index == HALL, "run starts in the Hall")
	_check(_mage.global_position.is_equal_approx(_spawn(hall)), "Mage starts at the Hall PlayerSpawn")
	_check(hall.state == Room.State.IDLE and _active_enemies(hall) == 0, "Hall starts IDLE, enemies inactive")
	_check(_sealed_names(hall) == ["DoorBottom", "DoorTop"], "unlinked Hall doors are sealed")
	var full_hp := _mage.health.max_health

	# --- Hall encounter: doors locked, sealed doors stay shut after victory ---
	await _hold(&"move_up", 60, func() -> bool: return hall.state != Room.State.IDLE)
	_check(hall.state == Room.State.COMBAT and _all_locked(hall), "entering the Hall starts combat and locks doors")
	await _try_exit(hall, &"DoorRight", &"move_right")
	_check(_dungeon.current_index == HALL, "locked exit blocks the Mage during combat")
	_mage.take_damage(30.0)
	await _kill_all(hall)
	_check(hall.state == Room.State.CLEARED and _door(hall, &"DoorRight").is_open(), "Hall cleared, linked exit open")
	_check(not _door(hall, &"DoorBottom").is_open() and _shape_enabled(_door(hall, &"DoorBottom")),
			"sealed door stays shut after victory")
	await _try_exit(hall, &"DoorBottom", &"move_down")
	_check(_dungeon.current_index == HALL and _mage.global_position.y < 632.0, "sealed door blocks the Mage")

	# --- Hall -> Crypt (exit right, arrive left) ---
	await _go(hall, &"DoorRight", &"move_right", CRYPT, &"DoorLeft")
	var crypt := _dungeon.current_room
	await _frames(3)
	_check(crypt.state == Room.State.COMBAT and _all_locked(crypt)
			and _active_enemies(crypt) == crypt.enemies_remaining and crypt.enemies_remaining > 0,
			"Crypt encounter starts on arrival with all enemies active")
	_check(_hud_text() == "Enemies remaining: %d" % crypt.enemies_remaining, "HUD follows the new room")
	await _frames(10)
	_check(_dungeon.current_index == CRYPT, "no repeated transition while near the arrival door")
	await _kill_all(crypt)

	# --- Crypt -> Cave (exit top, arrive bottom) ---
	await _go(crypt, &"DoorTop", &"move_up", CAVE, &"DoorBottom")
	var cave := _dungeon.current_room
	_check(cave.state == Room.State.COMBAT and _all_locked(cave), "Cave encounter starts on arrival, doors locked behind")
	await _try_exit(cave, &"DoorBottom", &"move_down")
	_check(_dungeon.current_room == cave and _mage.global_position.y < 632.0, "Mage cannot leave the way it came during combat")
	await _kill_all(cave)

	# --- Back: Cave -> Crypt (exit bottom, arrive top), Crypt -> Hall (exit left, arrive right) ---
	await _go(cave, &"DoorBottom", &"move_down", CRYPT, &"DoorTop")
	_check(_dungeon.current_room == crypt and crypt.state == Room.State.CLEARED
			and crypt.get_node(^"Enemies").get_child_count() == 0 and _door(crypt, &"DoorLeft").is_open(),
			"revisited Crypt stays cleared, no respawn")
	_check(_hud_text() == "Room cleared", "HUD shows Room cleared on revisit")
	await _go(crypt, &"DoorLeft", &"move_left", HALL, &"DoorRight")
	_check(_dungeon.current_room == hall and hall.state == Room.State.CLEARED, "revisited Hall stays cleared")

	# --- Game Over and Restart reset the whole run ---
	_mage.take_damage(9999.0)
	await _frames(1)
	var overlay := current_scene.get_node(^"GameOverOverlay") as GameOverOverlay
	_check(_mage.is_dead() and overlay.visible, "Game Over shown on Mage death")
	var old_scene := current_scene
	scene_id = current_scene.get_instance_id() if current_scene else 0
	overlay.restart()
	await _wait_for_scene(scene_id)
	_bind()
	var room := _dungeon.current_room
	_check(current_scene != old_scene and _dungeon.current_index == HALL, "Restart starts a new run in the Hall")
	_check(room.state == Room.State.IDLE and room.enemies_remaining == 3 and _active_enemies(room) == 0,
			"after Restart: Hall IDLE with all enemies back")
	_check(not _mage.is_dead() and is_equal_approx(_mage.health.current, full_hp)
			and _mage.global_position.is_equal_approx(_spawn(room)), "after Restart: Mage full HP at spawn")
	_check(not (current_scene.get_node(^"GameOverOverlay") as CanvasLayer).visible, "after Restart: Game Over hidden")

	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _bind() -> void:
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage


## Walks out through `exit` and checks arrival in `to_index` just inside `arrive_door`,
## facing inwards, with HP unchanged.
func _go(from: Room, exit: StringName, action: StringName, to_index: int, arrive_door: StringName) -> void:
	var hp := _mage.health.current
	_check(hp < _mage.health.max_health, "Mage is damaged before leaving %s (HP %.0f)" % [from.name, hp])
	await _try_exit(from, exit, action)
	await _frames(1)
	var room := _dungeon.current_room
	var label := "%s:%s -> %d:%s" % [from.name, exit, to_index, arrive_door]
	_check(_dungeon.current_index == to_index and room != from, "%s transitions" % label)
	var door := _door(room, arrive_door)
	var inward := (room.get_node(^"Visuals") as RoomVisuals).floor_rect.get_center() - door.position
	inward = Vector2(signf(inward.x), 0) if absf(inward.x) > absf(inward.y) * 1152.0 / 648.0 else Vector2(0, signf(inward.y))
	var expected := door.global_position + inward * _dungeon.arrival_distance
	_check(_mage.global_position.distance_to(expected) < 4.0,
			"%s arrives in front of the door (%s, expected %s)" % [label, _mage.global_position, expected])
	_check(_mage.facing == Mage.direction_name(inward), "%s faces inwards (%s)" % [label, _mage.facing])
	_check(is_equal_approx(_mage.health.current, hp), "%s keeps HP (%.0f)" % [label, _mage.health.current])


## Places the Mage just inside `door_name` and holds `action` until the room changes.
func _try_exit(room: Room, door_name: StringName, action: StringName) -> void:
	var door := _door(room, door_name)
	var dir: Vector2 = {&"move_up": Vector2.UP, &"move_down": Vector2.DOWN,
			&"move_left": Vector2.LEFT, &"move_right": Vector2.RIGHT}[action]
	_mage.global_position = door.global_position - dir * 60.0
	await _hold(action, 50, func() -> bool: return _dungeon.current_room != room)


func _kill_all(room: Room) -> void:
	for enemy in room.get_node(^"Enemies").get_children():
		(enemy as Enemy).take_damage(9999.0)
	await _frames(2)


func _door(room: Room, door_name: StringName) -> Door:
	return room.get_node(NodePath("Doors/" + door_name)) as Door


func _spawn(room: Room) -> Vector2:
	return (room.get_node(^"PlayerSpawn") as Marker2D).global_position


func _sealed_names(room: Room) -> Array:
	var names := room.get_doors().filter(func(d: Door) -> bool: return d.sealed).map(
			func(d: Door) -> String: return String(d.name))
	names.sort()
	return names


func _all_locked(room: Room) -> bool:
	return room.get_doors().all(func(d: Door) -> bool: return d.locked and _shape_enabled(d))


func _shape_enabled(door: Door) -> bool:
	return not (door.get_node(^"CollisionShape2D") as CollisionShape2D).disabled


func _active_enemies(room: Room) -> int:
	return room.get_node(^"Enemies").get_children().filter(func(e: Node) -> bool: return e.can_process()).size()


func _hud_text() -> String:
	var label := current_scene.get_node(^"RoomHud/StatusLabel") as Label
	return label.text if label.visible else ""


## Holds an input action for up to `frames` physics frames, or until `until` returns true.
func _hold(action: StringName, frames: int, until := Callable()) -> void:
	Input.action_press(action)
	for i in frames:
		await physics_frame
		if until.is_valid() and until.call():
			break
	Input.action_release(action)
	await _frames(1)


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
