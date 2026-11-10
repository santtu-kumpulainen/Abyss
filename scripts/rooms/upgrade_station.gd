class_name UpgradeStation
extends Node2D
## Anvil upgrade station. When the Mage (any "player" body) stands in
## "InteractArea", a prompt appears; "interact" (E) opens/closes the menu and
## "upgrade_1".."upgrade_4" (1-4) buy RunState.UPGRADES in order. Each line
## shows the cost, required level and effect; RunState blocks purchases that
## are unaffordable or level-locked. "buy_supply_1".."buy_supply_3" (5-7) buy
## RunState.CONSUMABLES in order (Issue #49), up to each inventory cap.
## Unavailable while its room is in combat. Inert until the Dungeon assigns `run_state`.

const BUY_ACTIONS: Array[StringName] = [&"upgrade_1", &"upgrade_2", &"upgrade_3", &"upgrade_4"]
const SUPPLY_ACTIONS: Array[StringName] = [&"buy_supply_1", &"buy_supply_2", &"buy_supply_3"]
## Every station is in this group (the ability bar leaves keys 1-3 to an open menu).
const GROUP := &"upgrade_stations"
## Key shown for SUPPLY_ACTIONS[0]; the next ones follow.
const FIRST_SUPPLY_KEY := 5

## Where the coin burst of a supply purchase plays, relative to the station.
@export var coin_burst_offset := Vector2(0, -24)

var run_state: RunState:
	set(value):
		if run_state and run_state.changed.is_connected(_refresh):
			run_state.changed.disconnect(_refresh)
		run_state = value
		if run_state:
			run_state.changed.connect(_refresh)
		if is_node_ready():
			_refresh()

var is_open := false
var _player_near := false
var _message := ""
var _room: Room

@onready var _area: Area2D = $InteractArea
@onready var _prompt: Label = $Prompt
@onready var _menu: CanvasLayer = $Menu
@onready var _menu_label: Label = %MenuLabel


func _ready() -> void:
	add_to_group(GROUP)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)
	var node := get_parent()
	while node and not node is Room:
		node = node.get_parent()
	_room = node as Room
	if _room:
		_room.state_changed.connect(func(_state: Room.State) -> void: _refresh())
	_refresh()


func _exit_tree() -> void:
	# Leaving the room (transition/restart) always closes the station.
	_player_near = false
	is_open = false
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not is_usable():
		return
	if event.is_action_pressed(&"interact"):
		set_open(not is_open)
		get_viewport().set_input_as_handled()
	elif is_open:
		for i in BUY_ACTIONS.size():
			if event.is_action_pressed(BUY_ACTIONS[i]):
				purchase(RunState.UPGRADES.keys()[i])
				get_viewport().set_input_as_handled()
				return
		for i in mini(SUPPLY_ACTIONS.size(), RunState.CONSUMABLES.size()):
			if event.is_action_pressed(SUPPLY_ACTIONS[i]):
				purchase_supply(RunState.CONSUMABLES.keys()[i])
				get_viewport().set_input_as_handled()
				return


## True if any station's menu in `tree` is open (it then owns keys 1-7).
static func any_open(tree: SceneTree) -> bool:
	for node in tree.get_nodes_in_group(GROUP):
		if (node as UpgradeStation).is_open:
			return true
	return false


## True when the player is in range, the run is known and no combat is running.
func is_usable() -> bool:
	return run_state != null and _player_near and (_room == null or _room.state != Room.State.COMBAT)


func set_open(open: bool) -> void:
	is_open = open and is_usable()
	_message = ""
	_refresh()


## Tries to buy upgrade `id` through RunState (menu must be open). Returns true on success.
func purchase(id: StringName) -> bool:
	if not is_open or not is_usable() or not RunState.UPGRADES.has(id):
		return false
	var upgrade_name: String = RunState.UPGRADES[id]["name"]
	var ok := run_state.purchase(id)
	if ok:
		_message = "Bought %s!" % upgrade_name
	elif run_state.upgrade_stacks(id) >= run_state.upgrade_max_stacks(id):
		_message = "%s is at its maximum." % upgrade_name
	elif run_state.dungeon_level < run_state.upgrade_min_dungeon_level(id):
		_message = "%s is sold from dungeon level %d." % [upgrade_name, run_state.upgrade_min_dungeon_level(id)]
	elif run_state.is_purchased(id):
		_message = "%s already bought this level." % upgrade_name
	elif run_state.level < run_state.upgrade_level(id):
		_message = "%s requires Lv %d." % [upgrade_name, run_state.upgrade_level(id)]
	else:
		_message = "Not enough gold for %s." % upgrade_name
	_refresh()
	return ok


## Tries to buy consumable `id` through RunState (menu must be open). Returns true on success.
func purchase_supply(id: StringName) -> bool:
	if not is_open or not is_usable() or not RunState.CONSUMABLES.has(id):
		return false
	var supply_name: String = RunState.CONSUMABLES[id]["name"]
	var ok := run_state.buy_consumable(id)
	if ok:
		_message = "Bought %s! (%d/%d)" % [supply_name, run_state.consumable_count(id), run_state.consumable_max(id)]
		EffectLibrary.spawn(&"coin_burst", self, global_position + coin_burst_offset)
	elif run_state.consumable_count(id) >= run_state.consumable_max(id):
		_message = "%s: inventory full." % supply_name
	else:
		_message = "Not enough gold for %s." % supply_name
	_refresh()
	return ok


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		_player_near = true
		_refresh()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		_player_near = false
		is_open = false
		_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	if is_open and not is_usable():
		is_open = false
	_prompt.visible = _player_near and run_state != null and not is_open
	_prompt.text = "[E] Anvil" if is_usable() else "Anvil (unavailable in combat)"
	_menu.visible = is_open
	if not is_open:
		return
	var lines: Array[String] = ["ANVIL      Lv %d   Gold %d" % [run_state.level, run_state.currency], ""]
	var ids := RunState.UPGRADES.keys()
	for i in ids.size():
		var data: Dictionary = RunState.UPGRADES[ids[i]]
		var status := ""
		var required := run_state.upgrade_level(ids[i])
		var stacks := run_state.upgrade_stacks(ids[i])
		var max_stacks := run_state.upgrade_max_stacks(ids[i])
		if stacks >= max_stacks:
			status = "  [MAX]"
		elif run_state.dungeon_level < run_state.upgrade_min_dungeon_level(ids[i]):
			status = "  [from dungeon level %d]" % run_state.upgrade_min_dungeon_level(ids[i])
		elif run_state.is_purchased(ids[i]):
			status = "  [bought this level]"
		elif run_state.level < required:
			status = "  [requires Lv %d]" % required
		elif run_state.currency < run_state.upgrade_cost(ids[i]):
			status = "  [not enough gold]"
		lines.append("[%d] %s (%d/%d) - %d gold, Lv %d: %s%s" % [i + 1, data["name"], stacks, max_stacks,
				run_state.upgrade_cost(ids[i]), required, data["effect"], status])
	lines.append("")
	lines.append("SUPPLIES")
	var supplies := RunState.CONSUMABLES.keys()
	for i in mini(SUPPLY_ACTIONS.size(), supplies.size()):
		var data: Dictionary = RunState.CONSUMABLES[supplies[i]]
		var count := run_state.consumable_count(supplies[i])
		var cap := run_state.consumable_max(supplies[i])
		var status := ""
		if count >= cap:
			status = "  [full]"
		elif run_state.currency < run_state.consumable_price(supplies[i]):
			status = "  [not enough gold]"
		lines.append("[%d] %s (%d/%d) - %d gold: %s%s" % [FIRST_SUPPLY_KEY + i, data["name"], count, cap,
				run_state.consumable_price(supplies[i]), data["effect"], status])
	lines.append("")
	lines.append(_message if not _message.is_empty() else "[1-4] Upgrades   [%d-%d] Supplies   [E] Close" % [
			FIRST_SUPPLY_KEY, FIRST_SUPPLY_KEY + SUPPLY_ACTIONS.size() - 1])
	_menu_label.text = "\n".join(lines)
