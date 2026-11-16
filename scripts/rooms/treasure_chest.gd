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
var _sprite: ChestSprite
## Draws the seal chains above the sprite (the node's own _draw is beneath its children).
var _chains: Node2D


func _ready() -> void:
	_sprite = ChestSprite.new()
	_sprite.name = &"Sprite"
	_sprite.cell = ChestSprite.TREASURE_CELL
	add_child(_sprite)
	_chains = Node2D.new()
	_chains.name = &"Chains"
	_chains.draw.connect(_draw_chains)
	add_child(_chains)
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
	AudioManager.sfx(self, &"chest_open")
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


func refresh() -> void:
	if _sprite:
		_sprite.opened = is_claimed()
		# A sealed chest looks dull until its challenge is done.
		_sprite.self_modulate = Color(0.7, 0.7, 0.75) if not is_unlocked() else Color.WHITE
	if _chains:
		_chains.queue_redraw()
	super.refresh()


## Shadow and the "ready to open" glow (the chest itself is the ChestSprite).
func _draw() -> void:
	draw_circle(Vector2(0, 2), 26.0, Color(0, 0, 0, 0.3))
	if is_unlocked() and not is_claimed():
		draw_circle(Vector2(0, -14), 34.0, Color(1.0, 0.8, 0.35, 0.18))


func _draw_chains() -> void:
	if is_unlocked() or is_claimed():
		return
	var chain := Color(0.7, 0.72, 0.78)
	_chains.draw_line(Vector2(-24, -34), Vector2(24, -2), chain, 3.0)
	_chains.draw_line(Vector2(24, -34), Vector2(-24, -2), chain, 3.0)
