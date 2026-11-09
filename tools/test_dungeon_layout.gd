extends SceneTree
## Headless check of the seeded 5x5 dungeon layout (DungeonLayout, Issue #45)
## on the real room pool of scenes/dungeon/dungeon.tscn over many seeds:
## 25 rooms on distinct grid cells, the start / boss / antechamber anchors, the
## two dead-end puzzle rooms and their door sides, tiers by row, per-tier
## reachability, every pool room placed exactly once (so the XP budget holds),
## determinism and variation. Also checks that doorways are clear of solid
## props in every pool room (rooms now get doors on any side) and that the
## Dungeon scene uses the generated layout per dungeon level.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_dungeon_layout.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SCENE := "res://scenes/dungeon/dungeon.tscn"
const SEEDS := 400
const SEED := 4242
## Arrival point: how far inside a door the Mage appears (Dungeon.arrival_distance).
const ARRIVAL := 72.0
## Interactables (chests, altar, runes) must be at least this far from an arrival point.
const INTERACT_CLEARANCE := 120.0
const DOOR_DIRS := {&"DoorTop": Vector2i.UP, &"DoorBottom": Vector2i.DOWN, &"DoorLeft": Vector2i.LEFT, &"DoorRight": Vector2i.RIGHT}

var _failures := 0
var _pool: Array[RoomSpec] = []
var _start := 0
## Pool signature -> base XP of that room (scene-placed + RoomSpec.enemies).
var _xp := {}


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	var dungeon := (load(SCENE) as PackedScene).instantiate() as Dungeon
	_pool.assign(dungeon.rooms)
	_start = dungeon.start_room
	_check(dungeon.seeded_layout, "the dungeon scene uses the seeded layout")
	dungeon.free()
	for spec in _pool:
		_xp[_signature(spec)] = _room_xp(spec)
	_test_pool()
	_test_generator()
	_test_doorways()
	await _test_scene()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Pool -------------------------------------------------------------------------

func _test_pool() -> void:
	var slots := DungeonLayout.combat_slots()
	var t1 := _pool.filter(func(r: RoomSpec) -> bool: return _is_combat(r) and r.required_level == 1)
	var t2 := _pool.filter(func(r: RoomSpec) -> bool: return _is_combat(r) and r.required_level == 2)
	_check(_pool.size() == 25 and t1.size() == slots[1] + 1 and t2.size() == slots[2],
			"pool: 25 rooms = start + %d tier-1 + %d tier-2 combat rooms + boss + 2 puzzle rooms (%d / %d / %d)"
			% [slots[1], slots[2], _pool.size(), t1.size(), t2.size()])
	var xp1 := 0
	for spec: RoomSpec in t1:
		xp1 += _xp[_signature(spec)]
	var xp2 := 0
	for spec: RoomSpec in t2:
		xp2 += _xp[_signature(spec)]
	_check(xp1 == 51 and xp2 == 106 and xp1 + xp2 == MageLevels.PRE_BOSS_BASE_XP,
			"pool XP: tier 1 %d + tier 2 %d = PRE_BOSS_BASE_XP %d" % [xp1, xp2, MageLevels.PRE_BOSS_BASE_XP])


# --- Generator over many seeds ------------------------------------------------------

func _test_generator() -> void:
	var errors := {}
	var layouts := {}
	var boss_columns := {}
	var puzzle_cells := {}
	var trial_cells := {}
	var max_attempt := 0
	var deterministic := true
	for s in SEEDS:
		var seed_value := hash([s, "layout test"])
		var layout := DungeonLayout.generate(_pool, _start, seed_value)
		if layout.is_empty():
			errors["no layout generated"] = true
			continue
		max_attempt = maxi(max_attempt, layout["attempt"])
		for e in _validate(layout):
			errors[e] = true
		var key := _serialize(layout)
		layouts[key] = true
		deterministic = deterministic and _serialize(DungeonLayout.generate(_pool, _start, seed_value)) == key
		var rooms: Array[RoomSpec] = layout["rooms"]
		for spec in rooms:
			if spec.is_boss:
				boss_columns[spec.cell.x] = true
			elif spec.treasure == RoomSpec.Treasure.PUZZLE:
				puzzle_cells[spec.cell] = true
			elif spec.treasure == RoomSpec.Treasure.SURVIVAL:
				trial_cells[spec.cell] = true
	_check(errors.is_empty(), "%d seeds: every layout is valid%s" % [SEEDS, "" if errors.is_empty() else " - " + ", ".join(errors.keys())])
	print("INFO: worst seed needed %d retries (limit %d)" % [max_attempt, DungeonLayout.MAX_ATTEMPTS])
	_check(max_attempt < DungeonLayout.MAX_ATTEMPTS / 2, "layouts are found well within the retry limit (%d)" % max_attempt)
	_check(deterministic, "same seed -> identical layout (rooms, cells, links)")
	_check(layouts.size() >= SEEDS * 0.98, "different seeds -> different layouts (%d distinct of %d)" % [layouts.size(), SEEDS])
	_check(boss_columns.size() == DungeonLayout.BOSS_COLUMNS.size(), "the boss room uses every allowed top-row column (%s)" % [boss_columns.keys()])
	_check(puzzle_cells.size() >= 6 and trial_cells.size() >= 6,
			"puzzle rooms move around (rune %d cells, survival %d cells)" % [puzzle_cells.size(), trial_cells.size()])


## Rule violations of one generated layout (empty if valid).
func _validate(layout: Dictionary) -> Array[String]:
	var bad: Array[String] = []
	var rooms: Array[RoomSpec] = layout["rooms"]
	var by_cell := {}
	for i in rooms.size():
		by_cell[rooms[i].cell] = i
	if rooms.size() != 25 or by_cell.size() != 25:
		bad.append("25 distinct cells")
	if not rooms.all(func(r: RoomSpec) -> bool: return r.cell.x >= 0 and r.cell.x < 5 and r.cell.y >= 0 and r.cell.y < 5):
		bad.append("inside the 5x5 grid")
	if rooms[0].cell != DungeonLayout.START_CELL or _signature(rooms[0]) != _signature(_pool[_start]):
		bad.append("start room first at (2,4)")
	# Each pool room exactly once (and so the tier XP is unchanged).
	var used := rooms.map(_signature)
	var expected := _pool.map(_signature)
	used.sort()
	expected.sort()
	if used != expected:
		bad.append("every pool room placed once")
	for spec in rooms:
		if not spec.is_boss and spec.required_level != DungeonLayout.tier_of(spec.cell):
			bad.append("tier by row")
			break
	# Links: neighbouring cells, no duplicates.
	var neighbours := {}
	for i in rooms.size():
		neighbours[i] = []
	var seen := {}
	for link: String in layout["links"]:
		var ends := link.split(" - ")
		var a: int = by_cell.get(_cell(ends[0]), -1)
		var b: int = by_cell.get(_cell(ends[1]), -1)
		var key := "%d-%d" % [mini(a, b), maxi(a, b)]
		if a < 0 or b < 0 or absi(rooms[a].cell.x - rooms[b].cell.x) + absi(rooms[a].cell.y - rooms[b].cell.y) != 1 or seen.has(key):
			bad.append("links join distinct neighbouring cells")
			continue
		seen[key] = true
		neighbours[a].append(b)
		neighbours[b].append(a)
	var boss := rooms.find_custom(func(r: RoomSpec) -> bool: return r.is_boss)
	var anvil: int = by_cell.get(layout["anvil_cell"], -1)
	if boss < 0 or rooms[boss].cell.y != 0 or not DungeonLayout.BOSS_COLUMNS.has(rooms[boss].cell.x):
		bad.append("boss in the top row")
	elif neighbours[boss] != [anvil] or rooms[anvil].cell != rooms[boss].cell + Vector2i.DOWN or not _is_combat(rooms[anvil]):
		bad.append("antechamber below the boss is its only link")
	for kind in [RoomSpec.Treasure.PUZZLE, RoomSpec.Treasure.SURVIVAL]:
		var t := rooms.find_custom(func(r: RoomSpec) -> bool: return r.treasure == kind)
		if t < 0 or neighbours[t].size() != 1:
			bad.append("puzzle rooms are dead ends")
			continue
		var entry: int = neighbours[t][0]
		var side := rooms[entry].cell - rooms[t].cell
		if not _is_combat(rooms[entry]):
			bad.append("puzzle rooms open onto main rooms")
		if kind == RoomSpec.Treasure.PUZZLE and (rooms[t].cell.y < 3 or side == Vector2i.DOWN or rooms[entry].required_level != 1):
			bad.append("rune puzzle in tier 1, linked to tier 1, never through its bottom door")
		if kind == RoomSpec.Treasure.SURVIVAL and (rooms[t].cell.y > 2 or side == Vector2i.UP
				or (boss >= 0 and _manhattan(rooms[t].cell, rooms[boss].cell) <= 1) or (anvil >= 0 and _manhattan(rooms[t].cell, rooms[anvil].cell) <= 1)):
			bad.append("survival trial in tier 2, away from boss/antechamber, never through its top door")
	if _reach(rooms, neighbours, 1).size() != 10:
		bad.append("all tier-1 rooms reachable at Lv 1")
	if _reach(rooms, neighbours, 2).size() != 24:
		bad.append("all tier-1/2 rooms reachable at Lv 2")
	if _reach(rooms, neighbours, 3).size() != 25:
		bad.append("every room reachable")
	var crossings := 0
	for i in rooms.size():
		for j: int in neighbours[i]:
			if i < j and _is_combat(rooms[i]) and _is_combat(rooms[j]) and rooms[i].required_level != rooms[j].required_level:
				crossings += 1
	if crossings < DungeonLayout.MIN_TIER_LINKS:
		bad.append("at least %d routes into tier 2" % DungeonLayout.MIN_TIER_LINKS)
	return bad


## Rooms reachable from the start through rooms needing at most `level`.
func _reach(rooms: Array[RoomSpec], neighbours: Dictionary, level: int) -> Dictionary:
	var seen := {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for j: int in neighbours[i]:
			if not seen.has(j) and rooms[j].required_level <= level:
				seen[j] = true
				queue.append(j)
	return seen


# --- Doorways ------------------------------------------------------------------------

## Every pool room can get a door on any side: arrival points and door lanes
## must be free of solid props. Treasure rooms keep interactables away from the
## arrival points of the doors the layout allows (and the forbidden ones are
## the doors next to the chests).
func _test_doorways() -> void:
	var blocked: Array[String] = []
	var seen := {}
	for spec in _pool:
		var path := spec.scene.resource_path
		if seen.has(path):
			continue
		seen[path] = true
		var room := spec.scene.instantiate() as Room
		var obstacles := room.find_children("*", "Obstacle", true, false)
		var interactables := room.find_children("*", "Interactable", true, false)
		for door: Door in room.get_node(^"Doors").get_children():
			var inward := -Vector2(DOOR_DIRS[door.name])
			var arrival := door.position + inward * ARRIVAL
			# Lane: the doorway width from the wall to just past the arrival point.
			var lane := Rect2(door.position, Vector2.ZERO).expand(arrival + inward * 24.0)
			lane = lane.grow_individual(
					door.size.x / 2.0 if inward.y != 0.0 else 0.0, door.size.x / 2.0 if inward.x != 0.0 else 0.0,
					door.size.x / 2.0 if inward.y != 0.0 else 0.0, door.size.x / 2.0 if inward.x != 0.0 else 0.0)
			for o: Obstacle in obstacles:
				if Rect2(o.position - o.footprint / 2.0, o.footprint).intersects(lane):
					blocked.append("%s:%s blocked by %s" % [path.get_file(), door.name, o.name])
			var allowed := not (spec.treasure == RoomSpec.Treasure.PUZZLE and door.name == &"DoorBottom") \
					and not (spec.treasure == RoomSpec.Treasure.SURVIVAL and door.name == &"DoorTop")
			var near := interactables.filter(func(n: Node2D) -> bool: return n.position.distance_to(arrival) < INTERACT_CLEARANCE)
			if allowed and not near.is_empty():
				blocked.append("%s:%s arrives on %s" % [path.get_file(), door.name, near[0].name])
			if spec.is_treasure() and not allowed and near.is_empty():
				blocked.append("%s:%s is forbidden for no reason" % [path.get_file(), door.name])
		room.free()
	_check(blocked.is_empty(), "doorways of all %d room scenes are clear on every side%s" % [seen.size(), "" if blocked.is_empty() else ": " + ", ".join(blocked)])


# --- Scene ----------------------------------------------------------------------------

func _test_scene() -> void:
	RunState.seed_override = SEED
	change_scene_to_file(SCENE)
	for i in 600:
		if current_scene is Dungeon and current_scene.is_node_ready():
			break
		await process_frame
	await process_frame
	var dungeon := current_scene as Dungeon
	var run := dungeon.run_state
	var level1 := DungeonLayout.generate(_pool, _start, run.level_seed())
	_check(_serialize_rooms(dungeon.rooms, dungeon.links) == _serialize(level1) and dungeon.start_room == 0
			and dungeon.final_anvil_cell == level1["anvil_cell"], "the Dungeon uses the generated layout of its level seed")
	_check(dungeon._link_map.size() == dungeon.links.size() * 2 and dungeon.current_index == 0
			and dungeon.rooms[0].cell == DungeonLayout.START_CELL, "door links built from the layout; the run starts at (2,4)")
	_check(_validate({"rooms": dungeon.rooms, "links": dungeon.links, "anvil_cell": dungeon.final_anvil_cell}).is_empty(),
			"the scene's layout passes every layout rule")
	var cells1 := _serialize_rooms(dungeon.rooms, dungeon.links)
	run.dungeon_level = 2
	dungeon._plan_level()
	var cells2 := _serialize_rooms(dungeon.rooms, dungeon.links)
	_check(cells2 != cells1 and cells2 == _serialize(DungeonLayout.generate(_pool, _start, run.level_seed())),
			"dungeon level 2 gets its own seeded layout")
	run.dungeon_level = 1
	dungeon._plan_level()
	_check(_serialize_rooms(dungeon.rooms, dungeon.links) == cells1, "re-planning a level reproduces its layout")
	RunState.seed_override = 0


# --- Helpers ---------------------------------------------------------------------------

func _is_combat(spec: RoomSpec) -> bool:
	return not spec.is_boss and not spec.is_treasure()


func _signature(spec: RoomSpec) -> String:
	return "%s|%s|%s|%d|%d|%s" % [spec.scene.resource_path, spec.enemies.map(func(e: PackedScene) -> String: return e.resource_path),
			spec.item, spec.required_level, spec.treasure, spec.is_boss]


func _serialize(layout: Dictionary) -> String:
	return _serialize_rooms(layout["rooms"], layout["links"])


func _serialize_rooms(rooms: Array[RoomSpec], links: PackedStringArray) -> String:
	var parts := rooms.map(func(r: RoomSpec) -> String: return "%s=%s" % [r.cell, _signature(r)])
	var sorted_links := Array(links)
	sorted_links.sort()
	return ";".join(parts) + "#" + ",".join(sorted_links)


func _room_xp(spec: RoomSpec) -> int:
	var total := EncounterPlanner.lineup_xp(spec.enemies)
	var room := spec.scene.instantiate()
	for enemy in room.get_node(^"Enemies").get_children():
		total += (enemy as Enemy).xp_reward
	room.free()
	return total


func _cell(text: String) -> Vector2i:
	var parts := text.strip_edges().split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
