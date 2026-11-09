extends SceneTree
## Headless check of the ranged enemy (RangedEnemy / Demon Caster) and enemy
## projectiles: ownership, cooldown, cleanup, AI spacing, death safety, and its
## integration with room combat, rewards, revisits and Restart in the dungeon.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_ranged_enemy.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const ROOM_SCENE := "res://scenes/test/cave_room_test.tscn"
const SEED := 4242
const DUNGEON_SCENE := "res://scenes/dungeon/dungeon.tscn"
## Clear vertical lane in the Cave room (no obstacles between these points).
const LANE_X := 680.0

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RunState.seed_override = SEED
	await _test_projectiles_and_ai()
	await _test_mage_death()
	await _test_dungeon_integration()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	RunState.seed_override = 0
	quit(1 if _failures > 0 else 0)


## Loads the Cave test room, starts combat and freezes every enemy except the caster.
func _setup_room() -> Array:
	var scene_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(ROOM_SCENE)
	await _wait_for_scene(scene_id)
	var room := current_scene.get_node(^"Room") as Room
	var mage := current_scene.get_node(^"Mage") as Mage
	var caster := room.get_node(^"Enemies/DemonCaster") as RangedEnemy
	room.start_encounter()
	await _frames(1)
	for enemy in room.get_node(^"Enemies").get_children():
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	return [room, mage, caster]


func _test_projectiles_and_ai() -> void:
	var setup: Array = await _setup_room()
	var room: Room = setup[0]
	var mage: Mage = setup[1]
	var caster: RangedEnemy = setup[2]
	_check(caster != null, "Cave room contains a RangedEnemy (DemonCaster)")
	if caster == null:
		return
	_check(caster.attack_range > caster.retreat_distance and caster.attack_cooldown > 0.0
			and caster.projectile_damage > 0.0 and caster.projectile_speed > 0.0,
			"caster has range %.0f, retreat %.0f, cooldown %.1fs, damage %.0f, speed %.0f"
			% [caster.attack_range, caster.retreat_distance, caster.attack_cooldown, caster.projectile_damage, caster.projectile_speed])

	# --- Projectile hits and damages the Mage ---
	mage.global_position = Vector2(LANE_X, 320)
	caster.global_position = Vector2(LANE_X, 150)
	await _frames(1)
	var hp := mage.health.current
	var shot := caster.fire(mage.global_position)
	_check(shot != null and shot.hostile_to_player and shot.source == caster, "fire() spawns an enemy-owned projectile")
	_check(shot.collision_layer == 16 and shot.collision_mask == 3, "enemy projectile: layer enemy_projectiles, mask world+player")
	_check(is_equal_approx(shot.spell.damage, caster.projectile_damage) and is_equal_approx(shot.spell.speed, caster.projectile_speed)
			and shot.spell != caster.projectile, "projectile uses the caster's damage/speed without modifying the shared Spell")
	_check(caster.fire(mage.global_position) == null, "fire() is blocked while on cooldown")
	await _wait_freed(shot, 120)
	_check(not is_instance_valid(shot), "projectile freed after hitting the Mage")
	_check(is_equal_approx(mage.health.current, hp - caster.projectile_damage),
			"projectile damages the Mage once (%.0f -> %.0f)" % [hp, mage.health.current])

	# --- Projectile does not damage enemies ---
	var goblin := room.get_node(^"Enemies/GiantGoblin1") as Enemy
	mage.global_position = Vector2(300, 580)
	goblin.global_position = Vector2(LANE_X, 320)
	await _frames(1)
	var goblin_hp := goblin.health.current
	caster._attack_cooldown_left = 0.0
	var through := caster.fire(goblin.global_position)
	await _frames(60)
	_check(is_equal_approx(goblin.health.current, goblin_hp), "enemy projectile passes enemies without damaging them")
	_reset_cooldown(caster)
	var probe := caster.fire(goblin.global_position)
	probe._on_body_entered(goblin)
	probe._on_area_entered(goblin.get_node(^"Hurtbox") as Area2D)
	probe._on_body_entered(caster)
	_check(is_equal_approx(goblin.health.current, goblin_hp) and is_equal_approx(caster.health.current, caster.health.max_health)
			and not probe._spent, "ownership guard ignores enemies, hurtboxes and the shooter")
	var fire_ball := load("res://scenes/spells/fire_ball/fire_ball.tres") as Spell
	var player_shot := fire_ball.projectile_scene.instantiate() as Projectile
	player_shot.setup(fire_ball, Vector2.RIGHT, mage)
	current_scene.add_child(player_shot)
	hp = mage.health.current
	player_shot._on_body_entered(mage)
	_check(not player_shot.hostile_to_player and is_equal_approx(mage.health.current, hp),
			"player Fire Ball keeps its ownership (never hits the Mage)")
	player_shot.queue_free()

	# --- Cleanup: every projectile is freed by collision or lifetime ---
	await _wait_freed(through, 200)
	await _wait_freed(probe, 200)
	_check(not is_instance_valid(through) and not is_instance_valid(probe), "missed projectiles are freed (wall or lifetime)")
	_check(_projectile_count() == 0, "no projectiles left in the scene")

	# --- AI: holds position in range and cooldown limits firing ---
	goblin.global_position = Vector2(200, 200)
	mage.global_position = Vector2(LANE_X, 320)
	caster.global_position = Vector2(LANE_X, 150)
	_reset_cooldown(caster)
	var shots: Array[Projectile] = []
	caster.fired.connect(func(p: Projectile) -> void: shots.append(p))
	caster.process_mode = Node.PROCESS_MODE_INHERIT
	var start := caster.global_position
	await _frames(int(caster.attack_cooldown * 60.0) - 10)
	_check(shots.size() == 1, "one shot within the first cooldown window (%d)" % shots.size())
	_check(caster.global_position.distance_to(start) < 4.0, "caster holds position between retreat distance and range")
	await _frames(30)
	_check(shots.size() == 2, "fires again after the cooldown (%d)" % shots.size())

	# --- AI: approaches when far, retreats when close ---
	mage.global_position = Vector2(LANE_X, 560)
	caster.global_position = Vector2(LANE_X, 150)
	await _frames(20)
	_check(caster.global_position.y > 155.0, "caster approaches a Mage beyond attack range")
	mage.global_position = Vector2(LANE_X, 330)
	caster.global_position = Vector2(LANE_X, 270)
	await _frames(20)
	_check(caster.global_position.y < 265.0, "caster retreats from a Mage inside retreat distance")

	# --- Shooter dies with a projectile in flight ---
	caster.process_mode = Node.PROCESS_MODE_DISABLED
	mage.global_position = Vector2(LANE_X, 320)
	caster.global_position = Vector2(LANE_X, 150)
	await _frames(1)
	_reset_cooldown(caster)
	var orphan := caster.fire(mage.global_position)
	var remaining := room.enemies_remaining
	hp = mage.health.current
	caster.take_damage(9999.0)
	await _frames(2)
	_check(not is_instance_valid(caster) and room.enemies_remaining == remaining - 1, "caster can be defeated")
	await _wait_freed(orphan, 120)
	_check(not is_instance_valid(orphan) and mage.health.current < hp, "in-flight projectile still resolves safely after its shooter dies")

	# --- Room completion ---
	for enemy in room.get_node(^"Enemies").get_children():
		(enemy as Enemy).take_damage(9999.0)
	await _frames(2)
	_check(room.state == Room.State.CLEARED and room.get_doors().all(func(d: Door) -> bool: return not d.locked),
			"room clears and unlocks doors with the caster in the encounter")


func _test_mage_death() -> void:
	var setup: Array = await _setup_room()
	var mage: Mage = setup[1]
	var caster: RangedEnemy = setup[2]
	mage.global_position = Vector2(LANE_X, 320)
	caster.global_position = Vector2(LANE_X, 150)
	await _frames(1)
	var in_flight := caster.fire(mage.global_position)
	mage.take_damage(9999.0)
	_check(mage.is_dead(), "Mage killed")
	var shots: Array[Projectile] = []
	caster.fired.connect(func(p: Projectile) -> void: shots.append(p))
	_reset_cooldown(caster)
	caster.process_mode = Node.PROCESS_MODE_INHERIT
	await _frames(120)
	_check(shots.is_empty() and caster.target == null, "caster stops targeting and firing at a dead Mage")
	_check(not is_instance_valid(in_flight), "projectile in flight at Mage death is cleaned up")


func _test_dungeon_integration() -> void:
	var scene_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(DUNGEON_SCENE)
	await _wait_for_scene(scene_id)
	var dungeon := current_scene as Dungeon
	dungeon.run_state.xp_multiplier_override = 1.0
	dungeon.enter_room(_scene_room(dungeon, "cave_room"), dungeon.entry_door(_scene_room(dungeon, "cave_room")))
	await _frames(2)
	var cave := dungeon.current_room
	cave.start_encounter()
	await _frames(1)
	var caster := cave.get_node_or_null(^"Enemies/DemonCaster") as RangedEnemy
	_check(caster != null and cave.state == Room.State.COMBAT and cave.get_doors().all(func(d: Door) -> bool: return d.locked),
			"dungeon Cave: caster present and doors locked in combat")
	var xp := dungeon.run_state.xp
	var currency := dungeon.run_state.currency
	var level := dungeon.run_state.level
	caster.take_damage(9999.0)
	caster.died.emit()  # duplicate death signal before the enemy is freed
	await _frames(2)
	_check(dungeon.run_state.level == level and dungeon.run_state.xp == xp + 2 and dungeon.run_state.currency == currency + 10,
			"caster defeat grants 2 XP and 10 currency once")
	for enemy in cave.get_node(^"Enemies").get_children():
		(enemy as Enemy).take_damage(9999.0)
	await _frames(2)
	_check(cave.state == Room.State.CLEARED, "Cave clears with the caster")

	# Stray enemy projectiles are removed on room transition.
	var bolt := load("res://scenes/spells/enemy_bolt/enemy_bolt.tres") as Spell
	var stray := bolt.projectile_scene.instantiate() as Projectile
	stray.setup(bolt, Vector2.UP, null)
	dungeon.add_child(stray)
	xp = dungeon.run_state.xp
	currency = dungeon.run_state.currency
	dungeon.enter_room(_scene_room(dungeon, "crypt_room"), dungeon.entry_door(_scene_room(dungeon, "crypt_room")))
	await _frames(3)
	_check(not is_instance_valid(stray), "enemy projectiles cleared on room transition")
	dungeon.enter_room(_scene_room(dungeon, "cave_room"), dungeon.entry_door(_scene_room(dungeon, "cave_room")))
	await _frames(3)
	_check(dungeon.current_room == cave and cave.state == Room.State.CLEARED
			and cave.get_node(^"Enemies").get_child_count() == 0, "revisited Cave stays cleared; caster does not respawn")
	_check(dungeon.run_state.xp == xp and dungeon.run_state.currency == currency, "revisit grants no duplicate rewards")

	# Restart resets the run and the caster returns.
	scene_id = current_scene.get_instance_id() if current_scene else 0
	(current_scene.get_node(^"GameOverOverlay") as GameOverOverlay).restart()
	await _wait_for_scene(scene_id)
	dungeon = current_scene as Dungeon
	_check(dungeon.run_state.xp == 0 and dungeon.run_state.currency == 0 and dungeon.run_state.level == 1, "Restart resets the run")
	dungeon.enter_room(_scene_room(dungeon, "cave_room"), dungeon.entry_door(_scene_room(dungeon, "cave_room")))
	await _frames(2)
	var fresh := dungeon.current_room
	_check(fresh != cave and fresh.state != Room.State.CLEARED and fresh.enemies_remaining == 4
			and fresh.get_node_or_null(^"Enemies/DemonCaster") != null,
			"after Restart the Cave and its caster are fresh (state %d, %d enemies)" % [fresh.state, fresh.enemies_remaining])


func _reset_cooldown(caster: RangedEnemy) -> void:
	caster._attack_cooldown_left = 0.0


func _projectile_count() -> int:
	return current_scene.get_children().filter(func(n: Node) -> bool: return n is Projectile).size()


func _wait_freed(node: Node, max_frames: int) -> void:
	for i in max_frames:
		if not is_instance_valid(node):
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
