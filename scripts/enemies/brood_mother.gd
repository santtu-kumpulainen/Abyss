class_name BroodMother
extends Miniboss
## Miniboss: summoner with punish windows (Issue #43).
## - Summon: she stops and channels for `summon_windup` s while green circles
##   (FloorHazards without damage) mark where `summon_count` Demons will crawl
##   out. While channelling she takes punish_multiplier x damage (the punish
##   window, shown by a pulsing ring). Only while fewer than `max_summons` live.
##   If she dies first, the circles vanish and nothing spawns.
## - Charge: locks the aim on the Mage and shows the dash lane (exactly the
##   hit width and length) for `charge_windup` s, then dashes along it at
##   `charge_speed` up to `charge_distance` (stops at walls). The first time the
##   Mage is within `charge_hit_radius` of her during the dash it takes
##   `charge_damage`. The lane is fixed at the windup start, so a sidestep dodges it.
## Otherwise she lumbers after the Mage with contact damage.

@export_group("Summon")
@export var summon_scene: PackedScene
@export var summon_count: int = 2
@export var max_summons: int = 4
@export var summon_windup: float = 1.8
@export var summon_cooldown: float = 7.0
## Distance of the summon circles from her.
@export var summon_distance: float = 130.0
@export var summon_radius: float = 34.0
@export var summon_color := Color(0.45, 1.0, 0.45)

@export_group("Charge")
@export var charge_windup: float = 0.85
@export var charge_cooldown: float = 4.5
@export var charge_speed: float = 620.0
@export var charge_distance: float = 440.0
@export var charge_damage: float = 18.0
@export var charge_hit_radius: float = 48.0
## Charges only start when the Mage is between these distances.
@export var charge_min_range: float = 110.0
@export var charge_max_range: float = 520.0
## Pause after a charge.
@export var charge_recover: float = 1.0

var _summon_left := 0.0
var _charge_left := 0.0
var _aim := Vector2.RIGHT
var _charge_travelled := 0.0
var _charge_hit := false
var _summon_points: Array[Vector2] = []


func _ready() -> void:
	super._ready()
	_summon_left = opening_delay
	_charge_left = opening_delay + 1.0


## Charge damage scales with damage, cooldowns with pace; telegraphs are kept.
func _scale_attacks(damage_mult: float, pace_mult: float) -> void:
	super._scale_attacks(damage_mult, pace_mult)
	charge_damage *= damage_mult
	summon_cooldown /= maxf(pace_mult, 0.01)
	charge_cooldown /= maxf(pace_mult, 0.01)


## Starts the summon channel now (ignores cooldown). Returns false if busy.
func begin_summon() -> bool:
	if state != State.CHASE:
		return false
	_summon_left = summon_cooldown
	_summon_points.clear()
	var room := _room()
	var forward := (target.global_position - global_position).normalized() if target else Vector2.DOWN
	if forward == Vector2.ZERO:
		forward = Vector2.DOWN
	for i in summon_count:
		# Fanned out to her sides, away from the Mage's line.
		var angle := PI / 2.0 * (1.0 if i % 2 == 0 else -1.0) + 0.35 * floorf(i / 2.0)
		var point := _clamp_to_floor(global_position + forward.rotated(angle) * summon_distance)
		_summon_points.append(point)
		var circle := FloorHazard.spawn(room if room else get_parent(), point, summon_radius, summon_windup, 0.0, 0.0, self, summon_color)
		circle.erupted.connect(_on_summon_circle.bind(point))
	_begin(&"summon", summon_windup, true)
	return true


## Starts the charge telegraph now, aimed at the Mage. Returns false if busy or without a target.
func begin_charge() -> bool:
	if state != State.CHASE:
		return false
	if target == null:
		target = _find_target()
	if target == null:
		return false
	_charge_left = charge_cooldown
	_aim = (target.global_position - global_position).normalized()
	if _aim == Vector2.ZERO:
		_aim = Vector2.RIGHT
	_charge_travelled = 0.0
	_charge_hit = false
	facing = direction_name(_aim)
	_begin(&"charge", charge_windup)
	return true


## Locked charge direction (unit vector).
func charge_aim() -> Vector2:
	return _aim


func _tick(delta: float) -> void:
	_summon_left = maxf(_summon_left - delta, 0.0)
	_charge_left = maxf(_charge_left - delta, 0.0)


func _choose(_delta: float, can_attack: bool) -> void:
	var dist := global_position.distance_to(target.global_position)
	if can_attack and _summon_left <= 0.0 and alive_summons().size() < max_summons:
		begin_summon()
	elif can_attack and _charge_left <= 0.0 and dist >= charge_min_range and dist <= charge_max_range:
		begin_charge()
	else:
		_chase_and_hit()


func _windup_finished(attack: StringName) -> void:
	if attack == &"charge":
		_start_action()
	else:
		_end_attack()


func _action(delta: float) -> bool:
	if _charge_travelled > 0.0 and is_on_wall():
		_end_attack(charge_recover)
		return false
	var step := charge_speed * delta
	velocity = _aim * charge_speed
	_charge_travelled += step
	var victim := _find_target()
	if not _charge_hit and victim and global_position.distance_to(victim.global_position) <= charge_hit_radius:
		_charge_hit = true
		victim.take_damage(charge_damage)
	if _charge_travelled >= charge_distance:
		_end_attack(charge_recover)
	return false


func _on_summon_circle(_hits: int, point: Vector2) -> void:
	if health.is_dead() or alive_summons().size() >= max_summons:
		return
	_summon(summon_scene, point)


func _draw() -> void:
	if _vulnerable:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0)
		draw_arc(Vector2(0, -30), 52.0 + 6.0 * pulse, 0.0, TAU, 40, Color(1.0, 0.95, 0.3, 0.6 + 0.3 * pulse), 3.0)
	if state == State.WINDUP and current_attack == &"charge":
		var progress := windup_progress()
		var length := charge_distance
		var side := _aim.orthogonal() * charge_hit_radius
		var lane := PackedVector2Array([side, _aim * length + side, _aim * length - side, -side])
		draw_colored_polygon(lane, Color(1.0, 0.3, 0.2, 0.12 + 0.18 * progress))
		draw_line(Vector2.ZERO, _aim * length * progress, Color(1.0, 0.4, 0.2, 0.8), 3.0)
		draw_polyline(lane + PackedVector2Array([lane[0]]), Color(1.0, 0.45, 0.25, 0.9), 2.0)
