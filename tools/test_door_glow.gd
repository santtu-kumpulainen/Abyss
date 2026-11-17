extends SceneTree
## Headless check of the open-door glow (Issue #63): only open doors glow
## (never locked, sealed or level-locked ones), the glow faces the room
## interior for all four doors of every room scene, and in a real dungeon the
## doors of a room in combat stop glowing until it is cleared.
## (Drawing itself is checked with windowed screenshots; headless renders nothing.)
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_door_glow.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const ROOM_SCENES := [
	"res://scenes/rooms/arena_room.tscn", "res://scenes/rooms/cave_room.tscn",
	"res://scenes/rooms/crypt_room.tscn", "res://scenes/rooms/survival_room.tscn",
	"res://scenes/rooms/rune_puzzle_room.tscn", "res://scenes/rooms/templates/boss_gate_room.tscn",
	"res://scenes/rooms/templates/cave_template.tscn", "res://scenes/rooms/templates/crypt_template.tscn",
	"res://scenes/rooms/templates/dungeon_template.tscn",
]
const DUNGEON_SCENE := "res://scenes/dungeon/dungeon.tscn"
const FLOOR_CENTER := Vector2(576, 324)

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_states_and_direction()
	await _test_dungeon()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_states_and_direction() -> void:
	for path: String in ROOM_SCENES:
		var room := (load(path) as PackedScene).instantiate() as Room
		root.add_child(room)
		await process_frame
		var doors := room.get_doors()
		var facing_in := 0
		for door in doors:
			# The glow's inward axis (local +y times the inward sign) points at the floor centre.
			var inward_global := (door.global_transform.basis_xform(Vector2(0, door._inward))).normalized()
			if inward_global.dot(door.global_position.direction_to(room.to_global(FLOOR_CENTER))) > 0.9:
				facing_in += 1
		_check(doors.size() == 4 and facing_in == 4, "%s: all 4 door glows face the room interior" % path.get_file())
		var door := doors[0]
		door.locked = false
		door.sealed = false
		door.level_locked = false
		var open_glows := door.is_glowing()
		door.locked = true
		var locked := door.is_glowing()
		door.locked = false
		door.sealed = true
		var sealed := door.is_glowing()
		door.sealed = false
		door.level_locked = true
		var level_locked := door.is_glowing()
		door.level_locked = false
		_check(open_glows and not locked and not sealed and not level_locked and door.is_glowing(),
				"%s: glow only while open (open/locked/sealed/level-locked/reopened)" % path.get_file())
		room.free()


func _test_dungeon() -> void:
	RunState.seed_override = 4242
	var scene_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(DUNGEON_SCENE)
	for i in 600:
		if current_scene != null and current_scene.get_instance_id() != scene_id and current_scene.is_node_ready():
			break
		await process_frame
	await process_frame
	var dungeon := current_scene as Dungeon
	var start := dungeon.current_room
	var glowing := start.get_doors().filter(func(d: Door) -> bool: return d.is_glowing())
	var linked := start.get_doors().filter(func(d: Door) -> bool: return not d.sealed and not d.level_locked)
	_check(not glowing.is_empty() and glowing.size() == linked.size(),
			"start room: exactly the usable exits glow (%d of 4)" % glowing.size())
	# Enter a combat room through its door: doors lock (no glow) until it is cleared.
	var target := -1
	for n: int in dungeon.get_neighbours(dungeon.current_index):
		if dungeon.can_enter(n) and not dungeon.room_lineup(n).is_empty():
			target = n
			break
	dungeon.enter_room(target, dungeon.door_to(target, dungeon.current_index))
	await physics_frame
	await process_frame
	var room := dungeon.current_room
	_check(room.state == Room.State.COMBAT and room.get_doors().all(func(d: Door) -> bool: return not d.is_glowing()),
			"combat room: no door glows during the fight")
	for enemy in room.get_node(^"Enemies").get_children():
		if enemy is Enemy:
			(enemy as Enemy).take_damage(1.0e9)
	for i in 10:
		await physics_frame
	_check(room.state == Room.State.CLEARED and room.get_doors().any(func(d: Door) -> bool: return d.is_glowing()),
			"cleared room: its open exits glow again")
	RunState.seed_override = 0


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
