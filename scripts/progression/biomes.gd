class_name Biomes
extends RefCounted
## Data-driven biome progression. Dungeon levels are grouped into biomes: the
## biome changes every `levels` levels (BIOMES entry, default `default_levels`)
## and the list repeats after its last entry, so the run is endless. The biome
## depends only on the dungeon level, never on the Difficulty tier.
##
## A biome can override, using existing content only:
##   theme      - RoomTheme path applied to every non-treasure room's visuals.
##   room_map   - room scene path -> replacement scene path (room pool).
##   enemy_map  - enemy scene path -> replacement scene path (enemy pool).
##   relics     - RunState.RELICS ids offered after the boss (empty = all).
## Add a biome by appending an entry; nothing else needs to change.

## Levels per biome unless the entry sets "levels". Keep within 3-5.
static var default_levels := 3

const BIOMES: Array[Dictionary] = [
	{
		"id": &"dungeon", "name": "The Dungeon",
		"theme": "", "room_map": {}, "enemy_map": {}, "relics": [],
	},
	{
		"id": &"caverns", "name": "Cavern Depths",
		"theme": "res://scenes/rooms/themes/cave_theme.tres", "room_map": {},
		"enemy_map": {
			"res://scenes/enemies/giant_goblin.tscn": "res://scenes/enemies/blood_monster.tscn",
			"res://scenes/enemies/demon_caster.tscn": "res://scenes/enemies/water_caster.tscn",
		},
		"relics": [],
	},
]


static func levels_in(index: int) -> int:
	return maxi(int(BIOMES[index].get("levels", default_levels)), 1)


## Index into BIOMES for dungeon `level` (1-based), repeating after the last.
static func index_for_level(level: int) -> int:
	var remaining := maxi(level, 1) - 1
	var i := 0
	while true:
		var span := levels_in(i % BIOMES.size())
		if remaining < span:
			return i % BIOMES.size()
		remaining -= span
		i += 1
	return 0


static func for_level(level: int) -> Dictionary:
	return BIOMES[index_for_level(level)]


static func biome_name(level: int) -> String:
	return for_level(level)["name"]


static func biome_id(level: int) -> StringName:
	return for_level(level)["id"]


## True if `level` is the first level of a biome different from the previous level's.
static func is_transition(level: int) -> bool:
	return level > 1 and index_for_level(level) != index_for_level(level - 1)


static func theme_for(level: int) -> RoomTheme:
	var path: String = for_level(level)["theme"]
	return load(path) as RoomTheme if not path.is_empty() else null


## `scene` or its replacement in `level`'s biome (`key` = "room_map" or "enemy_map").
static func map_scene(scene: PackedScene, level: int, key: String) -> PackedScene:
	var mapping: Dictionary = for_level(level)[key]
	var replacement = mapping.get(scene.resource_path, "")
	return load(replacement) as PackedScene if replacement is String and not replacement.is_empty() else scene


## Relic ids offered after the boss on `level`.
static func relic_pool(level: int) -> Array[StringName]:
	var allowed: Array = for_level(level)["relics"]
	var result: Array[StringName] = []
	for id: StringName in RunState.RELICS:
		if allowed.is_empty() or allowed.has(id):
			result.append(id)
	return result
