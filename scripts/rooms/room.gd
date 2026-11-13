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
## Special rooms (e.g. treasure rooms) can override start_encounter(),
## can_exit(), status_text() and _is_complete().

signal state_changed(state: State)
signal enemies_remaining_changed(count: int)
signal cleared
## Emitted once for each encounter enemy that dies (used for run rewards).
signal enemy_defeated(enemy: Enemy)
## Emitted when status_text() changes for reasons other than the signals above.
signal status_changed
## Emitted once for each enemy joining the encounter (scene-placed ones when
## the room becomes ready, spawned ones such as survival waves when added).
## The Dungeon applies run scaling here.
signal enemy_registered(enemy: Enemy)

enum State { IDLE, COMBAT, CLEARED }

## Start the encounter immediately instead of waiting for the trigger.
@export var start_on_ready: bool = false
## HUD text once the room is cleared (e.g. for a placeholder room).
@export var cleared_text: String = "Room cleared"
## Detection radius given to enemies added with add_encounter_enemies().
@export var spawn_detection_radius: float = 800.0
## Sampled extra-enemy spawns (extra_spawn_points()): least distance to any
## enemy, SpawnPoints marker, Decor object, the PlayerSpawn or another sample.
@export var extra_spawn_spacing: float = 72.0
## Sampled extra-enemy spawns: least distance to the floor edge (walls) and to
## every Obstacle footprint.
@export var extra_spawn_clearance: float = 40.0

## Random tries per sampled extra-enemy position before extra_spawn_points()
## falls back to the free SpawnPoints markers.
const EXTRA_SPAWN_TRIES := 60

var state: State = State.IDLE
var enemies_remaining: int = 0

var _enemies: Array[Enemy] = []

@onready var _enemy_container: Node = $Enemies
@onready var _door_container: Node = $Doors
@onready var _trigger: Area2D = get_node_or_null(^"EncounterTrigger")


func _ready() -> void:
	for child in _enemy_container.get_children():
		if child is Enemy:
			_register_enemy(child as Enemy, false)
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
	AudioManager.sfx(self, &"door_close")
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


## Difficulty pressure: adds up to `count` enemies (cycling through `scenes`)
## at `positions` (room coordinates, e.g. from extra_spawn_points()) or, if none
## are given, at the SpawnPoints markers not used by the first `used` enemies and
## at least `min_door_distance` from every door, so nothing spawns on top of
## another enemy or next to an arriving Mage. At most `max_elites` of them are
## elites (-1 = no limit): an elite scene past the limit is skipped for the next
## non-elite one, and nothing more is added if the pool has none. If too few
## positions are available, fewer enemies are added. Returns the number added.
## Call before the room enters the tree.
func add_extra_enemies(scenes: Array[PackedScene], count: int, used: int, min_door_distance: float = 180.0,
		positions: Array[Vector2] = [], max_elites: int = -1) -> int:
	if scenes.is_empty() or count <= 0:
		return 0
	var spots := positions if not positions.is_empty() else safe_extra_points(used, min_door_distance)
	var added := 0
	var elites := 0
	var next := 0
	for pos in spots:
		if added >= count:
			break
		var enemy: Enemy = null
		for attempt in scenes.size():
			var candidate := scenes[(next + attempt) % scenes.size()].instantiate() as Enemy
			if max_elites < 0 or not candidate.elite or elites < max_elites:
				enemy = candidate
				next += attempt + 1
				break
			candidate.free()
		if enemy == null:
			break
		if enemy.elite:
			elites += 1
		enemy.position = pos
		enemy.detection_radius = spawn_detection_radius
		get_node(^"Enemies").add_child(enemy, true)
		added += 1
	return added


## Up to `count` positions (room coordinates) for extra enemies, sampled from
## `rng_seed` (same seed and room = same positions): random points on the floor
## that pass is_valid_extra_spawn() and keep extra_spawn_spacing from each other.
## If sampling finds too few, the free safe SpawnPoints markers (safe_extra_points
## with `used`) fill up the rest (samples never come close to a marker). Call
## before the room enters the tree, after the planned enemies were added.
func extra_spawn_points(count: int, used: int, rng_seed: int, min_door_distance: float = 180.0) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if count <= 0:
		return result
	var area := _floor_area().grow(-extra_spawn_clearance)
	if area.has_area():
		var rng := RandomNumberGenerator.new()
		rng.seed = rng_seed
		var tries := 0
		while result.size() < count and tries < count * EXTRA_SPAWN_TRIES:
			tries += 1
			var pos := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
			if is_valid_extra_spawn(pos, result, min_door_distance):
				result.append(pos)
	for pos in safe_extra_points(used, min_door_distance):
		if result.size() >= count:
			break
		result.append(pos)
	return result


## True if an extra enemy may spawn at `pos` (room coordinates): on the floor at
## least extra_spawn_clearance from its edge, `min_door_distance` from every door
## and from the PlayerSpawn, clear of every Obstacle footprint (+ clearance), and
## extra_spawn_spacing from every enemy, SpawnPoints marker, Decor object and
## position in `taken`.
func is_valid_extra_spawn(pos: Vector2, taken: Array[Vector2] = [], min_door_distance: float = 180.0) -> bool:
	if not _floor_area().grow(-extra_spawn_clearance).has_point(pos):
		return false
	if has_node(^"Doors"):
		for door in get_node(^"Doors").get_children():
			if door is Node2D and pos.distance_to(_local_position(door as Node2D)) < min_door_distance:
				return false
	if has_node(^"PlayerSpawn") and pos.distance_to(_local_position(get_node(^"PlayerSpawn") as Node2D)) < min_door_distance:
		return false
	for node in find_children("*", "Obstacle", true, false):
		var obstacle := node as Obstacle
		var footprint := Rect2(_local_position(obstacle) - obstacle.footprint / 2.0, obstacle.footprint)
		if footprint.grow(extra_spawn_clearance).has_point(pos):
			return false
	var near: Array[Vector2] = taken.duplicate()
	for path: NodePath in [^"Enemies", ^"SpawnPoints", ^"Decor"]:
		if has_node(path):
			for child in get_node(path).get_children():
				if child is Node2D and not child is Obstacle:
					near.append(_local_position(child as Node2D))
	for other in near:
		if pos.distance_to(other) < extra_spawn_spacing:
			return false
	return true


## The walkable floor in room coordinates (RoomVisuals.floor_rect; the whole
## default room if there is no Visuals node).
func _floor_area() -> Rect2:
	var visuals := get_node_or_null(^"Visuals") as RoomVisuals
	if visuals == null:
		return Rect2(0, 0, 1152, 648)
	return Rect2(visuals.position + visuals.floor_rect.position, visuals.floor_rect.size)


## `node`'s position in room coordinates (works before the room is in the tree).
func _local_position(node: Node2D) -> Vector2:
	var xf := Transform2D.IDENTITY
	var current: Node = node
	while current != null and current != self:
		if current is Node2D:
			xf = (current as Node2D).transform * xf
		current = current.get_parent()
	return xf.origin


## Adds `enemy` (not yet in the tree) to the running encounter at global `pos`,
## e.g. a miniboss summon. It is registered like any encounter enemy (counted for
## the clear, scaled by the Dungeon through enemy_registered) and active at once
## while the room is in COMBAT.
func add_summoned_enemy(enemy: Enemy, pos: Vector2) -> void:
	enemy.detection_radius = spawn_detection_radius
	_enemy_container.add_child(enemy, true)
	enemy.global_position = pos
	_register_enemy(enemy, state == State.COMBAT)


## Positions (room coordinates) of the SpawnPoints from index `used` on that are
## at least `min_door_distance` from every door: where extra enemies may spawn.
func safe_extra_points(used: int, min_door_distance: float = 180.0) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not has_node(^"SpawnPoints"):
		return result
	var spawn_root := get_node(^"SpawnPoints") as Node2D
	var doors := get_node(^"Doors").get_children()
	var points := spawn_root.get_children()
	for i in range(used, points.size()):
		var pos := spawn_root.position + (points[i] as Node2D).position
		var safe := doors.all(func(door: Node2D) -> bool:
			return pos.distance_to(door.position + (door.get_parent() as Node2D).position) >= min_door_distance)
		if safe:
			result.append(pos)
	return result


## True when the Mage may leave through an open door (the Dungeon checks this).
func can_exit() -> bool:
	return state == State.CLEARED


## Text for the RoomHud ("" hides it).
func status_text() -> String:
	match state:
		State.COMBAT:
			return "Enemies remaining: %d" % enemies_remaining
		State.CLEARED:
			return cleared_text
	return ""


func get_doors() -> Array[Door]:
	var doors: Array[Door] = []
	for child in _door_container.get_children():
		if child is Door:
			doors.append(child)
	return doors


func _clear() -> void:
	# Doors only unlock audibly after a fight (an empty room clears silently).
	if state == State.COMBAT:
		AudioManager.sfx(self, &"door_open")
	_set_doors_locked(false)
	_set_state(State.CLEARED)
	cleared.emit()


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(state)


func _set_doors_locked(value: bool) -> void:
	for door in get_doors():
		door.locked = value


## Adds `enemy` (already a child of "Enemies") to the encounter.
func _register_enemy(enemy: Enemy, active: bool) -> void:
	_enemies.append(enemy)
	enemy.died.connect(_on_enemy_died.bind(enemy))
	_set_enemy_active(enemy, active)
	enemies_remaining = _enemies.size()
	enemy_registered.emit(enemy)


## True when the running encounter is won (checked after each kill).
func _is_complete() -> bool:
	return enemies_remaining == 0


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
	if state == State.COMBAT and _is_complete():
		_clear()
