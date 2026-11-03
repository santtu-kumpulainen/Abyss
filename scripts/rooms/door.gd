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

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
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
