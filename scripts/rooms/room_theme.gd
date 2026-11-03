class_name RoomTheme
extends Resource
## Visual style of a room, drawn by RoomVisuals: which tile-sheet regions
## make up the floor and walls, and how they are tinted. Regions are in source
## pixels; every region of a list should have the same size.

## Scale applied to source pixels (16 px tiles at 2.0 become 32 px).
@export var pixel_scale: float = 2.0

@export_group("Floor")
@export var floor_texture: Texture2D
## First region is the base tile; the others are random variations.
@export var floor_regions: Array[Rect2] = []
## Chance that a floor cell uses a variation instead of the base tile.
@export_range(0.0, 1.0) var floor_variation_chance: float = 0.15
@export var floor_tint := Color.WHITE

@export_group("Floor details")
## Optional decals (cracks, spots) scattered over the floor.
@export var detail_texture: Texture2D
@export var detail_regions: Array[Rect2] = []
@export_range(0.0, 1.0) var detail_chance: float = 0.0
@export var detail_tint := Color.WHITE

@export_group("Walls")
@export var wall_texture: Texture2D
## First region is the base tile; the others are random variations.
@export var wall_regions: Array[Rect2] = []
@export_range(0.0, 1.0) var wall_variation_chance: float = 0.2
@export var wall_tint := Color.WHITE
## Darkened band drawn on the floor around walls for depth.
@export var wall_shadow := Color(0.0, 0.0, 0.0, 0.35)
@export var wall_shadow_width: float = 10.0
