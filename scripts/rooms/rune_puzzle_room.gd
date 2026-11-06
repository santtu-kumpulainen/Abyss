class_name RunePuzzleRoom
extends Room
## Rune sequence treasure room. No combat: the doors always stay open. The
## RuneSwitch children of "Decor" must be activated in `sequence` order (a
## hint plaque in the scene gives the order). A correct rune stays lit; a
## wrong one flashes red, all runes go dark and the sequence restarts. The
## full sequence solves the puzzle once (CLEARED) and unlocks the
## TreasureChest ("Decor/TreasureChest"). Progress lives on the cached room
## instance, so it persists on revisits; Restart reloads the scene.
## The Dungeon may set a seeded `sequence` before the room is ready; the
## plaque ("Decor/Plaque") is then written from it with hint_text().

## Correct activation order (RuneSwitch.rune_id values).
@export var sequence: PackedStringArray = ["moon", "sun", "star"]
## Plaque riddle; the %s are the runes in `sequence` order.
@export_multiline var hint_template: String = "\"First the %s rises, then the %s follows,\nand the %s closes the night.\""

## Runes lit so far in the current attempt.
var progress := 0
## Wrong activations so far (for the HUD/tests).
var mistakes := 0

var _runes: Array[RuneSwitch] = []
var _wrong_last := false

@onready var chest: TreasureChest = $Decor/TreasureChest


## The plaque riddle for `order` (runes capitalised, in order).
func hint_text(order: PackedStringArray) -> String:
	var names: Array = Array(order).map(func(id: String) -> String: return id.capitalize())
	if names.size() != hint_template.count("%s"):
		return " - ".join(names)
	return hint_template % names


func _ready() -> void:
	super._ready()
	var plaque := get_node_or_null(^"Decor/Plaque") as Label
	if plaque:
		plaque.text = hint_text(sequence)
	for node in $Decor.get_children():
		if node is RuneSwitch:
			_runes.append(node)
			node.interacted.connect(activate.bind(node.rune_id))
	chest.opened.connect(status_changed.emit)


## Entering the room never starts an encounter.
func start_encounter() -> void:
	pass


func can_exit() -> bool:
	return true


func is_solved() -> bool:
	return state == State.CLEARED


func get_rune(id: String) -> RuneSwitch:
	for rune in _runes:
		if rune.rune_id == id:
			return rune
	return null


## Activates rune `id`. Returns true if it was the correct next rune. A lit
## rune or a solved puzzle ignores activations (returns false, no reset).
func activate(id: String) -> bool:
	var rune := get_rune(id)
	if is_solved() or rune == null or rune.lit:
		return false
	if sequence[progress] == id:
		rune.lit = true
		progress += 1
		_wrong_last = false
		if progress >= sequence.size():
			for r in _runes:
				r.solved = true
			_clear()
		else:
			status_changed.emit()
		return true
	mistakes += 1
	progress = 0
	_wrong_last = true
	for r in _runes:
		r.lit = false
		r.flash_wrong()
	status_changed.emit()
	return false


func status_text() -> String:
	if is_solved():
		return "Treasure claimed" if chest.is_claimed() else "Puzzle solved! Open the chest"
	if _wrong_last:
		return "Wrong order - the runes reset. Read the plaque. (%d/%d)" % [progress, sequence.size()]
	return "Rune puzzle: touch the runes in the right order (%d/%d)" % [progress, sequence.size()]
