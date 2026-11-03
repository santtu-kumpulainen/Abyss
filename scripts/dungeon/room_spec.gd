class_name RoomSpec
extends Resource
## One room of a Dungeon: which scene to use, where it sits on the dungeon
## grid (used for door links and the minimap), the Mage level needed to enter
## and optional extra encounter enemies spawned at the room's SpawnPoints.

## Room scene (a Room). Template scenes have an empty "Enemies" node.
@export var scene: PackedScene
## Grid cell (x right, y down). Linked rooms must be orthogonal neighbours.
@export var cell: Vector2i
## Mage level needed to enter. Doors leading here stay level-locked below it.
@export var required_level: int = 1
## Marks the boss room (gate label and minimap marker).
@export var is_boss: bool = false
## Enemies added to the room's "Enemies" on first visit, one per SpawnPoints marker.
@export var enemies: Array[PackedScene] = []
