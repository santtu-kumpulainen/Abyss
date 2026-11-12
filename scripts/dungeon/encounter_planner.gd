class_name EncounterPlanner
extends RefCounted
## Deterministic, per-level encounter variation (Issue #43). For one dungeon
## level, plan() turns each combat room's authored RoomSpec.enemies into a
## varied line-up:
## - up to MAX_SWAPS_PER_ROOM enemies are replaced by another member of their
##   SWAP_GROUPS group (every member of a group grants the same XP), and
## - the line-up order is shuffled, so enemy types move between the room's
##   authored SpawnPoints markers (extra enemies still use the later, door-safe
##   markers, see Room.add_extra_enemies()).
## Enemy count and per-room XP never change, so MageLevels.PRE_BOSS_BASE_XP and
## the level pacing hold for every seed. Boss and treasure rooms keep their
## authored line-ups. Room geometry, links and gates are not touched.
## Everything is derived from one integer seed (level_seed()), and each room is
## planned from its own sub-seed, so a seed always reproduces the same run.
## Biome enemy mapping (Biomes.map_scene) is applied by the Dungeon afterwards.

## Interchangeable enemy scenes. Every scene in a group must grant the same
## xp_reward (a test checks this); a scene belongs to at most one group.
const SWAP_GROUPS := [
	["res://scenes/enemies/demon.tscn", "res://scenes/enemies/demon_caster.tscn"],
]
## Most enemies replaced in one room (keeps the authored room's character).
const MAX_SWAPS_PER_ROOM := 2
## Ancient Seal sources per level, exactly (RunState.SEALS_REQUIRED + 1), so the
## player can always skip one (Issue #45: both puzzle rooms + 2 miniboss rooms).
const SEAL_SOURCES := 4

## Scene path -> [xp_reward, currency_reward] of a fresh instance.
static var _reward_cache := {}


## Seed of dungeon level `dungeon_level` in the run seeded with `run_seed`.
static func level_seed(run_seed: int, dungeon_level: int) -> int:
	return hash([run_seed, dungeon_level])


## Room index -> planned line-up (Array[PackedScene]) for every room of `rooms`
## with authored enemies. A line-up whose XP would differ from the authored one
## (a misconfigured group) falls back to the authored line-up.
static func plan(rooms: Array[RoomSpec], seed_value: int) -> Dictionary:
	var result := {}
	for i in rooms.size():
		var spec := rooms[i]
		if spec.enemies.is_empty():
			continue
		var authored: Array[PackedScene] = spec.enemies.duplicate()
		if spec.is_boss or spec.is_treasure():
			result[i] = authored
			continue
		var lineup := vary_lineup(authored, hash([seed_value, i]))
		if lineup_xp(lineup) != lineup_xp(authored):
			push_error("EncounterPlanner: room %d line-up changed its XP; using the authored line-up" % i)
			lineup = authored
		result[i] = lineup
	return result


## Picks `count` seal rooms from `candidates` (room indexes into `rooms`),
## preferring rooms that are not orthogonal neighbours of an earlier pick.
## Deterministic for `seed_value`; returns fewer only if there are too few candidates.
static func pick_seal_rooms(rooms: Array[RoomSpec], candidates: Array[int], count: int, seed_value: int) -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "seal_rooms"])
	var order: Array = candidates.duplicate()
	_shuffle(order, rng)
	var picked: Array[int] = []
	# First pass: spread out (no neighbouring picks); second pass fills up if needed.
	for spread in [true, false]:
		for index: int in order:
			if picked.size() >= count:
				return picked
			if picked.has(index):
				continue
			if spread and picked.any(func(p: int) -> bool:
					return absi(rooms[p].cell.x - rooms[index].cell.x) + absi(rooms[p].cell.y - rooms[index].cell.y) == 1):
				continue
			picked.append(index)
	return picked


## Fixed miniboss room composition per dungeon level (Issue #51 Stage 2c):
## [single, double, triple] rooms on levels 1, 2, ...; the last entry repeats
## for every later level. Not randomized.
const MINIBOSS_ROOM_COMPOSITION: Array = [
	[4, 0, 0],  # L1: 4 rooms, 4 minibosses
	[4, 1, 0],  # L2: 5 rooms, 6 minibosses
	[4, 2, 0],  # L3: 6 rooms, 8 minibosses
	[4, 2, 1],  # L4: 7 rooms, 11 minibosses
	[4, 3, 1],  # L5: 8 rooms, 13 minibosses
	[4, 2, 2],  # L6+: 8 rooms, 14 minibosses
]
## Most miniboss rooms (single + double + triple) a level may plan.
const MAX_MINIBOSS_ROOMS := 8
## Most double + triple rooms on one level.
const MAX_GROUP_ROOMS := 4
## Most minibosses in one room.
const MAX_MINIBOSSES_PER_ROOM := 3


## [single, double, triple] miniboss rooms on dungeon level `dungeon_level`.
static func miniboss_composition(dungeon_level: int) -> Array:
	var level := clampi(dungeon_level, 1, MINIBOSS_ROOM_COMPOSITION.size())
	return (MINIBOSS_ROOM_COMPOSITION[level - 1] as Array).duplicate()


## Single (one-miniboss) rooms on dungeon level `dungeon_level` (fixed: 4 on
## every level). `_seed_value` is kept for callers; the composition is not seeded.
static func single_miniboss_room_count(dungeon_level: int, _seed_value: int = 0) -> int:
	return miniboss_composition(dungeon_level)[0]


## Double-miniboss rooms on dungeon level `dungeon_level` (0 / 1 / 2 / 2 / 3 / 2...).
static func double_miniboss_room_count(dungeon_level: int) -> int:
	return miniboss_composition(dungeon_level)[1]


## Triple-miniboss rooms on dungeon level `dungeon_level` (none before level 4).
static func triple_miniboss_room_count(dungeon_level: int) -> int:
	return miniboss_composition(dungeon_level)[2]


## Miniboss rooms (single + double + triple) on dungeon level `dungeon_level`:
## 4 / 5 / 6 / 7, then 8 from level 5.
static func miniboss_room_count(dungeon_level: int, _seed_value: int = 0) -> int:
	var c := miniboss_composition(dungeon_level)
	return c[0] + c[1] + c[2]


## Miniboss types drawn on dungeon level `dungeon_level` (a double room draws
## two, a triple room three): 4 / 6 / 8 / 11 / 13, then 14.
static func miniboss_draws(dungeon_level: int, _seed_value: int = 0) -> int:
	var c := miniboss_composition(dungeon_level)
	return c[0] + 2 * c[1] + 3 * c[2]


## Shuffle bag of miniboss types for a whole run: `length` indexes into a
## roster of `type_count` types. Every bag holds each type once in a seeded
## order; when a bag runs out a new one is shuffled, and if it would start with
## the type drawn last, that type is swapped to a random later slot. So no type
## repeats before all types have appeared, two consecutive draws always differ
## (with 2+ types) and with 2 types the draws strictly alternate. The first
## type comes from the seed, so no type is favoured.
static func miniboss_bag(type_count: int, length: int, seed_value: int) -> Array[int]:
	var draws: Array[int] = []
	if type_count <= 0:
		return draws
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "miniboss_bag"])
	while draws.size() < length:
		var bag: Array = range(type_count)
		_shuffle(bag, rng)
		if type_count > 1 and not draws.is_empty() and bag[0] == draws.back():
			var j := rng.randi_range(1, type_count - 1)
			bag[0] = bag[j]
			bag[j] = draws.back()
		for t: int in bag:
			draws.append(t)
	draws.resize(length)
	return draws


## Index of the first shuffle-bag draw of dungeon level `dungeon_level` in run
## `run_seed`: the draws of levels 1 .. dungeon_level - 1 come first, so the bag
## continues across levels and every level is reproducible from the run seed.
static func miniboss_bag_offset(run_seed: int, dungeon_level: int) -> int:
	var offset := 0
	for level in range(1, maxi(dungeon_level, 1)):
		offset += miniboss_draws(level, level_seed(run_seed, level))
	return offset


## The `count` rooms of `miniboss_rooms` that hold an Ancient Seal (seeded
## choice, returned in `miniboss_rooms` order; all of them if there are fewer).
static func pick_seal_minibosses(miniboss_rooms: Array[int], count: int, seed_value: int) -> Array[int]:
	return _pick_subset(miniboss_rooms, count, hash([seed_value, "seal_minibosses"]))


## The `count` rooms of `miniboss_rooms` that get two minibosses (seeded,
## independent of the seal choice; returned in `miniboss_rooms` order). Rooms in
## `exclude` (the triple rooms) are never picked.
static func pick_double_minibosses(miniboss_rooms: Array[int], count: int, seed_value: int,
		exclude: Array[int] = []) -> Array[int]:
	var free: Array[int] = miniboss_rooms.filter(func(i: int) -> bool: return not exclude.has(i))
	return _pick_subset(free, count, hash([seed_value, "double_minibosses"]))


## The `count` rooms of `miniboss_rooms` that get three minibosses (seeded,
## independent of the seal choice; returned in `miniboss_rooms` order).
static func pick_triple_minibosses(miniboss_rooms: Array[int], count: int, seed_value: int) -> Array[int]:
	return _pick_subset(miniboss_rooms, count, hash([seed_value, "triple_minibosses"]))


## `total` split into `parts` whole shares that add up to exactly `total`
## (the first shares take the remainder), e.g. 9 / 2 -> [5, 4].
static func split_reward(total: int, parts: int) -> Array[int]:
	var shares: Array[int] = []
	parts = maxi(parts, 1)
	for k in parts:
		shares.append(total / parts + (1 if k < total % parts else 0))
	return shares


## A seeded `count`-element subset of `values`, in `values` order.
static func _pick_subset(values: Array[int], count: int, seed_value: int) -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var order: Array = values.duplicate()
	_shuffle(order, rng)
	var chosen := order.slice(0, count)
	var result: Array[int] = []
	for value in values:
		if chosen.has(value):
			result.append(value)
	return result


## One of `points`, chosen from `seed_value` (Vector2.INF if there are none).
static func pick_point(points: PackedVector2Array, seed_value: int) -> Vector2:
	if points.is_empty():
		return Vector2.INF
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "point"])
	return points[rng.randi_range(0, points.size() - 1)]


## `authored` with up to MAX_SWAPS_PER_ROOM equal-XP swaps, then shuffled.
static func vary_lineup(authored: Array[PackedScene], seed_value: int) -> Array[PackedScene]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lineup: Array[PackedScene] = authored.duplicate()
	var swappable: Array = []
	for i in lineup.size():
		if swap_group(lineup[i]).size() > 1:
			swappable.append(i)
	_shuffle(swappable, rng)
	var swaps := rng.randi_range(0, mini(MAX_SWAPS_PER_ROOM, swappable.size()))
	for k in swaps:
		var i: int = swappable[k]
		var others := swap_group(lineup[i]).filter(func(path: String) -> bool:
			return path != lineup[i].resource_path)
		lineup[i] = load(others[rng.randi_range(0, others.size() - 1)]) as PackedScene
	_shuffle(lineup, rng)
	return lineup


## The SWAP_GROUPS group containing `scene` (empty if none).
static func swap_group(scene: PackedScene) -> Array:
	for group: Array in SWAP_GROUPS:
		if group.has(scene.resource_path):
			return group
	return []


## XP granted by one enemy of `scene` (unscaled Enemy.xp_reward).
static func scene_xp(scene: PackedScene) -> int:
	return _rewards(scene)[0]


## Gold granted by one enemy of `scene` (unscaled Enemy.currency_reward).
static func scene_gold(scene: PackedScene) -> int:
	return _rewards(scene)[1]


static func _rewards(scene: PackedScene) -> Array:
	var path := scene.resource_path
	if not _reward_cache.has(path):
		var enemy := scene.instantiate() as Enemy
		_reward_cache[path] = [enemy.xp_reward, enemy.currency_reward] if enemy else [0, 0]
		if enemy:
			enemy.free()
	return _reward_cache[path]


## Total unscaled XP of a line-up.
static func lineup_xp(lineup: Array[PackedScene]) -> int:
	var total := 0
	for scene in lineup:
		total += scene_xp(scene)
	return total


## Seeded order of the rune puzzle: a permutation of `base` (same runes).
static func rune_order(base: PackedStringArray, seed_value: int) -> PackedStringArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "runes"])
	var order: Array = Array(base)
	_shuffle(order, rng)
	return PackedStringArray(order)


## Survival trial waves varied per wave: `wave_enemies` is split by
## `wave_sizes` and each wave gets vary_lineup() (equal-XP swaps, shuffled
## order) from its own sub-seed, so every wave keeps its size, XP and order in
## the trial. Entries beyond the waves are kept as they are.
static func vary_waves(wave_enemies: Array[PackedScene], wave_sizes: PackedInt32Array, seed_value: int) -> Array[PackedScene]:
	var result: Array[PackedScene] = []
	var start := 0
	for w in wave_sizes.size():
		var wave: Array[PackedScene] = []
		wave.assign(wave_enemies.slice(start, start + wave_sizes[w]))
		result.append_array(vary_lineup(wave, hash([seed_value, "wave", w])))
		start += wave_sizes[w]
	result.append_array(wave_enemies.slice(start))
	return result


## Unscaled gold of `count` extra enemies drawn from `pool` the way
## Room.add_extra_enemies() spawns them (cycling through the pool).
static func extra_enemies_gold(pool: Array[PackedScene], count: int) -> int:
	var total := 0
	if pool.is_empty():
		return total
	for k in maxi(count, 0):
		total += scene_gold(pool[k % pool.size()])
	return total


## Total unscaled gold of a line-up.
static func lineup_gold(lineup: Array[PackedScene]) -> int:
	var total := 0
	for scene in lineup:
		total += scene_gold(scene)
	return total


## Room index -> miniboss scenes (Array[PackedScene]) for each of
## `room_indexes` (in order) on dungeon level `dungeon_level` of run `run_seed`
## (Issue #51). The level takes its window of the run's shuffle bag
## (miniboss_bag(), from miniboss_bag_offset()): one draw per single room, two
## for a room in `double_rooms`, three for one in `triple_rooms` (capped at the
## roster size). The groups (largest first, then room order) take the earliest
## draws of the window whose types are not in the group yet, so a group never
## holds a type twice even across a bag boundary; the single rooms then take the
## remaining draws in order. Draws are only reordered inside the level's window,
## never dropped or duplicated, so the run-wide counts stay those of the bag.
## The roster is just `scenes`, so a new miniboss type needs no planner change.
static func assign_minibosses(room_indexes: Array[int], double_rooms: Array[int], scenes: Array[PackedScene],
		run_seed: int, dungeon_level: int, triple_rooms: Array[int] = []) -> Dictionary:
	var result := {}
	if scenes.is_empty():
		return result
	var sizes := {}
	var needed := 0
	for index in room_indexes:
		var size := 3 if triple_rooms.has(index) else (2 if double_rooms.has(index) else 1)
		size = mini(size, mini(scenes.size(), MAX_MINIBOSSES_PER_ROOM))
		sizes[index] = size
		needed += size
	var offset := miniboss_bag_offset(run_seed, dungeon_level)
	var window: Array = miniboss_bag(scenes.size(), offset + needed, run_seed).slice(offset)
	var groups: Array[int] = room_indexes.filter(func(i: int) -> bool: return sizes[i] > 1)
	groups.sort_custom(func(a: int, b: int) -> bool:
		return sizes[a] > sizes[b] if sizes[a] != sizes[b] else room_indexes.find(a) < room_indexes.find(b))
	var picks := {}
	for index in groups:
		var types: Array[int] = []
		var k := 0
		while types.size() < sizes[index] and k < window.size():
			if not types.has(window[k]):
				types.append(window[k])
				window.remove_at(k)
			else:
				k += 1
		picks[index] = types
	for index in room_indexes:
		if sizes[index] == 1 and not window.is_empty():
			var one: Array[int] = [window.pop_front()]
			picks[index] = one
	for index in room_indexes:
		var picked: Array[PackedScene] = []
		for t: int in picks.get(index, []):
			picked.append(scenes[t])
		result[index] = picked
	return result


## Room index -> `per_room` reward ids from `pool` for each of `room_indexes`.
## Ids are dealt from a seeded order of the pool, so rooms get different ids
## while the pool lasts (then it wraps around).
static func assign_rewards(room_indexes: Array[int], pool: Array[StringName], per_room: int, seed_value: int) -> Dictionary:
	var result := {}
	if pool.is_empty():
		return result
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "rewards"])
	var order: Array = pool.duplicate()
	_shuffle(order, rng)
	var next := 0
	for index in room_indexes:
		var ids: Array[StringName] = []
		for k in mini(per_room, pool.size()):
			ids.append(order[next % order.size()])
			next += 1
		result[index] = ids
	return result


## Fisher-Yates shuffle driven by `rng` (Array.shuffle() uses the global RNG).
static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = values[i]
		values[i] = values[j]
		values[j] = tmp
