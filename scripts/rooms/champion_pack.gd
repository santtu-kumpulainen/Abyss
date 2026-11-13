class_name ChampionPack
extends Node2D
## Champion room rule (Issue #43): the fallback seal source when a level has
## too few miniboss rooms. Added to a Room by the Dungeon. When the encounter
## starts, the strongest enemy (highest xp_reward, first on ties) becomes the
## gold-crowned champion and wards the rest of its pack: while the champion
## lives, every other encounter enemy takes only `ward_multiplier` x damage
## (shown by blue ward rings). Killing the champion breaks the ward at once,
## so the room rewards focusing the leader through its pack. Enemies, XP and
## gold are the room's own; nothing is added.

## Emitted once when the champion dies and the ward breaks.
signal ward_broken

## Damage taken multiplier of warded pack members.
@export var ward_multiplier: float = 0.35
@export var champion_tint := Color(1.0, 0.85, 0.35)

var champion: Enemy
var warded: Array[Enemy] = []
var active := false

var _room: Room


func _ready() -> void:
	_room = get_parent() as Room
	if _room:
		_room.state_changed.connect(_on_room_state)


## True while `enemy` is protected by the ward.
func is_warded(enemy: Enemy) -> bool:
	return active and warded.has(enemy)


func _on_room_state(state: Room.State) -> void:
	if state == Room.State.COMBAT and not active and champion == null:
		_raise_ward()


func _raise_ward() -> void:
	var pack: Array[Enemy] = []
	for child in _room.get_node(^"Enemies").get_children():
		if child is Enemy and not child.is_queued_for_deletion():
			pack.append(child)
	if pack.size() < 2:
		return
	champion = pack[0]
	for e in pack:
		if e.xp_reward > champion.xp_reward:
			champion = e
	(champion.get_node(^"AnimatedSprite2D") as CanvasItem).self_modulate = champion_tint
	champion.died.connect(_break_ward)
	for e in pack:
		if e != champion:
			e.damage_taken_multiplier *= ward_multiplier
			warded.append(e)
	active = true


func _break_ward() -> void:
	if not active:
		return
	active = false
	for e in warded:
		if is_instance_valid(e):
			e.damage_taken_multiplier /= ward_multiplier
	warded.clear()
	AudioManager.sfx(self, &"champion_ward_broken")
	ward_broken.emit()


func _process(_delta: float) -> void:
	if active:
		queue_redraw()


func _draw() -> void:
	if not active:
		return
	for e in warded:
		if is_instance_valid(e):
			draw_arc(to_local(e.global_position) + Vector2(0, -26), 24.0, 0.0, TAU, 24, Color(0.45, 0.75, 1.0, 0.7), 2.0)
	if is_instance_valid(champion):
		var c := to_local(champion.global_position)
		draw_arc(c + Vector2(0, -30), 34.0, 0.0, TAU, 32, Color(champion_tint, 0.9), 3.0)
		var top := c + Vector2(0, -92)
		draw_colored_polygon(PackedVector2Array([top + Vector2(-12, 8), top + Vector2(-12, -4), top + Vector2(-6, 2),
				top + Vector2(0, -8), top + Vector2(6, 2), top + Vector2(12, -4), top + Vector2(12, 8)]), champion_tint)
