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


## Miniboss rooms per dungeon level (Issue #45): 3 on levels 1-2, 4 from level 3.
static func miniboss_room_count(dungeon_level: int) -> int:
	return 3 if dungeon_level <= 2 else 4


## Double-miniboss rooms per dungeon level: none before level 5, 1 on levels
## 5-6, 2 from level 7.
static func double_miniboss_room_count(dungeon_level: int) -> int:
	if dungeon_level < 5:
		return 0
	return 1 if dungeon_level < 7 else 2


## The `count` rooms of `miniboss_rooms` that hold an Ancient Seal (seeded
## choice, returned in `miniboss_rooms` order; all of them if there are fewer).
static func pick_seal_minibosses(miniboss_rooms: Array[int], count: int, seed_value: int) -> Array[int]:
	return _pick_subset(miniboss_rooms, count, hash([seed_value, "seal_minibosses"]))


## The `count` rooms of `miniboss_rooms` that get two minibosses (seeded,
## independent of the seal choice; returned in `miniboss_rooms` order).
static func pick_double_minibosses(miniboss_rooms: Array[int], count: int, seed_value: int) -> Array[int]:
	return _pick_subset(miniboss_rooms, count, hash([seed_value, "double_minibosses"]))


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


## Total unscaled gold of a line-up.
static func lineup_gold(lineup: Array[PackedScene]) -> int:
	var total := 0
	for scene in lineup:
		total += scene_gold(scene)
	return total


## Room index -> miniboss scene for each of `room_indexes` (in order): the
## rooms take turns through a seeded order of `scenes`, so with two scenes and
## two rooms both minibosses appear.
static func assign_minibosses(room_indexes: Array[int], scenes: Array[PackedScene], seed_value: int) -> Dictionary:
	var result := {}
	if scenes.is_empty():
		return result
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "minibosses"])
	var order: Array = scenes.duplicate()
	_shuffle(order, rng)
	for k in room_indexes.size():
		result[room_indexes[k]] = order[k % order.size()]
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
