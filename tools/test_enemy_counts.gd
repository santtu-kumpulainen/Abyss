extends SceneTree
## Headless check of the Issue #55 Stage 6 enemy counts and extra-enemy spawns:
## - limits: up to MAX_EXTRA_ENEMIES (12) extras, at most MAX_ROOM_ENEMIES (20)
##   enemies in a regular room, at most MAX_ELITE_EXTRAS (4) elite extras;
##   survival waves keep at most MAX_WAVE_EXTRA_ENEMIES (4) extras;
## - real Dungeon rooms on levels 1, 3, 5 and 10 (Normal and Abyssal): counts,
##   elite extras and every extra position valid (floor, doors, PlayerSpawn,
##   obstacles, spacing), sampled positions or free safe markers only;
## - deterministic sampling: same seed + room = same positions, another seed
##   differs, a rebuilt Dungeon with the same run seed places the same extras;
## - fallback to the free safe SpawnPoints markers when sampling finds nothing;
## - miniboss rooms (no extras, compensation by the unchanged rule), boss rooms
##   and survival rooms are unchanged.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_enemy_counts.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const DUNGEON := "res://scenes/dungeon/dungeon.tscn"
const TEMPLATES: Array[String] = ["res://scenes/rooms/templates/dungeon_template.tscn",
		"res://scenes/rooms/templates/cave_template.tscn", "res://scenes/rooms/templates/crypt_template.tscn"]
const GOBLIN := "res://scenes/enemies/giant_goblin.tscn"
const BLOOD_MONSTER := "res://scenes/enemies/blood_monster.tscn"
const LEVELS: Array[int] = [1, 3, 5, 10]
const SEED := 9090

var _failures := 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	_test_limits()
	_test_sampling()
	_test_elite_cap()
	for tier: int in [Difficulty.Tier.NORMAL, Difficulty.Tier.ABYSSAL]:
		for level in LEVELS:
			await _test_dungeon_rooms(tier, level)
	await _test_rebuild_is_identical()
	RunState.seed_override = 0
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Limits ---------------------------------------------------------------------

func _test_limits() -> void:
	_check(RunState.MAX_EXTRA_ENEMIES == 12 and RunState.MAX_ROOM_ENEMIES == 20 and RunState.MAX_ELITE_EXTRAS == 4
			and RunState.MAX_WAVE_EXTRA_ENEMIES == 4 and RunState.MINIBOSS_OMITTED_EXTRAS_CAP == 4,
			"limits: 12 extras, 20 per regular room, 4 elite extras, 4 extras per survival wave, miniboss rule 4")
	var cap_ok := true
	var room_ok := true
	var wave_ok := true
	var max_extras := 0
	var max_wave := 0
	for tier: int in Difficulty.TIERS:
		for level in range(1, 31):
			var run := RunState.new()
			run.difficulty = tier
			run.dungeon_level = level
			for required in [1, 2]:
				for planned in range(0, 21):
					var n := run.extra_room_enemies(required, 8, planned)
					cap_ok = cap_ok and n >= 0 and n <= RunState.MAX_EXTRA_ENEMIES
					room_ok = room_ok and planned + n <= maxi(RunState.MAX_ROOM_ENEMIES, planned)
					max_extras = maxi(max_extras, n)
			wave_ok = wave_ok and run.extra_wave_enemies() <= RunState.MAX_WAVE_EXTRA_ENEMIES
			max_wave = maxi(max_wave, run.extra_wave_enemies())
			run.free()
	_check(cap_ok and max_extras == RunState.MAX_EXTRA_ENEMIES, "extras never exceed 12 and reach it deep in the run (max %d)" % max_extras)
	_check(room_ok, "planned + extras never exceed 20 in a regular room")
	_check(wave_ok and max_wave == 4, "survival wave extras stay capped at 4 (max %d)" % max_wave)
	var run := RunState.new()
	run.difficulty = Difficulty.Tier.ABYSSAL
	run.dungeon_level = 30
	_check(run.extra_room_enemies(2, 8, 10) == 10 and run.extra_room_enemies(2, 8, 20) == 0 and run.extra_room_enemies(2, 8, 4) == 12,
			"the room cap leaves 20 - planned extras (10 planned: 10, 20 planned: 0, 4 planned: 12)")
	_check(run.extra_room_enemies(2, 0, 4) == 12, "extras no longer need free markers (sampled positions)")
	_check(run.miniboss_omitted_extras(2, 8) == 4 and run.miniboss_omitted_extras(2, 2) == 2,
			"miniboss compensation keeps the pre-Stage-6 rule (cap 4, free markers)")
	run.dungeon_level = 1
	run.difficulty = Difficulty.Tier.NORMAL
	_check(run.extra_room_enemies(1, 8, 4) == 0 and run.extra_room_enemies(2, 8, 4) == 0, "Normal level 1 rooms still get no extras")
	run.free()


# --- Sampling, validity, determinism, fallback -------------------------------------

func _test_sampling() -> void:
	for path in TEMPLATES:
		var name := path.get_file().get_basename()
		var room := _template(path, 4)
		var first := room.extra_spawn_points(12, 4, 1234)
		var again := room.extra_spawn_points(12, 4, 1234)
		var other := room.extra_spawn_points(12, 4, 98765)
		var markers := room.safe_extra_points(4)
		_check(first == again, "%s: same seed, same room -> identical positions" % name)
		_check(first != other, "%s: another seed -> different positions" % name)
		_check(first.size() == 12, "%s: 12 positions found (%d)" % [name, first.size()])
		var valid := true
		for i in first.size():
			var pos := first[i]
			if markers.has(pos):
				continue
			var others: Array[Vector2] = first.duplicate()
			others.remove_at(i)
			valid = valid and room.is_valid_extra_spawn(pos, others) and _independently_valid(room, pos, others)
		_check(valid, "%s: every sampled position is on the floor, clear of doors, obstacles, markers and the others" % name)
		# Fallback: nothing can be sampled -> the free safe markers, in order.
		room.extra_spawn_spacing = 100000.0
		var fallback := room.extra_spawn_points(3, 4, 1234)
		_check(fallback == markers.slice(0, mini(3, markers.size())), "%s: sampling impossible -> falls back to the free safe markers %s" % [name, fallback])
		var all_markers := room.extra_spawn_points(12, 4, 1234)
		_check(all_markers == markers, "%s: fallback never exceeds the free safe markers (%d)" % [name, all_markers.size()])
		room.free()


## The placement rules checked without Room.is_valid_extra_spawn(), from the room's nodes.
func _independently_valid(room: Room, pos: Vector2, others: Array[Vector2]) -> bool:
	var visuals := room.get_node(^"Visuals") as RoomVisuals
	var floor_rect := Rect2(visuals.position + visuals.floor_rect.position, visuals.floor_rect.size)
	if not floor_rect.grow(-room.extra_spawn_clearance).has_point(pos):
		return false
	for door in room.get_node(^"Doors").get_children():
		if pos.distance_to(_local(room, door as Node2D)) < 180.0:
			return false
	if room.has_node(^"PlayerSpawn") and pos.distance_to(_local(room, room.get_node(^"PlayerSpawn") as Node2D)) < 180.0:
		return false
	for node in room.find_children("*", "Obstacle", true, false):
		var o := node as Obstacle
		if Rect2(_local(room, o) - o.footprint / 2.0, o.footprint).grow(room.extra_spawn_clearance).has_point(pos):
			return false
	for path: NodePath in [^"Enemies", ^"SpawnPoints"]:
		for child in room.get_node(path).get_children():
			if pos.distance_to(_local(room, child as Node2D)) < room.extra_spawn_spacing:
				return false
	for other in others:
		if pos.distance_to(other) < room.extra_spawn_spacing:
			return false
	return true


# --- Elite cap ------------------------------------------------------------------------

func _test_elite_cap() -> void:
	var goblin := load(GOBLIN) as PackedScene
	var blood := load(BLOOD_MONSTER) as PackedScene
	var room := _template(TEMPLATES[0], 2)
	var spots := room.extra_spawn_points(12, 2, 55)
	var elite_pool: Array[PackedScene] = [blood]
	var added := room.add_extra_enemies(elite_pool, 12, 2, 180.0, spots, RunState.MAX_ELITE_EXTRAS)
	_check(added == 4 and _elites(room, 2) == 4, "an all-elite pool stops at 4 elite extras (%d added)" % added)
	room.free()
	room = _template(TEMPLATES[0], 2)
	spots = room.extra_spawn_points(12, 2, 55)
	var mixed: Array[PackedScene] = [blood, goblin]
	added = room.add_extra_enemies(mixed, 12, 2, 180.0, spots, RunState.MAX_ELITE_EXTRAS)
	_check(added == 12 and _elites(room, 2) == 4, "a mixed pool: 12 extras, 4 elites, the rest non-elite (%d elites)" % _elites(room, 2))
	room.free()
	room = _template(TEMPLATES[0], 2)
	added = room.add_extra_enemies(elite_pool, 3, 2)
	_check(added == mini(3, room.safe_extra_points(2).size()), "without positions or an elite limit the old marker behaviour is kept (%d)" % added)
	room.free()


# --- Real Dungeon rooms ------------------------------------------------------------

func _test_dungeon_rooms(tier: int, level: int) -> void:
	var dungeon := await _load(SEED)
	var run := dungeon.run_state
	run.difficulty = tier
	run.dungeon_level = level
	dungeon._plan_level()
	var label := "%s level %d" % [Difficulty.display_name(tier), level]
	var regular := 0
	var counts_ok := true
	var elite_ok := true
	var valid_ok := true
	var expected_ok := true
	var largest := 0
	var most_extras := 0
	var bad: Array[String] = []
	for i in dungeon.rooms.size():
		var spec := dungeon.rooms[i]
		if i == dungeon.current_index or dungeon._room_cache.has(i):
			continue
		var room := dungeon._get_room(i)
		var enemies := room.get_node(^"Enemies").get_children()
		if spec.is_boss:
			_check(enemies.filter(func(e: Node) -> bool: return e is Boss).size() == 1 and enemies.size() == _scene_enemies(spec.scene),
					"%s: the boss room holds only its scene enemies (%d)" % [label, enemies.size()])
			continue
		if dungeon._minibosses.has(i):
			var omitted := run.miniboss_omitted_extras(spec.required_level, _fresh_free_markers(dungeon, i))
			_check(enemies.all(func(e: Node) -> bool: return e is Miniboss) and enemies.size() == dungeon.miniboss_pair(i).size()
					and dungeon.miniboss_compensation_gold(i) == EncounterPlanner.extra_enemies_gold(_pool(dungeon, i, level), omitted),
					"%s: miniboss room %d: only its %d minibosses, compensation by the unchanged rule" % [label, i, enemies.size()])
			continue
		if spec.is_treasure() or room is SurvivalRoom or dungeon.room_lineup(i).is_empty():
			continue
		regular += 1
		var planned := dungeon.room_lineup(i).size() + _scene_enemies(spec.scene)
		var extras := enemies.size() - planned
		var markers := _fresh_markers(dungeon, i)
		var free := markers.size()
		var wanted := run.extra_room_enemies(spec.required_level, free, planned)
		largest = maxi(largest, enemies.size())
		most_extras = maxi(most_extras, extras)
		counts_ok = counts_ok and enemies.size() <= RunState.MAX_ROOM_ENEMIES and extras >= 0 and extras <= RunState.MAX_EXTRA_ENEMIES
		var extra_nodes := enemies.slice(planned)
		var elites := extra_nodes.filter(func(e: Node) -> bool: return (e as Enemy).elite).size()
		elite_ok = elite_ok and elites <= RunState.MAX_ELITE_EXTRAS
		# All wanted extras are placed unless the elite limit stopped an all-elite pool.
		var all_elite := _pool(dungeon, i, level).all(func(s: PackedScene) -> bool: return _is_elite(s))
		expected_ok = expected_ok and (extras == wanted or (all_elite and extras == mini(wanted, RunState.MAX_ELITE_EXTRAS)))
		if not (extras == wanted or all_elite):
			bad.append("room %d: %d of %d" % [i, extras, wanted])
		var placed: Array[Vector2] = []
		for e in extra_nodes:
			placed.append((e as Node2D).position)
		for k in placed.size():
			var pos := placed[k]
			if markers.has(pos):
				continue
			var others: Array[Vector2] = placed.duplicate()
			others.remove_at(k)
			# Validate against the room without the extras (they were placed after sampling).
			var probe := _without_extras(room, planned)
			if not _independently_valid(probe, pos, others):
				valid_ok = false
				bad.append("room %d extra at %s" % [i, pos])
			probe.free()
	_check(regular > 0, "%s: %d regular combat rooms built" % [label, regular])
	_check(counts_ok, "%s: rooms <= 20 enemies, <= 12 extras (largest %d, most extras %d)" % [label, largest, most_extras])
	_check(elite_ok, "%s: at most 4 elite extras per room" % label)
	_check(expected_ok, "%s: every room gets the extras the rules ask for %s" % [label, bad])
	_check(valid_ok, "%s: every sampled extra position is valid %s" % [label, bad])
	# Survival rooms: unchanged, extras per wave capped at 4.
	for i in dungeon.rooms.size():
		var room := dungeon._room_cache.get(i) as Room
		if room is SurvivalRoom:
			var trial := room as SurvivalRoom
			_check(trial.extra_per_wave == mini(Difficulty.data(tier)["extra_wave"] + LevelScaling.wave_extra_enemies(level), 4),
					"%s: survival room extras per wave %d (cap 4)" % [label, trial.extra_per_wave])


## A Dungeon rebuilt from the same run seed places the same extras at the same positions.
func _test_rebuild_is_identical() -> void:
	var first := await _extra_layout(SEED)
	var second := await _extra_layout(SEED)
	var other := await _extra_layout(SEED + 1)
	_check(not first.is_empty() and first == second, "same run seed on level 5: identical extra enemies and positions (%d rooms)" % first.size())
	_check(first != other, "another run seed: a different layout")


func _extra_layout(run_seed: int) -> Dictionary:
	var dungeon := await _load(run_seed)
	dungeon.run_state.dungeon_level = 5
	dungeon._plan_level()
	var layout := {}
	for i in dungeon.rooms.size():
		var spec := dungeon.rooms[i]
		if i == dungeon.current_index or spec.is_boss or spec.is_treasure() or dungeon._minibosses.has(i) or dungeon._room_cache.has(i):
			continue
		var room := dungeon._get_room(i)
		var rows: Array = []
		for e in room.get_node(^"Enemies").get_children():
			rows.append([(e as Node).scene_file_path, (e as Node2D).position])
		layout[i] = rows
	return layout


# --- Helpers -----------------------------------------------------------------------

func _load(run_seed: int) -> Dungeon:
	RunState.seed_override = run_seed
	change_scene_to_file(DUNGEON)
	for i in 600:
		if current_scene != null and current_scene.is_node_ready() and current_scene is Dungeon:
			break
		await physics_frame
	for i in 3:
		await physics_frame
	return current_scene as Dungeon


## A room template with `planned` goblins at its first markers (not in the tree).
func _template(path: String, planned: int) -> Room:
	var room := (load(path) as PackedScene).instantiate() as Room
	var scenes: Array[PackedScene] = []
	for i in planned:
		scenes.append(load(GOBLIN) as PackedScene)
	room.add_encounter_enemies(scenes)
	return room


## A fresh copy of room `index` with only its planned enemies (lineup + scene-placed).
func _without_extras(room: Room, planned: int) -> Room:
	var copy := (load(room.scene_file_path) as PackedScene).instantiate() as Room
	var enemies := copy.get_node(^"Enemies")
	for child in enemies.get_children():
		enemies.remove_child(child)
		child.free()
	var source := room.get_node(^"Enemies").get_children()
	for k in mini(planned, source.size()):
		var marker := Node2D.new()
		marker.position = (source[k] as Node2D).position
		enemies.add_child(marker)
	return copy


func _fresh_markers(dungeon: Dungeon, index: int) -> Array[Vector2]:
	var level := dungeon.run_state.dungeon_level
	var copy := Biomes.map_scene(dungeon.rooms[index].scene, level, "room_map").instantiate() as Room
	var result := copy.safe_extra_points(dungeon.room_lineup(index).size())
	copy.free()
	return result


func _fresh_free_markers(dungeon: Dungeon, index: int) -> int:
	return _fresh_markers(dungeon, index).size()


func _pool(dungeon: Dungeon, index: int, level: int) -> Array[PackedScene]:
	var pool: Array[PackedScene] = []
	for scene in dungeon.room_lineup(index):
		pool.append(Biomes.map_scene(scene, level, "enemy_map"))
	return pool


func _scene_enemies(scene: PackedScene) -> int:
	var copy := scene.instantiate()
	var n := copy.get_node(^"Enemies").get_child_count() if copy.has_node(^"Enemies") else 0
	copy.free()
	return n


func _is_elite(scene: PackedScene) -> bool:
	var e := scene.instantiate() as Enemy
	var elite := e.elite
	e.free()
	return elite


func _elites(room: Room, planned: int) -> int:
	return room.get_node(^"Enemies").get_children().slice(planned).filter(func(e: Node) -> bool: return (e as Enemy).elite).size()


func _local(room: Room, node: Node2D) -> Vector2:
	var xf := Transform2D.IDENTITY
	var current: Node = node
	while current != null and current != room:
		if current is Node2D:
			xf = (current as Node2D).transform * xf
		current = current.get_parent()
	return xf.origin


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
