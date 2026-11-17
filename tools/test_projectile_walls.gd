extends SceneTree
## Headless check that spells fired next to walls work (Issue #63): the cast
## point sits above the Mage's feet and the projectile is wider than the feet,
## so near a wall it used to spawn inside the wall and burst at once.
## Covers every wall side, a corner, a closed door, a solid obstacle, firing
## into a wall (still stops there, no tunnelling), hitting an enemy that stands
## close to a wall, open-floor spawns (unchanged) and enemy/bouncing shots.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_projectile_walls.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const ROOM_SCENE := "res://scenes/test/room_test.tscn"
const TARGET_SCENE := "res://scenes/test/test_target.tscn"
const OBSTACLE_SCENE := "res://scenes/rooms/obstacle.tscn"
const BIG_WATER_BOLT := "res://scenes/spells/water_bolt/big_water_bolt.tres"
## Room floor (inside the 32 px walls of room_base.tscn: 32..1120 x 32..616).
const FLOOR := Rect2(32, 32, 1088, 584)
## Mage feet radius (mage.tscn) + 1 px: as close to a wall as the Mage gets.
const HUG := 9.0

var _failures := 0
var _room: Room
var _mage: Mage


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(ROOM_SCENE)
	await _wait_for_scene(scene_id)
	_room = current_scene.get_node(^"Room") as Room
	_mage = current_scene.get_node(^"Mage") as Mage
	# Only walls and doors: remove props so positions are deterministic.
	for child in _room.get_node(^"Decor").get_children():
		child.free()
	_mage.process_mode = Node.PROCESS_MODE_DISABLED
	_mage.caster.process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(2)

	await _test_open_floor_unchanged()
	await _test_wall_sides()
	await _test_fire_into_wall()
	await _test_closed_door()
	await _test_obstacle()
	await _test_enemy_near_wall()
	await _test_static_helper()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## Moves the Mage (feet) to `pos` and fires toward `target`.
func _fire(pos: Vector2, target: Vector2) -> Projectile:
	_mage.global_position = pos
	await _frames(2)
	_mage.caster._cooldown_left = 0.0
	return _mage.caster.try_cast(target)


func _overlaps_world(p: Projectile) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = p.spell.collision_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.collision_mask = Projectile.WORLD_MASK
	query.transform = Transform2D(0.0, p.global_position)
	return not p.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _test_open_floor_unchanged() -> void:
	var shot := await _fire(Vector2(576, 400), Vector2(576, 100))
	_check(shot != null and shot.global_position.is_equal_approx(_mage.caster.global_position),
			"open floor: projectile still spawns exactly at the cast point")
	await _frames(10)
	_check(is_instance_valid(shot) and shot.global_position.y < 360.0, "open floor: projectile flies toward the aim")
	_clear_projectiles()


func _test_wall_sides() -> void:
	# [Mage feet position, aim target, label]; each aims away from the wall it hugs.
	var cases := [
		[Vector2(200, FLOOR.position.y + HUG), Vector2(200, 500), "top wall, firing down"],
		[Vector2(200, FLOOR.position.y + HUG), Vector2(500, FLOOR.position.y + HUG - 27), "top wall, firing sideways along it"],
		[Vector2(FLOOR.position.x + HUG, 200), Vector2(600, 200), "left wall, firing right"],
		[Vector2(FLOOR.end.x - HUG, 200), Vector2(400, 200), "right wall, firing left"],
		[Vector2(200, FLOOR.end.y - HUG), Vector2(200, 100), "bottom wall, firing up"],
		[Vector2(FLOOR.position.x + HUG, FLOOR.position.y + HUG), Vector2(600, 500), "top-left corner, firing diagonally"],
	]
	for c in cases:
		var shot := await _fire(c[0], c[1])
		_check(shot != null and not _overlaps_world(shot), "%s: spawns clear of walls" % c[2])
		var start: Vector2 = shot.global_position if shot else Vector2.ZERO
		var aim: Vector2 = _mage.caster.global_position.direction_to(c[1])
		await _frames(8)
		var alive := is_instance_valid(shot)
		_check(alive and (shot.global_position - start).dot(aim) > 30.0 and FLOOR.has_point(shot.global_position),
				"%s: projectile survives and flies along the aim" % c[2])
		_check(alive and shot.direction.is_equal_approx(aim), "%s: aim direction unchanged" % c[2])
		_clear_projectiles()


func _test_fire_into_wall() -> void:
	var hits := 0
	for target in [Vector2(200, -200), Vector2(-300, 200)]:
		var pos := Vector2(200, FLOOR.position.y + HUG) if target.y < 0.0 else Vector2(FLOOR.position.x + HUG, 200)
		var shot := await _fire(pos, target)
		var spawned := shot != null
		var max_out := 0.0
		for i in 12:
			await physics_frame
			if not is_instance_valid(shot):
				break
			max_out = maxf(max_out, maxf(FLOOR.position.y - shot.global_position.y, FLOOR.position.x - shot.global_position.x))
		if spawned and not is_instance_valid(shot) and max_out < 32.0:
			hits += 1
	_check(hits == 2, "firing into an adjacent wall still bursts on the wall (no tunnelling)")
	_clear_projectiles()


func _test_closed_door() -> void:
	var door := _room.get_node(^"Doors/DoorTop") as Door
	door.locked = true
	await _frames(2)
	var shot := await _fire(Vector2(576, FLOOR.position.y + HUG), Vector2(576, 500))
	_check(shot != null and not _overlaps_world(shot), "closed door: spawns clear of the door")
	await _frames(8)
	_check(is_instance_valid(shot) and shot.global_position.y > 80.0, "closed door: shot away from it flies")
	_clear_projectiles()
	door.locked = false
	await _frames(2)


func _test_obstacle() -> void:
	var obstacle := (load(OBSTACLE_SCENE) as PackedScene).instantiate() as Obstacle
	obstacle.footprint = Vector2(48, 24)
	_room.add_child(obstacle)
	obstacle.global_position = Vector2(700, 300)
	await _frames(2)
	# Feet just below the footprint: the cast point is inside the obstacle.
	var below := Vector2(700, 300 + 12 + HUG)
	var shot := await _fire(below, Vector2(700, 600))
	_check(shot != null and not _overlaps_world(shot), "obstacle: spawns clear of the prop footprint")
	await _frames(8)
	_check(is_instance_valid(shot) and shot.global_position.y > 360.0, "obstacle: shot away from it flies")
	_clear_projectiles()
	var into := await _fire(below, Vector2(700, 0))
	var spawned := into != null
	await _frames(8)
	_check(spawned and not is_instance_valid(into), "obstacle: shot into it still stops on it")
	obstacle.free()
	await _frames(2)


func _test_enemy_near_wall() -> void:
	var target := (load(TARGET_SCENE) as PackedScene).instantiate()
	current_scene.add_child(target)
	target.global_position = Vector2(300, FLOOR.position.y + 30)
	await _frames(2)
	var before: float = target.health
	var shot := await _fire(Vector2(200, FLOOR.position.y + HUG), target.global_position)
	var spawned := shot != null
	await _frames(15)
	_check(spawned and is_instance_valid(target) and target.health < before,
			"an enemy standing next to the wall is still hit")
	if is_instance_valid(target):
		target.free()
	_clear_projectiles()


func _test_static_helper() -> void:
	var space := _room.get_world_2d().direct_space_state
	var free_point := Vector2(500, 400)
	_check(Projectile.clear_spawn_point(space, free_point + Vector2(0, 40), free_point, 26.0).is_equal_approx(free_point),
			"helper: open floor returns the muzzle unchanged")
	# Boss-sized bouncing bolt fired from a body hugging the top wall, muzzle 40 px up.
	var spell := load(BIG_WATER_BOLT) as Spell
	var feet := Vector2(300, FLOOR.position.y + 12.0)
	var spawn := Projectile.clear_spawn_point(space, feet, feet + Vector2(0, -40), spell.collision_radius)
	var circle := CircleShape2D.new()
	circle.radius = spell.collision_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.collision_mask = Projectile.WORLD_MASK
	query.transform = Transform2D(0.0, spawn)
	_check(space.intersect_shape(query, 1).is_empty() and FLOOR.has_point(spawn),
			"helper: a large (bouncing) bolt's muzzle inside a wall is moved onto the floor")


func _clear_projectiles() -> void:
	for child in current_scene.get_children():
		if child is Projectile or child is PixelEffect:
			child.free()


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1


func _wait_for_scene(old_id: int) -> void:
	for i in 600:
		if current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready():
			break
		await process_frame
	await _frames(2)
