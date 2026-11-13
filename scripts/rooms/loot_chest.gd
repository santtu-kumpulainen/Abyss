class_name LootChest
extends Interactable
## Random loot chest (Issue #58): the Dungeon places 1-4 per run, spread over
## the first dungeon levels, in seeded combat rooms (Dungeon.loot_chest_rooms()). Locked until its Room is
## cleared, then "interact" (E) opens it once and RunState.open_loot_chest()
## pays its gold (once per level, even across revisits). An opened chest stays
## dimmed. Inert until the Dungeon assigns `run_state`.

## Emitted once when the chest is opened, with the gold it paid.
signal opened(gold: int)

## Unique per dungeon level (the Dungeon uses the room cell).
@export var chest_id: StringName

var run_state: RunState:
	set(value):
		run_state = value
		if is_node_ready():
			refresh()

var _room: Room
var _sprite: ChestSprite


func _ready() -> void:
	_sprite = ChestSprite.new()
	_sprite.name = &"Sprite"
	_sprite.cell = ChestSprite.LOOT_CELL
	add_child(_sprite)
	super._ready()
	_room = find_room()
	if _room:
		_room.state_changed.connect(func(_state: Room.State) -> void: refresh())


## True once its Room is cleared (or it has no Room).
func is_unlocked() -> bool:
	return _room == null or _room.state == Room.State.CLEARED


func is_opened() -> bool:
	return run_state != null and run_state.is_loot_chest_opened(chest_id)


func can_interact() -> bool:
	return run_state != null and not chest_id.is_empty() and is_unlocked() and not is_opened()


## Opens the chest. Returns false if it is locked, already opened or unbound.
func interact() -> bool:
	if not can_interact():
		return false
	var gold := run_state.open_loot_chest(chest_id)
	if gold < 0:
		return false
	refresh()
	AudioManager.sfx(self, &"chest_open")
	_pop()
	opened.emit(gold)
	interacted.emit()
	return true


func prompt_text() -> String:
	if run_state == null:
		return ""
	if is_opened():
		return "Empty chest"
	if not is_unlocked():
		return "Locked - clear the room"
	return "[E] Open chest"


func refresh() -> void:
	if _sprite:
		_sprite.opened = is_opened()
	super.refresh()


func _draw() -> void:
	# Flat elliptical shadow under the chest's base.
	draw_set_transform(Vector2(0, -2), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 26.0, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)
	if is_unlocked() and not is_opened():
		draw_circle(Vector2(0, -16), 32.0, Color(1.0, 0.8, 0.35, 0.16))


## Short squash-and-stretch so opening reads clearly.
func _pop() -> void:
	if _sprite == null or not is_inside_tree():
		return
	var base := _sprite.scale
	var tween := create_tween()
	tween.tween_property(_sprite, ^"scale", base * Vector2(1.2, 0.85), 0.07)
	tween.tween_property(_sprite, ^"scale", base * Vector2(0.9, 1.15), 0.08)
	tween.tween_property(_sprite, ^"scale", base, 0.1)
