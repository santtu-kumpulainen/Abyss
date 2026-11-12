class_name Miniboss
extends Enemy
## Shared base of the miniboss encounters (Issue #43). A miniboss replaces a
## seal room's encounter: the Dungeon gives it that encounter's XP and gold, so
## the room XP budget is unchanged. Attack flow (subclasses pick the attacks):
##   CHASE   - moves / picks the next attack (_choose()); no attacks during the
##             first `opening_delay` seconds.
##   WINDUP  - a telegraphed attack winds up for a fixed time (never scaled by
##             pace, so telegraphs stay readable); then _windup_finished().
##   ACTION  - optional active part (e.g. a dash), until _action() returns true.
##   RECOVER - pause, then back to CHASE.
## While a windup is marked vulnerable (a punish window) the miniboss takes
## `punish_multiplier` x damage. Summons (_summon()) join the room encounter
## with 0 XP and 0 gold and die with the miniboss; its FloorHazards and bolts
## are removed when it dies, so nothing outlives the encounter.
## The Dungeon calls configure_for_level() with the dungeon level at spawn, so
## a miniboss can pick its behaviour tier (Issue #51); the default does nothing.
## floor_rect() is the floor it fights on: its Room's RoomVisuals floor, or
## outside a Room (test scenes) a sibling's "Floor" control.

## Emitted when an attack's telegraph starts.
signal attack_started(attack: StringName)
## Emitted when an attack ends (after its windup / action).
signal attack_resolved(attack: StringName)

enum State { CHASE, WINDUP, ACTION, RECOVER }

@export var display_name: String = "Miniboss"
## Seconds after activation before the first attack.
@export var opening_delay: float = 1.2
## Pause after each attack.
@export var recover_time: float = 0.6
## Damage taken multiplier during vulnerable windups (punish windows).
@export var punish_multiplier: float = 1.6
@export var muzzle_offset := Vector2(0, -40)
## Summon / zone points stay this far inside the room floor (clear of walls and corner decor).
@export var floor_margin: float = 150.0

var state: State = State.CHASE
## Attack being telegraphed / performed (&"" when none).
var current_attack: StringName = &""

var _state_left := 0.0
var _windup_total := 0.0
var _vulnerable := false
var _opening_left := 0.0
var _summons: Array[Enemy] = []


func _ready() -> void:
	super._ready()
	_opening_left = opening_delay
	var label := get_node_or_null(^"NameLabel") as Label
	if label:
		label.text = display_name


## True during a punish window.
func is_vulnerable() -> bool:
	return _vulnerable


func take_damage(amount: float) -> void:
	super.take_damage(amount * (punish_multiplier if _vulnerable else 1.0))


## Living summons of this miniboss.
func alive_summons() -> Array[Enemy]:
	var alive: Array[Enemy] = []
	for e in _summons:
		if is_instance_valid(e) and not e.is_queued_for_deletion() and not e.health.is_dead():
			alive.append(e)
	_summons = alive
	return alive.duplicate()


## Telegraph progress 0..1 of the current windup.
func windup_progress() -> float:
	return clampf(1.0 - _state_left / maxf(_windup_total, 0.01), 0.0, 1.0) if state == State.WINDUP else 0.0


func _physics_process(delta: float) -> void:
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	_opening_left = maxf(_opening_left - delta, 0.0)
	_tick(delta)
	target = _find_target()
	velocity = Vector2.ZERO
	match state:
		State.CHASE:
			if target:
				facing = direction_name(target.global_position - global_position)
				_choose(delta, _opening_left <= 0.0)
		State.WINDUP:
			_state_left -= delta
			if _state_left <= 0.0:
				_windup_finished(current_attack)
		State.ACTION:
			if _action(delta):
				_end_attack()
		State.RECOVER:
			_state_left -= delta
			if _state_left <= 0.0:
				state = State.CHASE
	move_and_slide()
	_play(&"walk" if velocity != Vector2.ZERO else &"idle")
	queue_redraw()


## Starts telegraphing `attack` for `windup` seconds (`vulnerable`: punish window).
func _begin(attack: StringName, windup: float, vulnerable: bool = false) -> void:
	current_attack = attack
	state = State.WINDUP
	_state_left = windup
	_windup_total = windup
	_vulnerable = vulnerable
	attack_started.emit(attack)


## Moves on from a windup into the attack's ACTION part.
func _start_action() -> void:
	state = State.ACTION
	_vulnerable = false


## Ends the current attack and recovers for `pause` seconds (default recover_time).
func _end_attack(pause: float = -1.0) -> void:
	var attack := current_attack
	current_attack = &""
	_vulnerable = false
	state = State.RECOVER
	_state_left = recover_time if pause < 0.0 else pause
	attack_resolved.emit(attack)


## Spawns `scene` as a summon at global `pos` (0 XP, 0 gold) in this room's encounter.
func _summon(scene: PackedScene, pos: Vector2) -> Enemy:
	var room := _room()
	if scene == null or room == null:
		return null
	var enemy := scene.instantiate() as Enemy
	enemy.xp_reward = 0
	enemy.currency_reward = 0
	enemy.summoned = true
	room.add_summoned_enemy(enemy, pos)
	_summons.append(enemy)
	return enemy


## Global `pos` moved inside the room floor, at least `floor_margin` from its edges.
func _clamp_to_floor(pos: Vector2) -> Vector2:
	var area := floor_rect()
	if not area.has_area():
		return pos
	var rect := area.grow(-floor_margin)
	return pos.clamp(rect.position, rect.end)


## Global rect of the floor this miniboss fights on: its Room's RoomVisuals
## floor_rect; outside a Room the first "Floor" Control of a sibling (e.g.
## scenes/rooms/test_room.tscn); else an empty Rect2.
func floor_rect() -> Rect2:
	var room := _room()
	if room:
		var visuals := room.get_node_or_null(^"Visuals") as RoomVisuals
		if visuals:
			return Rect2(room.to_global(visuals.floor_rect.position), visuals.floor_rect.size)
		return Rect2()
	var parent := get_parent()
	if parent == null:
		return Rect2()
	for sibling in parent.get_children():
		var area := sibling.get_node_or_null(^"Floor") as Control
		if area:
			return area.get_global_rect()
	return Rect2()


## Node that holds this miniboss's floor hazards: its Room (so they are freed
## with it), else its own parent.
func _hazard_parent() -> Node:
	var room := _room()
	return room if room else get_parent()


func _room() -> Room:
	var node := get_parent()
	while node and not node is Room:
		node = node.get_parent()
	return node as Room


## Moves towards the target and hits it on contact (like Enemy).
func _chase_and_hit() -> void:
	var to_target := target.global_position - global_position
	if to_target.length() > attack_range:
		velocity = to_target.normalized() * speed
	elif _attack_cooldown_left <= 0.0:
		_attack_cooldown_left = attack_cooldown
		target.take_damage(contact_damage)


# --- Subclass hooks ----------------------------------------------------------------

## Called by the Dungeon at spawn with the dungeon level (behaviour tiers).
func configure_for_level(_level: int) -> void:
	pass


## Cooldown timers.
func _tick(_delta: float) -> void:
	pass


## CHASE: move and start attacks (`can_attack` is false during the opening delay).
func _choose(_delta: float, _can_attack: bool) -> void:
	pass


## The windup of `attack` is over: resolve it, then _end_attack() or _start_action().
func _windup_finished(_attack: StringName) -> void:
	_end_attack()


## ACTION part; return true when it is over.
func _action(_delta: float) -> bool:
	return true


func _on_died() -> void:
	_vulnerable = false
	FloorHazard.clear_from(get_tree(), self)
	var container: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	for child in container.get_children():
		if child is Projectile and (child as Projectile).source == self:
			child.queue_free()
	# Summons crumble with their master (they grant nothing).
	for e in alive_summons():
		e.take_damage(e.health.max_health * 100.0)
	super._on_died()
