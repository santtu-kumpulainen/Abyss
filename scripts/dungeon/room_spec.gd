class_name RoomSpec
extends Resource
## One room of a Dungeon: which scene to use, where it sits on the dungeon
## grid (used for door links and the minimap), the Mage level needed to enter
## optional extra encounter enemies spawned at the room's SpawnPoints and an
## optional collectible item (a RunState.ITEMS id). Treasure rooms are optional
## side rooms: they don't count for the full clear and get a minimap marker.

enum Treasure { NONE, SURVIVAL, PUZZLE }

## Room scene (a Room). Template scenes have an empty "Enemies" node.
@export var scene: PackedScene
## Grid cell (x right, y down). Linked rooms must be orthogonal neighbours.
@export var cell: Vector2i
## Mage level needed to enter. Doors leading here stay level-locked below it.
@export var required_level: int = 1
## Marks the boss room (gate label and minimap marker).
@export var is_boss: bool = false
## Marks an optional treasure room and its kind (minimap marker).
@export var treasure: Treasure = Treasure.NONE
## Enemies added to the room's "Enemies" on first visit, one per SpawnPoints marker.
@export var enemies: Array[PackedScene] = []
## RunState.ITEMS id of a pickup placed in this room (empty = none). It appears
## once the room is cleared and can be collected once per run.
@export var item: StringName = &""
## Pickup position in room coordinates.
@export var item_position := Vector2(576, 324)


func is_treasure() -> bool:
	return treasure != Treasure.NONE
