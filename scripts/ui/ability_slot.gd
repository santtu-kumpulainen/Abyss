class_name AbilitySlot
extends Control
## One square of the AbilityBar (Issue #49): the fixed Dash slot or an item
## slot. It only draws what the bar gives it (set_state(), derived from the
## Mage, RunState and HomeTeleport each refresh) and keeps no game state.
## Item slots can be dragged onto each other; the bar swaps them. Clicks on a
## slot never cast a spell (Mage.HUD_CLICK_GROUP).

enum Kind { DASH, ITEM }

const FRAME := Color(0.08, 0.08, 0.1, 0.85)
const BORDER := Color(0, 0, 0, 1)
const READY_EDGE := Color(1, 0.9, 0.55, 1)
const CAST_EDGE := Color(0.45, 0.75, 1, 1)
const TEXT := Color(1, 1, 1, 1)
const KEY_TEXT := Color(1, 0.9, 0.55, 1)
const EMPTY_TEXT := Color(1, 0.45, 0.4, 1)
const TIMER_TEXT := Color(0.6, 1, 0.6, 1)

@export var kind := Kind.ITEM
## Item slot position (0 = key 1); -1 for the Dash slot.
@export var index := -1
## Key shown in the corner.
@export var key_text := ""

var bar: AbilityBar
## Consumable id shown (item slots).
var item: StringName = &""

# Display state (set_state()).
var _quantity := 0
## The slot can be used now (bright); false = dimmed.
var _usable := true
## Dash only: false when the dash cannot be used at all (dead, run over).
var _available := true
## Remaining cooldown, 1.0 = just used .. 0.0 = ready (Dash).
var _cooldown := 0.0
var _cooldown_text := ""
## Teleport cast progress 0..1, or -1 when not casting.
var _cast := -1.0
var _timer_text := ""
var _flash := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(44, 44)
	mouse_filter = MOUSE_FILTER_STOP
	focus_mode = FOCUS_NONE
	add_to_group(Mage.HUD_CLICK_GROUP)


## Display state for the next draw (see the variables above).
func set_state(state: Dictionary) -> void:
	_quantity = state.get("quantity", 0)
	_usable = state.get("usable", true)
	_available = state.get("available", true)
	_cooldown = state.get("cooldown", 0.0)
	_cooldown_text = state.get("cooldown_text", "")
	_cast = state.get("cast", -1.0)
	_timer_text = state.get("timer", "")
	queue_redraw()


## Displayed state, for tests and the bar.
func displayed() -> Dictionary:
	return {"item": item, "quantity": _quantity, "usable": _usable, "available": _available,
			"cooldown": _cooldown, "cast": _cast, "timer": _timer_text, "key": key_text}


## Short red flash (the slot's key did nothing, e.g. an empty slot).
func flash() -> void:
	_flash = 1.0
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		_flash = v
		queue_redraw(), 1.0, 0.0, 0.3)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if kind != Kind.ITEM or bar == null or item == &"":
		return null
	if get_viewport() and get_viewport().gui_is_dragging():
		set_drag_preview(_make_preview())
	return {"ability_slot": index}


## A see-through copy of this slot, centred on the mouse while dragging.
func _make_preview() -> Control:
	var preview := AbilitySlot.new()
	preview.kind = Kind.ITEM
	preview.item = item
	preview.size = size
	preview.position = -size / 2.0
	preview.modulate.a = 0.8
	preview.set_state({"quantity": _quantity, "usable": _usable})
	var holder := Control.new()
	holder.add_child(preview)
	return holder


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return (kind == Kind.ITEM and bar != null and data is Dictionary and data.has("ability_slot")
			and bar.can_swap(int(data["ability_slot"]), index))


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	bar.swap_slots(int(data["ability_slot"]), index)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, FRAME)
	var bright := _usable and _available and _cooldown <= 0.0
	var icon_tint := Color.WHITE if bright else Color(0.55, 0.55, 0.6, 0.6)
	if kind == Kind.ITEM and _quantity <= 0:
		icon_tint = Color(0.4, 0.4, 0.45, 0.35)
	if kind == Kind.DASH and not _available:
		icon_tint = Color(0.35, 0.35, 0.4, 0.4)
	AbilityIcons.draw_icon(self, &"dash" if kind == Kind.DASH else item, rect.grow(-7), icon_tint)

	# Dash cooldown: a dark shade that shrinks from the top as it recharges.
	if kind == Kind.DASH and _cooldown > 0.0 and _available:
		draw_rect(Rect2(0, 0, size.x, size.y * _cooldown), Color(0, 0, 0, 0.6))
		_text(_cooldown_text, Vector2(0, size.y / 2.0 + 5), 13, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	# Teleport cast: blue fill rising from the bottom.
	if _cast >= 0.0:
		draw_rect(Rect2(0, size.y * (1.0 - _cast), size.x, size.y * _cast), Color(0.3, 0.6, 1, 0.45))

	var edge := BORDER
	if _cast >= 0.0:
		edge = CAST_EDGE
	elif bright and (kind == Kind.DASH or _quantity > 0):
		edge = READY_EDGE.darkened(0.35)
	draw_rect(rect, edge, false, 2.0)
	if _flash > 0.0:
		draw_rect(rect, Color(1, 0.3, 0.25, _flash), false, 3.0)

	_text(key_text, Vector2(3, 12), 11, KEY_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	if kind == Kind.ITEM:
		_text(str(_quantity), Vector2(-3, size.y - 3), 14, TEXT if _quantity > 0 else EMPTY_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		if not _timer_text.is_empty():
			_text(_timer_text, Vector2(-2, 12), 10, TIMER_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)


## Outlined text at `pos` (baseline); right/center alignment use the slot width.
func _text(text: String, pos: Vector2, font_size: int, color: Color, align: HorizontalAlignment) -> void:
	if text.is_empty():
		return
	var font := ThemeDB.fallback_font
	var width := -1.0
	var at := pos
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		width = size.x - 4.0
		at = Vector2(2.0, pos.y)
		if align == HORIZONTAL_ALIGNMENT_RIGHT:
			at.x += pos.x
	draw_string_outline(font, at, text, align, width, font_size, 4, Color.BLACK)
	draw_string(font, at, text, align, width, font_size, color)
