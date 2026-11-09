class_name DungeonMap
extends Control
## Small minimap in the bottom-left corner. Shows visited rooms (current room
## highlighted, cleared rooms dimmed), and from each visited room its door
## links: rooms behind unexplored doors appear as outlines; gold outlines and
## links need a higher Mage level (red for the boss room). Known treasure
## rooms carry a diamond marker: orange for the survival trial, violet for
## the rune puzzle (dimmed once completed). Ancient Seal rooms are not marked
## (Issue #45): the player finds the seals by exploring; RunHud shows the count.

@export var cell_size: float = 16.0
@export var gap: float = 6.0
@export var margin: float = 16.0
@export var padding: float = 6.0
@export var background_color := Color(0.0, 0.0, 0.0, 0.55)
@export var current_color := Color(1.0, 0.9, 0.55, 1.0)
@export var cleared_color := Color(0.45, 0.5, 0.62, 1.0)
@export var uncleared_color := Color(0.75, 0.3, 0.3, 1.0)
@export var unexplored_color := Color(0.85, 0.85, 0.9, 0.9)
@export var locked_color := Color(0.85, 0.65, 0.2, 1.0)
@export var boss_color := Color(0.9, 0.2, 0.25, 1.0)
@export var survival_color := Color(1.0, 0.55, 0.15, 1.0)
@export var puzzle_color := Color(0.72, 0.45, 1.0, 1.0)

var _dungeon: Dungeon
var _origin_cell := Vector2i.ZERO
var _grid_size := Vector2i.ONE


func set_dungeon(dungeon: Dungeon) -> void:
	_dungeon = dungeon
	var min_cell := Vector2i(1 << 20, 1 << 20)
	var max_cell := -min_cell
	for spec in dungeon.rooms:
		min_cell = min_cell.min(spec.cell)
		max_cell = max_cell.max(spec.cell)
	_origin_cell = min_cell
	_grid_size = max_cell - min_cell + Vector2i.ONE
	dungeon.map_changed.connect(queue_redraw)
	dungeon.run_state.changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	if _dungeon == null:
		return
	var pitch := cell_size + gap
	var map_size := Vector2(_grid_size) * pitch - Vector2(gap, gap) + Vector2.ONE * padding * 2.0
	var top_left := Vector2(margin, size.y - margin - map_size.y)
	draw_rect(Rect2(top_left, map_size), background_color)
	var origin := top_left + Vector2.ONE * padding

	var known := {}
	for i in _dungeon.rooms.size():
		if not _dungeon.is_visited(i):
			continue
		known[i] = true
		for j: int in _dungeon.get_neighbours(i):
			known[j] = true
			# Each link drawn once from the lower index (or from the only visited end).
			if _dungeon.is_visited(j) and j < i:
				continue
			var a := _cell_center(origin, i)
			var b := _cell_center(origin, j)
			var dir := (b - a).normalized()
			var color := unexplored_color if _dungeon.can_enter(j) else _gate_color(j)
			draw_line(a + dir * cell_size / 2.0, b - dir * cell_size / 2.0, color, 3.0)

	for i: int in known:
		var rect := Rect2(_cell_center(origin, i) - Vector2.ONE * cell_size / 2.0, Vector2.ONE * cell_size)
		if i == _dungeon.current_index:
			draw_rect(rect, current_color)
		elif _dungeon.is_cleared(i):
			draw_rect(rect, cleared_color)
		elif _dungeon.is_visited(i):
			draw_rect(rect, uncleared_color)
		else:
			var color := unexplored_color if _dungeon.can_enter(i) else _gate_color(i)
			draw_rect(rect, color, false, 2.0)
		if _dungeon.rooms[i].is_boss:
			draw_rect(rect.grow(-cell_size * 0.3), boss_color)
		var marker := marker_color(i)
		if marker.a > 0.0:
			var c := rect.get_center()
			var r := cell_size * 0.32
			var diamond := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
			draw_colored_polygon(diamond, marker)
			draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color.BLACK, 1.0)


## Treasure-room marker colour for room `index` (transparent for other rooms).
func marker_color(index: int) -> Color:
	var color := Color.TRANSPARENT
	match _dungeon.rooms[index].treasure:
		RoomSpec.Treasure.SURVIVAL:
			color = survival_color
		RoomSpec.Treasure.PUZZLE:
			color = puzzle_color
	return color.darkened(0.45) if color.a > 0.0 and _dungeon.is_cleared(index) else color


func _gate_color(index: int) -> Color:
	return boss_color if _dungeon.rooms[index].is_boss else locked_color


func _cell_center(origin: Vector2, index: int) -> Vector2:
	var cell := _dungeon.rooms[index].cell - _origin_cell
	return origin + Vector2(cell) * (cell_size + gap) + Vector2.ONE * cell_size / 2.0
