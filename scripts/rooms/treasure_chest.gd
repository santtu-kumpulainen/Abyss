class_name TreasureChest
extends Interactable
## Treasure-room chest holding RunState.TREASURES[treasure_id]. Sealed (chained)
## until its Room is cleared, then "interact" (E) opens it once and claims the
## treasure through RunState, which pays out once per run. A claimed chest
## stays open and empty on revisits. Inert until the Dungeon assigns `run_state`.

signal opened

@export var treasure_id: StringName

var run_state: RunState:
	set(value):
		run_state = value
		if is_node_ready():
			refresh()

var _room: Room


func _ready() -> void:
	super._ready()
	_room = find_room()
	if _room:
		_room.state_changed.connect(func(_state: Room.State) -> void: refresh())
	if not RunState.TREASURES.has(treasure_id):
		push_warning("TreasureChest: unknown treasure id '%s'" % treasure_id)
	refresh()


## True once its Room's challenge is complete.
func is_unlocked() -> bool:
	return _room == null or _room.state == Room.State.CLEARED


func is_claimed() -> bool:
	return run_state != null and run_state.is_treasure_claimed(treasure_id)


func can_interact() -> bool:
	return run_state != null and RunState.TREASURES.has(treasure_id) and is_unlocked() and not is_claimed()


## Opens the chest and claims its treasure. Returns false if it is still
## sealed, already claimed or not bound to a run.
func interact() -> bool:
	if not can_interact() or not run_state.claim_treasure(treasure_id):
		return false
	refresh()
	opened.emit()
	interacted.emit()
	return true


func prompt_text() -> String:
	if run_state == null:
		return ""
	if is_claimed():
		return "Empty chest"
	if not is_unlocked():
		return "Sealed - complete this room's challenge"
	return "[E] Open chest: %s" % RunState.TREASURES[treasure_id]["name"]


func _draw() -> void:
	var claimed := is_claimed()
	var unlocked := is_unlocked()
	var wood := Color(0.45, 0.27, 0.13) if unlocked else Color(0.32, 0.22, 0.15)
	var band := Color(0.95, 0.75, 0.3) if unlocked else Color(0.55, 0.5, 0.42)
	draw_circle(Vector2(0, 2), 26.0, Color(0, 0, 0, 0.3))
	if unlocked and not claimed:
		draw_circle(Vector2(0, -14), 34.0, Color(1.0, 0.8, 0.35, 0.18))
	# Body.
	draw_rect(Rect2(-22, -24, 44, 26), wood)
	draw_rect(Rect2(-22, -24, 44, 26), wood.darkened(0.4), false, 2.0)
	for x in [-16.0, 12.0]:
		draw_rect(Rect2(x, -24, 4, 26), band)
	if claimed:
		# Open lid tilted back, empty inside.
		draw_rect(Rect2(-22, -40, 44, 10), wood.lightened(0.1))
		draw_rect(Rect2(-20, -26, 40, 4), Color(0.08, 0.05, 0.03))
		return
	# Closed lid with lock.
	draw_rect(Rect2(-24, -36, 48, 12), wood.lightened(0.1))
	draw_rect(Rect2(-24, -36, 48, 12), wood.darkened(0.4), false, 2.0)
	draw_rect(Rect2(-4, -28, 8, 9), band)
	if not unlocked:
		# Chains across the chest.
		var chain := Color(0.7, 0.72, 0.78)
		draw_line(Vector2(-24, -34), Vector2(24, -2), chain, 3.0)
		draw_line(Vector2(24, -34), Vector2(-24, -2), chain, 3.0)
