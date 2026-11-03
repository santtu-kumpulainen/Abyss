extends SceneTree
## Headless check of the room combat loop and room layouts for every room test
## scene in SCENES (each has Room, Mage, RoomHud and GameOverOverlay nodes).
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_room_combat.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENES: Array[String] = [
	"res://scenes/test/room_test.tscn",
	"res://scenes/test/crypt_room_test.tscn",
	"res://scenes/test/cave_room_test.tscn",
]
## Free space kept in front of every door (depth into the room, in pixels).
const DOOR_LANE_DEPTH := 96.0
## Clearance radius around the player spawn and enemy spawns.
const SPAWN_CLEARANCE := 28.0

var _failures := 0
var _prefix := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for scene in SCENES:
		_prefix = scene.get_file().get_basename()
		await _test_scene(scene)
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_scene(path: String) -> void:
	var scene_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(path)
	await _wait_for_scene(scene_id)

	# --- Layout ---
	var room := current_scene.get_node(^"Room") as Room
	var mage := current_scene.get_node(^"Mage") as Mage
	var hud_label := current_scene.get_node(^"RoomHud/StatusLabel") as Label
	var enemy_count := room.enemies_remaining
	_check(enemy_count >= 2, "room has an enemy group (%d)" % enemy_count)
	_check_layout(room, mage)

	# --- Initial state ---
	_check(room.state == Room.State.IDLE, "room starts IDLE")
	_check(_doors_locked(room) == 0, "doors start unlocked")
	_check(_active_enemies(room) == 0, "enemies start inactive")
	_check(not hud_label.visible, "HUD hidden while idle")

	# --- Encounter start: the Mage walks up from the spawn into the trigger ---
	await _hold(&"move_up", 60, func() -> bool: return room.state != Room.State.IDLE)
	_check(room.state == Room.State.COMBAT, "walking from spawn into trigger starts COMBAT")
	_check(_doors_locked(room) == room.get_doors().size(), "all doors locked in combat")
	_check(_door_shapes_enabled(room) == room.get_doors().size(), "locked door colliders enabled")
	_check(_active_enemies(room) == enemy_count, "all enemies active in combat")
	await _frames(10)
	await _check_enemy_animations(room, mage)
	_check(hud_label.visible and hud_label.text == "Enemies remaining: %d" % enemy_count,
			"HUD shows %d remaining" % enemy_count)

	# Locked bottom door blocks the way out.
	var bottom_door := room.get_node(^"Doors/DoorBottom") as Door
	mage.global_position = bottom_door.global_position + Vector2(0, -60)
	await _hold(&"move_down", 40)
	_check(mage.global_position.y < bottom_door.global_position.y - 16.0, "locked door blocks the Mage")

	# --- Kill enemies one by one ---
	var enemies := room.get_node(^"Enemies").get_children()
	for i in enemies.size():
		(enemies[i] as Enemy).take_damage(9999.0)
		await _frames(2)
		var left := enemies.size() - i - 1
		_check(room.enemies_remaining == left, "remaining count = %d" % left)
		if left > 0:
			_check(room.state == Room.State.COMBAT and _doors_locked(room) == room.get_doors().size(),
					"still COMBAT, doors locked with %d left" % left)
			_check(hud_label.text == "Enemies remaining: %d" % left, "HUD shows %d remaining" % left)
	_check(room.state == Room.State.CLEARED, "room CLEARED after last kill")
	_check(_doors_locked(room) == 0, "doors unlocked when cleared")
	_check(_door_shapes_enabled(room) == 0, "door colliders disabled when cleared")
	_check(hud_label.text == "Room cleared", "HUD shows Room cleared")
	_check(not mage.is_dead() and mage.is_physics_processing(), "Mage alive and controllable")

	# Unlocked bottom door lets the Mage through.
	mage.global_position = bottom_door.global_position + Vector2(0, -60)
	await _hold(&"move_down", 60)
	_check(mage.global_position.y > bottom_door.global_position.y + 16.0, "Mage walks through unlocked door")

	# --- Mage death mid-encounter, then Restart ---
	reload_current_scene()
	await _frames(3)
	room = current_scene.get_node(^"Room") as Room
	mage = current_scene.get_node(^"Mage") as Mage
	room.start_encounter()
	await _frames(1)
	(room.get_node(^"Enemies").get_child(0) as Enemy).take_damage(9999.0)
	await _frames(2)
	_check(room.enemies_remaining == enemy_count - 1 and room.state == Room.State.COMBAT,
			"mid-encounter: %d left" % (enemy_count - 1))
	mage.take_damage(9999.0)
	await _frames(1)
	var overlay := current_scene.get_node(^"GameOverOverlay") as GameOverOverlay
	_check(mage.is_dead() and overlay.visible, "Game Over shown on Mage death")
	var old_scene := current_scene
	scene_id = current_scene.get_instance_id() if current_scene else 0
	overlay.restart()
	await _wait_for_scene(scene_id)
	_check(current_scene != old_scene, "Restart reloaded the scene")
	room = current_scene.get_node(^"Room") as Room
	mage = current_scene.get_node(^"Mage") as Mage
	overlay = current_scene.get_node(^"GameOverOverlay") as GameOverOverlay
	hud_label = current_scene.get_node(^"RoomHud/StatusLabel") as Label
	_check(room.state == Room.State.IDLE and room.enemies_remaining == enemy_count,
			"after Restart: room IDLE with %d enemies" % enemy_count)
	_check(_active_enemies(room) == 0 and _doors_locked(room) == 0,
			"after Restart: enemies inactive, doors unlocked")
	_check(not hud_label.visible and not overlay.visible, "after Restart: HUD and Game Over hidden")
	_check(not mage.is_dead() and mage.health.current == mage.health.max_health,
			"after Restart: Mage full health")


## Spawn, doors, walls and props are consistent and leave the play space open.
func _check_layout(room: Room, mage: Mage) -> void:
	var spawn := room.get_node(^"PlayerSpawn") as Marker2D
	_check(mage.global_position.is_equal_approx(spawn.global_position), "Mage starts at PlayerSpawn")
	var trigger_shape := room.get_node(^"EncounterTrigger/CollisionShape2D") as CollisionShape2D
	var trigger_rect := _shape_rect(trigger_shape)
	_check(not trigger_rect.has_point(spawn.global_position), "spawn is outside the encounter trigger")

	var visuals := room.get_node(^"Visuals") as RoomVisuals
	_check(visuals.theme != null, "room has a visual theme")
	var wall_rects := visuals.get_wall_rects()
	_check(wall_rects.size() == room.get_node(^"Walls").get_child_count(), "wall art drawn for every wall collider")
	var interior := Rect2(32, 32, 1088, 584)

	# Keep-clear zones: in front of each door, around the spawn and enemy spawns.
	var keep_clear: Array[Rect2] = []
	for door in room.get_doors():
		var inward := (interior.get_center() - door.global_position).normalized().round()
		var lane_center := door.global_position + inward * (16.0 + DOOR_LANE_DEPTH / 2.0)
		var lane_size := Vector2(96, DOOR_LANE_DEPTH) if inward.x == 0.0 else Vector2(DOOR_LANE_DEPTH, 96)
		keep_clear.append(Rect2(lane_center - lane_size / 2.0, lane_size))
	keep_clear.append(_square(spawn.global_position, SPAWN_CLEARANCE))
	for enemy in room.get_node(^"Enemies").get_children():
		keep_clear.append(_square((enemy as Node2D).global_position, SPAWN_CLEARANCE))

	var obstacles := 0
	var blocking_decor := 0
	for decor in room.get_node(^"Decor").get_children():
		# An UpgradeStation's solid part is its Anvil obstacle (its InteractArea is a non-blocking sensor).
		var prop: Node = decor.get_node(^"Anvil") if decor is UpgradeStation else decor
		if prop is Obstacle:
			obstacles += 1
			var footprint := _shape_rect(prop.get_node(^"CollisionShape2D"))
			var label := "%s footprint" % prop.name
			_check(interior.encloses(footprint), "%s inside the room" % label)
			var clear := true
			for zone in keep_clear:
				clear = clear and not zone.intersects(footprint)
			_check(clear, "%s keeps doors, spawn and enemy spawns clear" % label)
		elif not prop.find_children("*", "CollisionObject2D").is_empty() or prop is CollisionObject2D:
			blocking_decor += 1
	_check(blocking_decor == 0, "decorations without Obstacle have no collision")
	print("    (%d obstacles, %d decor nodes)" % [obstacles, room.get_node(^"Decor").get_child_count()])


## Every enemy plays an animation its SpriteFrames has; side-view enemies are
## mirrored towards the Mage when it stands to their left or right.
func _check_enemy_animations(room: Room, mage: Mage) -> void:
	for enemy: Enemy in room.get_node(^"Enemies").get_children():
		var sprite := enemy.get_node(^"AnimatedSprite2D") as AnimatedSprite2D
		_check(sprite.sprite_frames.has_animation(sprite.animation) and sprite.is_playing(),
				"%s plays a valid animation (%s)" % [enemy.name, sprite.animation])
		if not enemy.side_view:
			continue
		for side: float in [-1.0, 1.0]:
			mage.global_position = enemy.global_position + Vector2(side * 150.0, 0.0)
			await _frames(2)
			_check(sprite.flip_h == (side < 0.0),
					"%s side-view sprite faces the Mage (%s)" % [enemy.name, enemy.facing])
	mage.global_position = (room.get_node(^"PlayerSpawn") as Marker2D).global_position


func _shape_rect(shape_node: CollisionShape2D) -> Rect2:
	var size: Vector2 = (shape_node.shape as RectangleShape2D).size
	return Rect2(shape_node.global_position - size / 2.0, size)


func _square(center: Vector2, half: float) -> Rect2:
	return Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0)


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
	print("%s: [%s] %s" % ["PASS" if condition else "FAIL", _prefix, label])
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


## Scene changes are deferred: waits until a new, ready scene (not `old_id`) is current.
func _wait_for_scene(old_id: int) -> void:
	for i in 600:
		if current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready():
			break
		await process_frame
	await _frames(2)
