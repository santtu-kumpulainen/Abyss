@tool
class_name RoomVisuals
extends Node2D
## Draws a room's floor and walls from a RoomTheme. Walls are drawn over the
## RectangleShape2D colliders of the StaticBody2D children of `walls`, so the
## art always matches the collision. Tile variations are picked from a fixed
## seed, so a room looks the same every time it loads.

@export var theme: RoomTheme:
	set(value):
		theme = value
		queue_redraw()
## Floor area in local pixels (the whole room, including door gaps).
@export var floor_rect := Rect2(0, 0, 1152, 648):
	set(value):
		floor_rect = value
		queue_redraw()
## Node whose StaticBody2D children are the room walls.
@export var walls: Node2D:
	set(value):
		walls = value
		queue_redraw()
@export var variation_seed: int = 1:
	set(value):
		variation_seed = value
		queue_redraw()


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	if theme == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed
	_fill(theme.floor_texture, theme.floor_regions, floor_rect,
			theme.floor_variation_chance, theme.floor_tint, rng)
	_scatter_details(rng)
	var wall_rects := get_wall_rects()
	for rect in wall_rects:
		draw_rect(rect.grow(theme.wall_shadow_width), theme.wall_shadow)
	for rect in wall_rects:
		_fill(theme.wall_texture, theme.wall_regions, rect,
				theme.wall_variation_chance, theme.wall_tint, rng)


## Wall collider rectangles in this node's local space.
func get_wall_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if walls == null:
		return rects
	for body in walls.get_children():
		if not body is StaticBody2D:
			continue
		for shape_node in body.get_children():
			var collision := shape_node as CollisionShape2D
			if collision == null or not collision.shape is RectangleShape2D:
				continue
			var size: Vector2 = collision.shape.size
			var center: Vector2 = get_global_transform().affine_inverse() * collision.global_position
			rects.append(Rect2(center - size / 2.0, size))
	return rects


## Tiles `rect` with `regions`, clipping the last row/column to the rect.
func _fill(texture: Texture2D, regions: Array[Rect2], rect: Rect2, chance: float,
		tint: Color, rng: RandomNumberGenerator) -> void:
	if texture == null or regions.is_empty():
		return
	var step := regions[0].size * theme.pixel_scale
	var y := rect.position.y
	while y < rect.end.y:
		var x := rect.position.x
		while x < rect.end.x:
			var region := regions[0]
			if regions.size() > 1 and rng.randf() < chance:
				region = regions[rng.randi_range(1, regions.size() - 1)]
			var cell := Rect2(x, y, minf(step.x, rect.end.x - x), minf(step.y, rect.end.y - y))
			var source := Rect2(region.position, cell.size / theme.pixel_scale)
			draw_texture_rect_region(texture, cell, source, tint)
			x += step.x
		y += step.y


func _scatter_details(rng: RandomNumberGenerator) -> void:
	if theme.detail_texture == null or theme.detail_regions.is_empty() or theme.detail_chance <= 0.0:
		return
	var step := theme.floor_regions[0].size * theme.pixel_scale if not theme.floor_regions.is_empty() \
			else Vector2(32, 32)
	var y := floor_rect.position.y
	while y < floor_rect.end.y:
		var x := floor_rect.position.x
		while x < floor_rect.end.x:
			if rng.randf() < theme.detail_chance:
				var region := theme.detail_regions[rng.randi_range(0, theme.detail_regions.size() - 1)]
				var size := region.size * theme.pixel_scale
				var cell := Rect2(Vector2(x, y), size)
				if floor_rect.encloses(cell):
					draw_texture_rect_region(theme.detail_texture, cell, region, theme.detail_tint)
			x += step.x
		y += step.y
