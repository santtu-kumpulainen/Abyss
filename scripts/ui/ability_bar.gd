class_name AbilityBar
extends CanvasLayer
## Ability bar at the bottom centre (Issue #49): the fixed Dash slot (Space),
## three item slots (keys 1-3) and the Ancient Seal crystals. Presentation
## only: every value comes from the Mage (dash), RunState (quantities, Speed
## Potion time, seals) and HomeTeleport (cast); using a slot goes through
## Dungeon.use_item(). Keys belong to slot positions; items swap by dragging
## one slot onto another, and the order is ProgressionStore.ability_slots
## (saved in progression.cfg). While an Anvil menu is open, keys 1-3 are left
## to it. The bar fades while the Mage stands behind it.

const SLOT_ACTIONS: Array[StringName] = [&"ability_slot_1", &"ability_slot_2", &"ability_slot_3"]
## Modulate alpha while the Mage is behind the bar.
const FADED_ALPHA := 0.35

var dungeon: Dungeon
var _progression: ProgressionStore
var _was_animating := false
var _room: Room

@onready var _bar: Control = %Bar
@onready var _dash_slot: AbilitySlot = %DashSlot
@onready var _item_slots: Array[AbilitySlot] = [%Slot1, %Slot2, %Slot3]
@onready var _seals: SealCrystals = %Seals


func _ready() -> void:
	_dash_slot.bar = self
	for slot in _item_slots:
		slot.bar = self
	set_process(false)


## Binds the bar to `p_dungeon` (its Mage, RunState and HomeTeleport). Called
## once by the Dungeon; a new run reloads the scene and a new bar.
func setup(p_dungeon: Dungeon) -> void:
	dungeon = p_dungeon
	_progression = ProgressionStore.instance(get_tree())
	var mage := dungeon.mage
	mage.dash_started.connect(func(_dir: Vector2) -> void: refresh())
	mage.dash_ended.connect(refresh)
	mage.died.connect(refresh)
	mage.health.changed.connect(func(_current: float) -> void: refresh())
	mage.health.damaged.connect(func(_amount: float, _current: float) -> void: refresh())
	dungeon.run_state.changed.connect(refresh)
	dungeon.home_teleport.state_changed.connect(refresh)
	dungeon.room_changed.connect(_on_room_changed)
	dungeon.victory_started.connect(refresh)
	dungeon.level_started.connect(func(_level: int) -> void: refresh())
	_seals.run_state = dungeon.run_state
	_on_room_changed(dungeon.current_room, dungeon.current_index)
	set_process(true)


## The consumable ids in slots 1-3 (ProgressionStore.ability_slots).
func slot_order() -> Array[StringName]:
	if _progression:
		return _progression.ability_slots.duplicate()
	return ProgressionStore.default_ability_slots()


func item_in_slot(index: int) -> StringName:
	var order := slot_order()
	return order[index] if index >= 0 and index < order.size() else &""


func slot(index: int) -> AbilitySlot:
	return _item_slots[index] if index >= 0 and index < _item_slots.size() else null


func dash_slot() -> AbilitySlot:
	return _dash_slot


func seals() -> SealCrystals:
	return _seals


func can_swap(from: int, to: int) -> bool:
	return from != to and from >= 0 and to >= 0 and from < _item_slots.size() and to < _item_slots.size()


## Swaps the items of slots `from` and `to` (their keys stay with the slots)
## and saves the order. Returns false (changing nothing) for invalid slots.
func swap_slots(from: int, to: int) -> bool:
	if not can_swap(from, to) or _progression == null:
		return false
	var order := slot_order()
	var moved := order[from]
	order[from] = order[to]
	order[to] = moved
	if not _progression.set_ability_slots(order):
		return false
	refresh()
	return true


## Uses the item in slot `index` (key index + 1). Returns true if it was used
## or a teleport cast started. Does nothing while an Anvil menu is open.
func use_slot(index: int) -> bool:
	if dungeon == null or index < 0 or index >= _item_slots.size() or UpgradeStation.any_open(get_tree()):
		return false
	var id := item_in_slot(index)
	var cancelling := id == HomeTeleport.ITEM and dungeon.home_teleport.is_casting()
	var used := dungeon.use_item(id)
	if not used and not cancelling:
		_item_slots[index].flash()
	refresh()
	return used


func _unhandled_input(event: InputEvent) -> void:
	if dungeon == null or event.is_echo():
		return
	for i in SLOT_ACTIONS.size():
		if event.is_action_pressed(SLOT_ACTIONS[i]):
			# An open Anvil menu owns keys 1-3 (it buys upgrades with them).
			if UpgradeStation.any_open(get_tree()):
				return
			use_slot(i)
			get_viewport().set_input_as_handled()
			return


## Redraws every slot from the current game state.
func refresh() -> void:
	if dungeon == null or not is_node_ready():
		return
	var mage := dungeon.mage
	var cooling := not mage.dash_ready()
	var remaining := mage.dash_cooldown_remaining()
	_dash_slot.item = &"dash"
	_dash_slot.set_state({
		"available": not mage.is_dead() and mage.is_physics_processing(),
		"usable": mage.can_dash() or cooling,
		"cooldown": 1.0 - mage.dash_cooldown_ratio(),
		"cooldown_text": ("%.1f" % remaining) if cooling else "",
	})
	var run := dungeon.run_state
	var order := slot_order()
	for i in _item_slots.size():
		var id := order[i]
		var slot_node := _item_slots[i]
		slot_node.item = id
		var state := {"quantity": run.consumable_count(id), "usable": _is_usable(id)}
		if id == &"speed_potion" and run.is_speed_potion_active():
			state["timer"] = RunState.format_time(run.speed_potion_remaining)
		if id == HomeTeleport.ITEM and dungeon.home_teleport.is_busy():
			state["cast"] = dungeon.home_teleport.cast_progress()
		slot_node.set_state(state)


## True if using `id` now would do something (owned and not refused).
func _is_usable(id: StringName) -> bool:
	var run := dungeon.run_state
	if run.consumable_count(id) <= 0 or dungeon.mage.is_dead() or dungeon.victory:
		return false
	match id:
		&"health_potion":
			return dungeon.mage.health.current < dungeon.mage.health.max_health
		&"speed_potion":
			return run.can_use_speed_potion()
		HomeTeleport.ITEM:
			return dungeon.home_teleport.can_start() or dungeon.home_teleport.is_casting()
	return true


## True while something on the bar changes every frame (dash cooldown, the
## Speed Potion timer or a teleport cast); otherwise signals drive refresh().
func is_animating() -> bool:
	if dungeon == null:
		return false
	return (not dungeon.mage.dash_ready() or dungeon.run_state.is_speed_potion_active()
			or dungeon.home_teleport.is_busy())


func _process(_delta: float) -> void:
	var animating := is_animating()
	# One more refresh when it stops, so the final state (e.g. dash ready) shows.
	if animating or _was_animating:
		refresh()
	_was_animating = animating
	_update_fade()


## Fades the bar while the Mage is drawn behind it (e.g. at a bottom door).
func _update_fade() -> void:
	_bar.modulate.a = FADED_ALPHA if is_mage_behind() else 1.0


## True when the Mage's feet are at or below the bar's top edge within its
## width, i.e. the Mage is drawn behind the bar (standing above it is fine).
func is_mage_behind() -> bool:
	if dungeon == null:
		return false
	var feet := dungeon.mage.get_global_transform_with_canvas().origin
	var rect := _bar.get_global_rect()
	return feet.x > rect.position.x - 16.0 and feet.x < rect.end.x + 16.0 and feet.y > rect.position.y


func _on_room_changed(room: Room, _index: int) -> void:
	# The teleport slot is unusable during combat: follow the room's state.
	if _room and is_instance_valid(_room) and _room.state_changed.is_connected(_on_room_state_changed):
		_room.state_changed.disconnect(_on_room_state_changed)
	_room = room
	if _room:
		_room.state_changed.connect(_on_room_state_changed)
	refresh()


func _on_room_state_changed(_state: Room.State) -> void:
	refresh()
