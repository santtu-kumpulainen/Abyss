@tool
class_name Door
extends StaticBody2D
## Room exit. Locked, sealed or level-locked: solid wall (world layer) drawn
## as an iron portcullis (gold with `lock_label` when level-locked). Otherwise: collision disabled so characters can pass; only a
## faint threshold is drawn so the floor shows through.

@export var locked: bool = false:
	set(value):
		locked = value
		if is_node_ready():
			_apply()

## A sealed door leads nowhere (no connected room): it stays shut even while
## unlocked. Room only toggles `locked`, so sealing survives room clears.
@export var sealed: bool = false:
	set(value):
		sealed = value
		if is_node_ready():
			_apply()

## Leads to a room the Mage's level is too low for (set by the Dungeon).
## Independent of `locked`, so room clears don't open it.
@export var level_locked: bool = false:
	set(value):
		level_locked = value
		if is_node_ready():
			_apply()

## Shown on the door while level-locked, e.g. "Lv 2".
@export var lock_label: String = "":
	set(value):
		lock_label = value
		queue_redraw()

## Size of the doorway in local pixels (matches the collision shape).
@export var size := Vector2(96, 32):
	set(value):
		size = value
		queue_redraw()
@export var bar_color := Color(0.42, 0.44, 0.52, 1.0)
@export var bar_highlight := Color(0.72, 0.74, 0.82, 1.0)
@export var backdrop_color := Color(0.05, 0.04, 0.07, 0.9)
@export var open_color := Color(0.0, 0.0, 0.0, 0.25)
@export var level_bar_color := Color(0.72, 0.56, 0.2, 1.0)
@export var level_bar_highlight := Color(1.0, 0.86, 0.45, 1.0)
@export_group("Open glow")
## Open doors only (Issue #63): a faint light spilling a few pixels onto the
## floor inside the doorway, so open exits read at a glance. Drawn in stepped
## bands (pixel-art look), static, under characters (the Doors node sorts first).
@export var glow_color := Color(1.0, 0.84, 0.55, 1.0)
## Alpha of the brightest band (0 = no glow).
@export_range(0.0, 1.0) var glow_strength: float = 0.18
## Bands and the depth of each, in pixels, from the doorway into the room.
@export var glow_bands: int = 3
@export var glow_band_depth: float = 4.0
@export_group("")

## Local y direction pointing into the room (+1 or -1), found from the room's
## floor centre when the door is ready.
var _inward := 1.0

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_inward = _find_inward()
	_apply()


## True when characters can walk through.
func is_open() -> bool:
	return not locked and not sealed and not level_locked


func _apply() -> void:
	# Deferred: lock/unlock can happen during physics callbacks.
	_shape.set_deferred(&"disabled", is_open())
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(-size / 2.0, size)
	if is_open():
		draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, 3.0), open_color)
		draw_rect(Rect2(rect.position.x, rect.end.y - 3.0, rect.size.x, 3.0), open_color)
		_draw_glow(rect)
		return
	draw_rect(rect, backdrop_color)
	var gated := level_locked and not sealed
	var bar := level_bar_color if gated else bar_color
	var highlight := level_bar_highlight if gated else bar_highlight
	# Vertical bars with a highlight, plus two cross bars.
	var bar_width := 4.0
	var x := rect.position.x + 4.0
	while x + bar_width <= rect.end.x - 2.0:
		draw_rect(Rect2(x, rect.position.y, bar_width, rect.size.y), bar)
		draw_rect(Rect2(x, rect.position.y, 1.0, rect.size.y), highlight)
		x += 12.0
	for t in [0.3, 0.7]:
		var y: float = rect.position.y + rect.size.y * t - 1.5
		draw_rect(Rect2(rect.position.x, y, rect.size.x, 3.0), bar)
		draw_rect(Rect2(rect.position.x, y, rect.size.x, 1.0), highlight)
	if gated and not lock_label.is_empty():
		_draw_label()


## Open-door glow: bands narrowing and fading from the room-side edge of the
## doorway inwards, plus a very faint tint over the doorway itself.
func _draw_glow(rect: Rect2) -> void:
	if glow_strength <= 0.0 or glow_bands <= 0:
		return
	draw_rect(rect.grow_individual(-4.0, -3.0, -4.0, -3.0), Color(glow_color, glow_strength * 0.35))
	var edge := rect.end.y if _inward > 0.0 else rect.position.y
	for k in glow_bands:
		var inset := minf(6.0 + 8.0 * k, rect.size.x / 2.0 - 2.0)
		var alpha := glow_strength * (1.0 - float(k) / glow_bands)
		var y := edge + (glow_band_depth * k if _inward > 0.0 else -glow_band_depth * (k + 1))
		draw_rect(Rect2(rect.position.x + inset, y, rect.size.x - 2.0 * inset, glow_band_depth), Color(glow_color, alpha))


## True if the glow is drawn (open door with a visible glow strength).
func is_glowing() -> bool:
	return is_open() and glow_strength > 0.0 and glow_bands > 0


## Local y sign pointing from the door into its Room (doors sit on the walls).
func _find_inward() -> float:
	var node := get_parent()
	while node and not node is Room:
		node = node.get_parent()
	if node == null:
		return 1.0
	var visuals := node.get_node_or_null(^"Visuals") as RoomVisuals
	var center: Vector2 = (node as Node2D).to_global(visuals.floor_rect.get_center() if visuals else Vector2(576, 324))
	return 1.0 if to_local(center).y >= 0.0 else -1.0


## Draws `lock_label` upright and centred, whatever the door's rotation.
func _draw_label() -> void:
	var font := ThemeDB.fallback_font
	var font_size := 16
	draw_set_transform(Vector2.ZERO, -rotation)
	var text_size := font.get_string_size(lock_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := Vector2(-text_size.x / 2.0, font.get_ascent(font_size) - text_size.y / 2.0)
	draw_string_outline(font, pos, lock_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color.BLACK)
	draw_string(font, pos, lock_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.9, 0.55))
	draw_set_transform(Vector2.ZERO)
