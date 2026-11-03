class_name SurvivalRoom
extends Room
## Timed survival treasure room. Entering does not start anything (the doors
## stay open and the Mage may leave); using the ChallengeAltar
## ("Decor/ChallengeAltar") starts the trial once: the doors lock (COMBAT) and
## a `duration`-second timer runs. Wave 1 spawns at once; each next wave spawns
## as soon as every enemy of the current wave is dead (checked once per physics
## frame, so duplicate death signals cannot skip a wave), never while enemies
## remain. Wave i has `wave_sizes[i]` enemies (taken in order from
## `wave_enemies`), placed at SpawnPoints at least `min_spawn_distance` away
## from the Mage. The timer keeps running throughout. The room clears only when
## the timer has run out AND all waves have spawned and been defeated: clearing
## every wave early means surviving until 0:00 (the HUD says so); running out
## of time with waves left means fighting the remaining waves. Clearing unlocks the TreasureChest
## ("Decor/TreasureChest"). The room instance is cached by the Dungeon, so a
## completed trial never restarts; Restart reloads the scene.

## Trial length in seconds.
@export var duration: float = 120.0
## Enemies per wave; the wave count is its size.
@export var wave_sizes := PackedInt32Array([3, 4, 5, 6])
## Enemy scenes used by the waves, in spawn order (sum of wave_sizes).
@export var wave_enemies: Array[PackedScene] = []
## Spawn points closer than this to the Mage are skipped (if any farther exist).
@export var min_spawn_distance: float = 260.0
## Offset between enemies sharing a spawn point (a wave larger than the
## usable points), so they don't stack.
@export var spawn_spread: float = 40.0
## Difficulty pressure: extra enemies added to every wave (repeating that
## wave's own enemy types). Set by the Dungeon before the room is ready.
var extra_per_wave := 0

## Seconds since the trial started.
var elapsed := 0.0
## Waves spawned so far.
var waves_spawned := 0

var _spawned_enemies := 0
var _shown_seconds := -1

@onready var altar: ChallengeAltar = $Decor/ChallengeAltar
@onready var chest: TreasureChest = $Decor/TreasureChest


func _ready() -> void:
	super._ready()
	altar.interacted.connect(begin_challenge)
	chest.opened.connect(status_changed.emit)


## Entering the room (or its EncounterTrigger) never starts the trial.
func start_encounter() -> void:
	pass


## Starts the trial once (only while IDLE). Returns true if it started.
func begin_challenge() -> bool:
	if state != State.IDLE:
		return false
	elapsed = 0.0
	waves_spawned = 0
	_set_doors_locked(true)
	_set_state(State.COMBAT)
	_advance(0.0)
	return true


## Seconds left on the trial timer.
func time_left() -> float:
	return maxf(duration - elapsed, 0.0)


func is_running() -> bool:
	return state == State.COMBAT


func wave_count() -> int:
	return wave_sizes.size()


## True once every wave has spawned and been defeated (the timer may still run).
func all_waves_cleared() -> bool:
	return waves_spawned >= wave_count() and enemies_remaining == 0


## Doors stay usable before the trial; locked while it runs.
func can_exit() -> bool:
	return state != State.COMBAT


func status_text() -> String:
	match state:
		State.IDLE:
			return "Survival trial: use the altar to begin (%d s, doors lock)" % roundi(duration)
		State.COMBAT:
			var secs := ceili(time_left())
			var clock := "%d:%02d" % [floori(secs / 60.0), secs % 60]
			if time_left() > 0.0:
				if all_waves_cleared():
					return "All waves cleared - survive until time runs out: %s" % clock
				return "Survive %s   Wave %d/%d   Enemies %d" % [clock, waves_spawned, wave_count(), enemies_remaining]
			if waves_spawned < wave_count() or enemies_remaining > 1:
				return "Time's up! Defeat the remaining waves: Wave %d/%d   Enemies %d" % [waves_spawned, wave_count(), enemies_remaining]
			return "Time's up! Defeat the last enemy"
	return "Treasure claimed" if chest.is_claimed() else "Trial complete! Open the chest"


func _physics_process(delta: float) -> void:
	if state == State.COMBAT:
		_advance(delta)


## Moves the trial clock forward by `seconds`, spawns the next wave if the
## current one is defeated (at most one per call) and completes the trial when
## the time is up and every wave is defeated.
func _advance(seconds: float) -> void:
	if state != State.COMBAT:
		return
	elapsed = minf(elapsed + seconds, duration)
	if enemies_remaining == 0 and waves_spawned < wave_count():
		_spawn_wave(waves_spawned)
		waves_spawned += 1
		enemies_remaining_changed.emit(enemies_remaining)
	if _is_complete():
		_clear()
		return
	if ceili(time_left()) != _shown_seconds:
		_shown_seconds = ceili(time_left())
		status_changed.emit()


func _is_complete() -> bool:
	return time_left() <= 0.0 and all_waves_cleared()


func _spawn_wave(wave: int) -> void:
	var base_count: int = wave_sizes[wave] if wave < wave_sizes.size() else 0
	var count := base_count + (extra_per_wave if base_count > 0 else 0)
	var wave_start := _spawned_enemies
	var points := _spawn_points()
	for i in count:
		var scene_index := _spawned_enemies if i < base_count else wave_start + (i - base_count) % base_count
		if scene_index >= wave_enemies.size():
			push_error("%s: wave %d needs more wave_enemies" % [name, wave + 1])
			return
		var enemy := wave_enemies[scene_index].instantiate() as Enemy
		if i < base_count:
			_spawned_enemies += 1
		# Rotate through the points so consecutive waves come from different sides.
		var point: Node2D = points[(i + wave) % points.size()]
		# Extra enemies on a reused point are pushed outwards along a ring.
		var ring := floori(float(i) / points.size())
		enemy.position = point.position + Vector2.RIGHT.rotated(TAU * i / float(count)) * spawn_spread * ring
		enemy.detection_radius = spawn_detection_radius
		_enemy_container.add_child(enemy, true)
		_register_enemy(enemy, true)


## SpawnPoints at least min_spawn_distance from the Mage, or (if none) the
## farthest half of them.
func _spawn_points() -> Array:
	var points := get_node(^"SpawnPoints").get_children()
	var mage := get_tree().get_first_node_in_group(&"player") as Node2D
	if mage == null:
		return points
	var far := points.filter(func(p: Node2D) -> bool:
		return p.global_position.distance_to(mage.global_position) >= min_spawn_distance)
	if not far.is_empty():
		return far
	points.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_to(mage.global_position) > b.global_position.distance_to(mage.global_position))
	return points.slice(0, maxi(ceili(points.size() / 2.0), 1))
