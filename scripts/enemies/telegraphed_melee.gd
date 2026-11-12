class_name TelegraphedMelee
extends Enemy
## Regular melee enemy with one telegraphed special attack (Issue #47); the
## Goblin's sword strike and the Blood Monster's dash extend it. Phases:
##   CHASE   - walks at the target with contact damage (Enemy._pursue()). Starts
##             the special when _special_ready() (default: off cooldown),
##             `opening_delay` has passed since activation and the target is
##             within [special_min_range, special_max_range].
##   WINDUP  - stands still for `special_windup` s with the aim locked
##             (_lock_special()) while _draw() shows the exact hit area. Never
##             deals damage. The windup is not scaled by pace, so it stays readable.
##   ACTIVE  - _special_active() runs every frame until it returns true.
##   RECOVER - stands still for `special_recover` s (punish window), then CHASE.
## Damage scales through _scale_attacks(); the cooldown scales with attack pace.

## Emitted when the special's windup (telegraph) starts.
signal special_started
## Emitted when the special's active part ends.
signal special_resolved

enum Phase { CHASE, WINDUP, ACTIVE, RECOVER }

@export_group("Special attack")
## Seconds after activation (room entry) before the first special.
@export var opening_delay: float = 1.0
## The special only starts while the target is between these distances.
@export var special_min_range: float = 0.0
@export var special_max_range: float = 70.0
## Telegraph time before the special lands (not scaled by pace).
@export var special_windup: float = 0.6
## Pause after the special.
@export var special_recover: float = 0.5
## Seconds from one special's start to the next (scaled by attack pace).
@export var special_cooldown: float = 2.5
@export var special_damage: float = 14.0

var phase: Phase = Phase.CHASE
## Locked aim of the current special (unit vector).
var aim := Vector2.RIGHT

var _phase_left := 0.0
var _opening_left := 0.0
var _special_left := 0.0


func _ready() -> void:
	super._ready()
	_opening_left = opening_delay


func _scale_attacks(damage_mult: float, pace_mult: float) -> void:
	super._scale_attacks(damage_mult, pace_mult)
	special_damage *= damage_mult
	special_cooldown /= maxf(pace_mult, 0.01)


## The RECOVER pause after the special (the windup is never scaled).
func _scale_recovery(mult: float) -> void:
	super._scale_recovery(mult)
	special_recover /= mult


## Telegraph progress 0..1 during the windup.
func windup_progress() -> float:
	return clampf(1.0 - _phase_left / maxf(special_windup, 0.01), 0.0, 1.0) if phase == Phase.WINDUP else 0.0


## Starts the special's windup now, aimed at the target (ignores cooldown, range
## and the opening delay). Returns false if busy or without a target.
func begin_special() -> bool:
	if phase != Phase.CHASE:
		return false
	if target == null:
		target = _find_target()
	if target == null:
		return false
	_special_left = special_cooldown
	aim = (target.global_position - global_position).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	facing = direction_name(aim)
	_lock_special()
	phase = Phase.WINDUP
	_phase_left = special_windup
	special_started.emit()
	return true


func _physics_process(delta: float) -> void:
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	_opening_left = maxf(_opening_left - delta, 0.0)
	_special_left = maxf(_special_left - delta, 0.0)
	target = _find_target()
	velocity = Vector2.ZERO
	match phase:
		Phase.CHASE:
			if target:
				var dist := global_position.distance_to(target.global_position)
				if _opening_left <= 0.0 and _special_ready() and dist >= special_min_range and dist <= special_max_range:
					begin_special()
				else:
					_pursue()
		Phase.WINDUP:
			_phase_left -= delta
			if _phase_left <= 0.0:
				phase = Phase.ACTIVE
				_start_active()
		Phase.ACTIVE:
			if _special_active(delta):
				phase = Phase.RECOVER
				_phase_left = special_recover
				special_resolved.emit()
		Phase.RECOVER:
			_phase_left -= delta
			if _phase_left <= 0.0:
				phase = Phase.CHASE
	move_and_slide()
	_knockback_step(delta)
	_play(&"walk" if velocity != Vector2.ZERO else &"idle")
	queue_redraw()


## No knockback during the special's windup (telegraph) and strike.
func can_be_knocked_back() -> bool:
	return phase != Phase.WINDUP and phase != Phase.ACTIVE


# --- Subclass hooks ----------------------------------------------------------------

## True when the special may start (range and opening delay are checked separately).
func _special_ready() -> bool:
	return _special_left <= 0.0


## The aim was just locked (start of the windup).
func _lock_special() -> void:
	pass


## The windup is over: the active part starts this frame.
func _start_active() -> void:
	pass


## ACTIVE part, every physics frame; return true when it is over.
func _special_active(_delta: float) -> bool:
	return true
