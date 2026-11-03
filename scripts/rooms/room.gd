class_name Room
extends Node2D
## Reusable combat room. Expected children:
## - "Enemies": Enemy instances belonging to this room's encounter.
## - "Doors": Door instances (exits) locked during combat.
## - "EncounterTrigger" (optional Area2D): the encounter starts when a node in
##   the "player" group enters it. Without it, call start_encounter() or set
##   `start_on_ready`.
## Flow: IDLE (enemies inactive, doors open) -> COMBAT (doors locked, enemies
## active) -> CLEARED (all encounter enemies dead, doors open).
## Different rooms reuse this by placing different enemies under "Enemies".

signal state_changed(state: State)
signal enemies_remaining_changed(count: int)
signal cleared
## Emitted once for each encounter enemy that dies (used for run rewards).
signal enemy_defeated(enemy: Enemy)

enum State { IDLE, COMBAT, CLEARED }

## Start the encounter immediately instead of waiting for the trigger.
@export var start_on_ready: bool = false
## HUD text once the room is cleared (e.g. for a placeholder room).
@export var cleared_text: String = "Room cleared"
## Detection radius given to enemies added with add_encounter_enemies().
@export var spawn_detection_radius: float = 800.0

var state: State = State.IDLE
var enemies_remaining: int = 0

var _enemies: Array[Enemy] = []

@onready var _enemy_container: Node = $Enemies
@onready var _door_container: Node = $Doors
@onready var _trigger: Area2D = get_node_or_null(^"EncounterTrigger")


func _ready() -> void:
	for child in _enemy_container.get_children():
		var enemy := child as Enemy
		if enemy == null:
			continue
		_enemies.append(enemy)
		enemy.died.connect(_on_enemy_died.bind(enemy))
		_set_enemy_active(enemy, false)
	enemies_remaining = _enemies.size()
	_set_doors_locked(false)
	if _trigger:
		_trigger.body_entered.connect(_on_trigger_body_entered)
	if start_on_ready:
		start_encounter.call_deferred()


## Locks the doors and activates the encounter enemies. Only works once, from IDLE.
func start_encounter() -> void:
	if state != State.IDLE:
		return
	if _enemies.is_empty():
		_clear()
		return
	_set_doors_locked(true)
	for enemy in _enemies:
		_set_enemy_active(enemy, true)
	_set_state(State.COMBAT)
	enemies_remaining_changed.emit(enemies_remaining)


## Adds one enemy per scene at the "SpawnPoints" markers, in marker order.
## Call before the room enters the tree so _ready() includes them in the encounter.
func add_encounter_enemies(scenes: Array[PackedScene]) -> void:
	var points := get_node(^"SpawnPoints").get_children()
	if scenes.size() > points.size():
		push_error("%s: %d enemies but only %d spawn points" % [name, scenes.size(), points.size()])
	for i in mini(scenes.size(), points.size()):
		var enemy := scenes[i].instantiate() as Enemy
		enemy.position = (points[i] as Node2D).position
		enemy.detection_radius = spawn_detection_radius
		get_node(^"Enemies").add_child(enemy, true)


func get_doors() -> Array[Door]:
	var doors: Array[Door] = []
	for child in _door_container.get_children():
		if child is Door:
			doors.append(child)
	return doors


func _clear() -> void:
	_set_doors_locked(false)
	_set_state(State.CLEARED)
	cleared.emit()


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(state)


func _set_doors_locked(value: bool) -> void:
	for door in get_doors():
		door.locked = value


func _set_enemy_active(enemy: Enemy, active: bool) -> void:
	enemy.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func _on_trigger_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		start_encounter()


func _on_enemy_died(enemy: Enemy) -> void:
	if not _enemies.has(enemy):
		return
	_enemies.erase(enemy)
	enemy_defeated.emit(enemy)
	enemies_remaining = _enemies.size()
	enemies_remaining_changed.emit(enemies_remaining)
	if state == State.COMBAT and enemies_remaining == 0:
		_clear()
