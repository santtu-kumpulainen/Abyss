class_name HomeTeleport
extends Node
## Home Teleport cast (Issue #49), owned by the Dungeon. try_start() begins a
## RunState "cast_time" (1.5 s) cast; the Mage must stay still and keep out of
## combat for all of it. Any movement input, actual movement (also pushes),
## damage that gets through, a dash, an attack, a room or level change, the
## current room entering combat (e.g. a trial started at its altar), death or
## victory cancels it at once and keeps the item. When the cast completes,
## Dungeon.teleport_home() moves the Mage to the run's current start_room and
## spends the item, only if the teleport happens.
##
## For the HUD: is_casting(), cast_progress(), can_start(), quantity() and the
## signals below. Visuals: a flattened blue ring under the Mage that grows with
## the progress, and a looping aura around it (EffectLibrary).

signal cast_started
## `reason`: &"input", &"moved", &"damage", &"dash", &"attack", &"combat", &"room_change",
## &"level_change", &"death", &"victory", &"manual" or &"failed".
signal cast_cancelled(reason: StringName)
## The teleport happened (the Mage is in the start room, the item is spent).
signal cast_completed
## Any change of the state above (start, cancel, completion).
signal state_changed

const ITEM := &"home_teleport"
## Position change (px) that counts as moving during the cast.
const MOVE_EPSILON := 0.5

enum State { IDLE, CASTING, TELEPORTING }

## Ring size at the start of the cast, relative to its full size.
@export var ring_start_scale := 0.3
## Vertical squash of the ring (ground perspective).
@export var ring_flatten := 0.5
@export var cancel_fade := 0.1

var dungeon: Dungeon
var _state := State.IDLE
var _elapsed := 0.0
var _cast_position := Vector2.ZERO
var _ring: PixelEffect
var _aura: PixelEffect
## Current room, watched for entering combat.
var _room: Room


## Connects to the Dungeon's Mage and room changes. Called once by the Dungeon.
func setup(p_dungeon: Dungeon) -> void:
	dungeon = p_dungeon
	var mage := dungeon.mage
	mage.dash_started.connect(func(_dir: Vector2) -> void: cancel(&"dash"))
	mage.health.damaged.connect(func(_amount: float, _current: float) -> void: cancel(&"damage"))
	mage.died.connect(func() -> void: cancel(&"death"))
	mage.caster.cast.connect(func(_p: Projectile) -> void: cancel(&"attack"))
	dungeon.room_changed.connect(func(room: Room, _index: int) -> void:
		cancel(&"room_change")
		_watch_room(room))
	dungeon.victory_started.connect(func() -> void: cancel(&"victory"))


## Cast duration in seconds (RunState.CONSUMABLES).
func cast_time() -> float:
	return RunState.CONSUMABLES[ITEM]["cast_time"]


## Owned Home Teleports (RunState inventory).
func quantity() -> int:
	return dungeon.run_state.consumable_count(ITEM) if dungeon else 0


func is_casting() -> bool:
	return _state == State.CASTING


## True from the cast start until the teleport has finished.
func is_busy() -> bool:
	return _state != State.IDLE


## Cast progress: 0.0 at the start, 1.0 when complete (0.0 when not casting).
func cast_progress() -> float:
	if _state == State.TELEPORTING:
		return 1.0
	if _state != State.CASTING:
		return 0.0
	return clampf(_elapsed / cast_time(), 0.0, 1.0)


func can_start() -> bool:
	return start_refusal() == &""


## Why a cast cannot start now, or &"" if it can: &"busy", &"none_owned",
## &"dead", &"victory", &"transition", &"no_room", &"start_room", &"combat"
## or &"dashing".
func start_refusal() -> StringName:
	if dungeon == null:
		return &"no_room"
	if is_busy():
		return &"busy"
	if quantity() <= 0:
		return &"none_owned"
	if dungeon.mage.is_dead():
		return &"dead"
	if dungeon.victory:
		return &"victory"
	if dungeon.is_transitioning():
		return &"transition"
	if dungeon.current_room == null:
		return &"no_room"
	if dungeon.current_index == dungeon.start_room:
		return &"start_room"
	if dungeon.current_room.state == Room.State.COMBAT:
		return &"combat"
	if dungeon.mage.is_dashing():
		return &"dashing"
	return &""


## Starts the cast. Returns false (changing nothing) if start_refusal() is set.
func try_start() -> bool:
	if not can_start():
		return false
	_state = State.CASTING
	_elapsed = 0.0
	_cast_position = dungeon.mage.global_position
	_spawn_cast_effects()
	cast_started.emit()
	state_changed.emit()
	return true


## Cancels a running cast (the item is kept). Returns false if none was running.
func cancel(reason: StringName = &"manual") -> bool:
	if _state != State.CASTING:
		return false
	_state = State.IDLE
	_elapsed = 0.0
	# Leaving the room: remove at once, so nothing is carried along.
	_stop_cast_effects(0.0 if reason in [&"room_change", &"level_change", &"death"] else cancel_fade)
	cast_cancelled.emit(reason)
	state_changed.emit()
	return true


## Follows `room`'s Room.state_changed: entering COMBAT cancels a cast.
func _watch_room(room: Room) -> void:
	if _room and is_instance_valid(_room) and _room.state_changed.is_connected(_on_room_state_changed):
		_room.state_changed.disconnect(_on_room_state_changed)
	_room = room
	if _room:
		_room.state_changed.connect(_on_room_state_changed)


func _on_room_state_changed(state: Room.State) -> void:
	if state == Room.State.COMBAT:
		cancel(&"combat")


func _physics_process(delta: float) -> void:
	if _state != State.CASTING:
		return
	var mage := dungeon.mage
	if not Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down").is_zero_approx():
		cancel(&"input")
	elif mage.is_attack_held():
		cancel(&"attack")
	elif mage.global_position.distance_to(_cast_position) > MOVE_EPSILON:
		cancel(&"moved")
	elif mage.is_dead():
		cancel(&"death")
	elif dungeon.current_room and dungeon.current_room.state == Room.State.COMBAT:
		# Backstop for the state_changed signal above.
		cancel(&"combat")
	if _state != State.CASTING:
		return
	_elapsed += delta
	_update_ring()
	if _elapsed >= cast_time() - 0.0001:
		_complete()


func _complete() -> void:
	_state = State.TELEPORTING
	_stop_cast_effects(0.0)
	if not dungeon.teleport_home(_on_teleport_finished):
		_on_teleport_finished(false)


func _on_teleport_finished(success: bool) -> void:
	_state = State.IDLE
	_elapsed = 0.0
	if success:
		cast_completed.emit()
	else:
		cast_cancelled.emit(&"failed")
	state_changed.emit()


func _spawn_cast_effects() -> void:
	var mage := dungeon.mage
	var parent := mage.get_parent()
	_ring = EffectLibrary.spawn(&"teleport_ring", parent, mage.global_position)
	_aura = EffectLibrary.spawn(&"teleport_aura", parent, mage.caster.global_position)
	for effect in [_ring, _aura]:
		if effect:
			_put_behind(effect, mage)
	_update_ring()


## Same z as the Mage, just before it among its siblings: above the room floor,
## under the Mage (also in the y-sorted Dungeon).
static func _put_behind(effect: Node2D, mage: Mage) -> void:
	effect.z_index = mage.z_index
	if effect.get_parent() == mage.get_parent():
		mage.get_parent().move_child(effect, mage.get_index())


func _update_ring() -> void:
	if _ring and is_instance_valid(_ring):
		var size := lerpf(ring_start_scale, 1.0, cast_progress())
		_ring.scale = Vector2(size, size * ring_flatten)


func _stop_cast_effects(fade: float) -> void:
	for effect in [_ring, _aura]:
		if effect and is_instance_valid(effect):
			if fade > 0.0:
				(effect as PixelEffect).stop(fade)
			else:
				effect.queue_free()
	_ring = null
	_aura = null
