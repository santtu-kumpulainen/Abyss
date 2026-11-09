class_name DungeonLayout
extends RefCounted
## Seeded 5x5 dungeon layout (Issue #45). generate() places an authored room
## pool on the SIZE x SIZE grid and builds its door graph from one seed:
## - the start room stays at START_CELL (bottom centre);
## - the boss room sits at a seeded top-row cell (BOSS_COLUMNS) and its only
##   door leads to the antechamber directly below it (a tier-2 combat room that
##   gets the pre-boss anvil, see Dungeon.final_anvil_cell);
## - the Rune Puzzle is a dead end in the tier-1 rows, linked to a tier-1 room
##   and never through its bottom door (its chest stands there);
## - the Survival Trial is a dead end in the tier-2 rows, not next to the boss
##   room or the antechamber and never entered through its top door (chest);
## - the other cells get a seeded spanning tree (all tier-1 cells first, grown
##   from the start room, then tier 2) plus MIN_LOOPS..MAX_LOOPS extra links,
##   with at least MIN_TIER_LINKS links between the tiers;
## - tier-1 combat rooms of the pool (required_level 1) are shuffled over the
##   tier-1 rows (y >= TIER1_MIN_ROW), tier-2 combat rooms over the rows above.
## So every room is reachable through rooms of its own tier or lower, and the
## same seed always gives the same layout. Room geometry is never changed.

const SIZE := 5
const START_CELL := Vector2i(2, 4)
## Top-row columns the boss room may use.
const BOSS_COLUMNS: Array[int] = [1, 2, 3]
## First row of tier 1 (Mage level gate 1); the rows above are tier 2.
const TIER1_MIN_ROW := 3
const MIN_LOOPS := 2
const MAX_LOOPS := 4
## Fewest links between tier-1 and tier-2 main rooms (routes into tier 2).
const MIN_TIER_LINKS := 2
## Seeded retries before generate() gives up (a valid layout is normally found at once).
const MAX_ATTEMPTS := 64
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


## Places `pool` (authored RoomSpecs; `start_index` is the start room) on the
## grid. Returns {"rooms": Array[RoomSpec] (copies with their cells, start room
## first, then row by row), "links": PackedStringArray ("x,y - x,y"),
## "boss_cell", "anvil_cell", "attempt"}, or {} if the pool does not fit.
static func generate(pool: Array[RoomSpec], start_index: int, seed_value: int) -> Dictionary:
	var roles := _split_pool(pool, start_index)
	if roles.is_empty():
		return {}
	for attempt in MAX_ATTEMPTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "layout", attempt])
		var plan := _try_plan(rng)
		if not plan.is_empty():
			var result := _build(plan, roles, rng)
			result["attempt"] = attempt
			return result
	push_error("DungeonLayout: no valid layout for seed %d" % seed_value)
	return {}


## Tier of `cell`: 1 in the tier-1 rows, otherwise 2.
static func tier_of(cell: Vector2i) -> int:
	return 1 if cell.y >= TIER1_MIN_ROW else 2


## Number of combat rooms per tier the pool needs (start room excluded from tier 1).
static func combat_slots() -> Dictionary:
	var tier1 := SIZE * (SIZE - TIER1_MIN_ROW) - 2  # minus start room and Rune Puzzle
	var tier2 := SIZE * TIER1_MIN_ROW - 2  # minus boss room and Survival Trial
	return {1: tier1, 2: tier2}


## Pool roles: {"start", "boss", "survival", "puzzle": RoomSpec, 1 / 2: Array of tier combat rooms}.
static func _split_pool(pool: Array[RoomSpec], start_index: int) -> Dictionary:
	if start_index < 0 or start_index >= pool.size():
		push_error("DungeonLayout: bad start room index %d" % start_index)
		return {}
	var roles := {"start": pool[start_index], 1: [], 2: []}
	for i in pool.size():
		var spec := pool[i]
		if i == start_index:
			continue
		if spec.is_boss:
			roles["boss"] = spec
		elif spec.treasure == RoomSpec.Treasure.SURVIVAL:
			roles["survival"] = spec
		elif spec.treasure == RoomSpec.Treasure.PUZZLE:
			roles["puzzle"] = spec
		else:
			roles[1 if spec.required_level <= 1 else 2].append(spec)
	var slots := combat_slots()
	if not (roles.has("boss") and roles.has("survival") and roles.has("puzzle")) \
			or roles[1].size() != slots[1] or roles[2].size() != slots[2]:
		push_error("DungeonLayout: the pool needs a start, boss, survival and puzzle room plus %d tier-1 and %d tier-2 combat rooms (has %d / %d)"
				% [slots[1], slots[2], roles[1].size(), roles[2].size()])
		return {}
	return roles


## One seeded attempt: {"boss", "anvil", "puzzle", "survival": Vector2i, "edges": Array of [a, b]}, or {}.
static func _try_plan(rng: RandomNumberGenerator) -> Dictionary:
	var bx: int = BOSS_COLUMNS[rng.randi_range(0, BOSS_COLUMNS.size() - 1)]
	var boss := Vector2i(bx, 0)
	var anvil := Vector2i(bx, 1)
	var rune_options: Array[Vector2i] = []
	var trial_options: Array[Vector2i] = []
	for cell in _all_cells():
		if tier_of(cell) == 1:
			if cell != START_CELL:
				rune_options.append(cell)
		elif cell != boss and cell != anvil and _manhattan(cell, boss) > 1 and _manhattan(cell, anvil) > 1:
			trial_options.append(cell)
	var rune := rune_options[rng.randi_range(0, rune_options.size() - 1)]
	var trial := trial_options[rng.randi_range(0, trial_options.size() - 1)]
	var main := {}
	for cell in _all_cells():
		if cell != boss and cell != rune and cell != trial:
			main[cell] = true

	# Spanning tree (randomized Prim): tier-1 cells first, so tier 1 is connected on its own.
	var visited: Array[Vector2i] = [START_CELL]
	var edges: Array = []
	while visited.size() < main.size():
		var frontier: Array = []
		var tier1_frontier: Array = []
		for a in visited:
			for dir in DIRECTIONS:
				var b := a + dir
				if main.has(b) and not visited.has(b):
					frontier.append([a, b])
					if tier_of(b) == 1:
						tier1_frontier.append([a, b])
		if frontier.is_empty():
			return {}
		var options := tier1_frontier if not tier1_frontier.is_empty() else frontier
		var edge: Array = options[rng.randi_range(0, options.size() - 1)]
		visited.append(edge[1])
		edges.append(edge)

	# Extra loops between main cells.
	var extras: Array = []
	for a: Vector2i in main:
		for dir in [Vector2i.RIGHT, Vector2i.DOWN]:
			var b: Vector2i = a + dir
			if main.has(b) and not _has_edge(edges, a, b):
				extras.append([a, b])
	EncounterPlanner._shuffle(extras, rng)
	for k in mini(rng.randi_range(MIN_LOOPS, MAX_LOOPS), extras.size()):
		edges.append(extras[k])
	# More than one route from tier 1 into tier 2.
	if edges.filter(func(e: Array) -> bool: return tier_of(e[0]) != tier_of(e[1])).size() < MIN_TIER_LINKS:
		return {}

	# Dead-end puzzle rooms and the boss room.
	var rune_link: Variant = _pick_neighbour(rune, main, rng, func(n: Vector2i) -> bool:
		return tier_of(n) == 1 and n != rune + Vector2i.DOWN)
	var trial_link: Variant = _pick_neighbour(trial, main, rng, func(n: Vector2i) -> bool:
		return n != trial + Vector2i.UP)
	if rune_link == null or trial_link == null:
		return {}
	edges.append([rune_link, rune])
	edges.append([trial_link, trial])
	edges.append([anvil, boss])
	return {"boss": boss, "anvil": anvil, "puzzle": rune, "survival": trial, "edges": edges}


## Room copies on their cells and the link strings of `plan`.
static func _build(plan: Dictionary, roles: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var tier1: Array = roles[1].duplicate()
	var tier2: Array = roles[2].duplicate()
	EncounterPlanner._shuffle(tier1, rng)
	EncounterPlanner._shuffle(tier2, rng)
	var rooms: Array[RoomSpec] = [_placed(roles["start"], START_CELL)]
	for cell in _all_cells():
		var spec: RoomSpec
		if cell == START_CELL:
			continue
		elif cell == plan["boss"]:
			spec = roles["boss"]
		elif cell == plan["puzzle"]:
			spec = roles["puzzle"]
		elif cell == plan["survival"]:
			spec = roles["survival"]
		elif tier_of(cell) == 1:
			spec = tier1.pop_back()
		else:
			spec = tier2.pop_back()
		rooms.append(_placed(spec, cell))
	var links := PackedStringArray()
	for edge: Array in plan["edges"]:
		links.append("%d,%d - %d,%d" % [edge[0].x, edge[0].y, edge[1].x, edge[1].y])
	return {"rooms": rooms, "links": links, "boss_cell": plan["boss"], "anvil_cell": plan["anvil"]}


## A copy of `spec` on `cell` (the authored pool is never changed).
static func _placed(spec: RoomSpec, cell: Vector2i) -> RoomSpec:
	var copy := spec.duplicate() as RoomSpec
	copy.cell = cell
	return copy


## A seeded neighbour of `cell` inside `main` that passes `allowed` (null if none).
static func _pick_neighbour(cell: Vector2i, main: Dictionary, rng: RandomNumberGenerator, allowed: Callable) -> Variant:
	var options: Array[Vector2i] = []
	for dir in DIRECTIONS:
		var n := cell + dir
		if main.has(n) and allowed.call(n):
			options.append(n)
	return null if options.is_empty() else options[rng.randi_range(0, options.size() - 1)]


static func _has_edge(edges: Array, a: Vector2i, b: Vector2i) -> bool:
	return edges.any(func(e: Array) -> bool: return (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a))


## Every grid cell, row by row (y, then x).
static func _all_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in SIZE:
		for x in SIZE:
			cells.append(Vector2i(x, y))
	return cells


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
