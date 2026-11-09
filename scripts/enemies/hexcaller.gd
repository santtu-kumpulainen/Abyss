class_name Hexcaller
extends Miniboss
## Miniboss: area denial and repositioning (Issue #43). Keeps between
## `preferred_min` and `preferred_max` from the Mage.
## - Hex zones: a short cast (glyph over her head), then `hex_count`
##   FloorHazards: one on the Mage, one where the Mage is heading
##   (`hex_lead_time` s ahead) and one to the side. Each telegraphs for
##   `hex_delay` s, erupts for `hex_damage`, then lingers `hex_lifetime` s
##   pulsing every `hex_pulse` s, closing off parts of the floor.
## - Fan: locks its aim and shows `fan_count` aim lines for `fan_windup` s,
##   then fires that many bolts `fan_spread_degrees` apart.
## - Blink: once the Mage has stayed within `blink_trigger` for `blink_hold`
##   s, it flickers for `blink_windup` s with a marker on its destination (the
##   room SpawnPoint farthest from the Mage), then teleports there.

@export_group("Fan")
@export var projectile: Spell
@export var fan_damage: float = 9.0
@export var fan_speed: float = 240.0
@export var fan_count: int = 3
@export var fan_spread_degrees: float = 16.0
@export var fan_windup: float = 0.75
@export var fan_cooldown: float = 2.6
@export var fan_range: float = 560.0

@export_group("Hex")
@export var hex_count: int = 3
@export var hex_radius: float = 72.0
@export var hex_delay: float = 1.2
@export var hex_damage: float = 10.0
@export var hex_lifetime: float = 3.0
@export var hex_pulse: float = 1.0
@export var hex_windup: float = 0.6
@export var hex_cooldown: float = 6.0
@export var hex_lead_time: float = 0.8
## Side offset of the third zone.
@export var hex_spread: float = 150.0
@export var hex_color := Color(0.75, 0.35, 1.0)

@export_group("Movement")
@export var preferred_min: float = 230.0
@export var preferred_max: float = 380.0

@export_group("Blink")
@export var blink_trigger: float = 150.0
@export var blink_hold: float = 0.7
@export var blink_windup: float = 0.65
@export var blink_cooldown: float = 5.0

var _spell: Spell
var _fan_left := 0.0
var _hex_left := 0.0
var _blink_left := 0.0
var _close_time := 0.0
var _aim := Vector2.DOWN
var _blink_to := Vector2.ZERO


func _ready() -> void:
	super._ready()
	_fan_left = opening_delay
	_hex_left = opening_delay + 0.8
	if projectile:
		_spell = projectile.duplicate() as Spell
		_spell.damage = fan_damage
		_spell.speed = fan_speed


## Bolt and hex damage scale with damage; bolt speed and cooldowns with pace.
func _scale_attacks(damage_mult: float, pace_mult: float) -> void:
	super._scale_attacks(damage_mult, pace_mult)
	fan_damage *= damage_mult
	hex_damage *= damage_mult
	fan_speed *= pace_mult
	fan_cooldown /= maxf(pace_mult, 0.01)
	hex_cooldown /= maxf(pace_mult, 0.01)
	blink_cooldown /= maxf(pace_mult, 0.01)
	if _spell:
		_spell.damage = fan_damage
		_spell.speed = fan_speed


## Starts the fan telegraph now. Returns false if busy or without a target.
func begin_fan() -> bool:
	if not _ready_to_attack():
		return false
	_fan_left = fan_cooldown
	_aim = ((target.global_position) - (global_position + muzzle_offset)).normalized()
	if _aim == Vector2.ZERO:
		_aim = Vector2.DOWN
	_begin(&"fan", fan_windup)
	return true


## Starts the hex cast now. Returns false if busy or without a target.
func begin_hex() -> bool:
	if not _ready_to_attack():
		return false
	_hex_left = hex_cooldown
	_begin(&"hex", hex_windup)
	return true


## Starts the blink telegraph now. Returns false if busy or without a target.
func begin_blink() -> bool:
	if not _ready_to_attack():
		return false
	_blink_left = blink_cooldown
	_close_time = 0.0
	_blink_to = _blink_destination()
	_begin(&"blink", blink_windup)
	return true


## Bolt directions of the fan being telegraphed.
func fan_directions() -> Array[Vector2]:
	var dirs: Array[Vector2] = []
	var spread := deg_to_rad(fan_spread_degrees)
	for i in fan_count:
		dirs.append(_aim.rotated((i - (fan_count - 1) / 2.0) * spread))
	return dirs


## Where the current blink will land (global).
func blink_destination() -> Vector2:
	return _blink_to


## Centres of the hex zones for the current target (global).
func hex_targets() -> Array[Vector2]:
	var points: Array[Vector2] = []
	if target == null:
		return points
	var at := target.global_position
	var moving := Vector2.ZERO
	if target is CharacterBody2D:
		moving = (target as CharacterBody2D).velocity
	var ahead := at + moving * hex_lead_time
	if ahead.distance_to(at) < hex_radius:
		# Standing still: the second zone cuts off the way back to the Hexcaller instead.
		ahead = at + (global_position - at).normalized() * hex_radius * 1.6
	var side := (ahead - at).normalized().orthogonal()
	if side == Vector2.ZERO:
		side = Vector2.RIGHT
	# The zone on the Mage stays put; the others are kept inside the floor.
	points.append(at)
	points.append(_clamp_to_floor(ahead))
	points.append(_clamp_to_floor(at + side * hex_spread))
	return points.slice(0, hex_count)


func _ready_to_attack() -> bool:
	if state != State.CHASE:
		return false
	if target == null:
		target = _find_target()
	return target != null


func _tick(delta: float) -> void:
	_fan_left = maxf(_fan_left - delta, 0.0)
	_hex_left = maxf(_hex_left - delta, 0.0)
	_blink_left = maxf(_blink_left - delta, 0.0)


func _choose(delta: float, can_attack: bool) -> void:
	var to_target := target.global_position - global_position
	var dist := to_target.length()
	_close_time = _close_time + delta if dist <= blink_trigger else maxf(_close_time - delta, 0.0)
	if can_attack and _close_time >= blink_hold and _blink_left <= 0.0:
		begin_blink()
	elif can_attack and _hex_left <= 0.0:
		begin_hex()
	elif can_attack and _fan_left <= 0.0 and dist <= fan_range:
		begin_fan()
	elif dist > preferred_max:
		velocity = to_target.normalized() * speed
	elif dist < preferred_min:
		velocity = -to_target.normalized() * speed
		if dist <= attack_range and _attack_cooldown_left <= 0.0:
			_attack_cooldown_left = attack_cooldown
			target.take_damage(contact_damage)


func _windup_finished(attack: StringName) -> void:
	match attack:
		&"fan":
			for dir in fan_directions():
				_fire(dir)
		&"hex":
			var room := _room()
			for point in hex_targets():
				var zone := FloorHazard.spawn(room if room else get_parent(), point, hex_radius, hex_delay, hex_damage, hex_lifetime, self, hex_color)
				zone.pulse_interval = hex_pulse
		&"blink":
			global_position = _blink_to
	_end_attack()


## Room SpawnPoint (global) farthest from the target; stays put without points.
func _blink_destination() -> Vector2:
	var room := _room()
	var best := global_position
	if room == null or not room.has_node(^"SpawnPoints") or target == null:
		return best
	var best_dist := -1.0
	for point: Node2D in room.get_node(^"SpawnPoints").get_children():
		var d := point.global_position.distance_to(target.global_position)
		if d > best_dist:
			best_dist = d
			best = point.global_position
	return best


func _fire(direction: Vector2) -> Projectile:
	if _spell == null or _spell.projectile_scene == null:
		return null
	var shot := _spell.projectile_scene.instantiate() as Projectile
	if shot == null:
		return null
	shot.setup(_spell, direction, self)
	var container: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	container.add_child(shot)
	shot.global_position = global_position + muzzle_offset
	return shot


func _draw() -> void:
	if state != State.WINDUP:
		return
	var progress := windup_progress()
	match current_attack:
		&"fan":
			for dir in fan_directions():
				draw_line(muzzle_offset, muzzle_offset + dir * 300.0, Color(0.8, 0.5, 1.0, 0.25 + 0.55 * progress), 2.0)
		&"hex":
			var c := muzzle_offset + Vector2(0, -30)
			draw_arc(c, 14.0 + 10.0 * progress, 0.0, TAU, 24, Color(hex_color, 0.9), 3.0)
			for i in 3:
				var dir := Vector2.UP.rotated(TAU * i / 3.0 + progress * TAU)
				draw_line(c, c + dir * 18.0, Color(hex_color.lightened(0.4), 0.9), 2.0)
		&"blink":
			# Flicker in place and mark the landing spot.
			modulate.a = 0.35 + 0.65 * absf(sin(progress * PI * 6.0))
			var dest := _blink_to - global_position
			draw_arc(dest, 30.0, 0.0, TAU, 32, Color(0.6, 0.9, 1.0, 0.8), 2.0)
			draw_line(dest + Vector2(-10, 0), dest + Vector2(10, 0), Color(0.6, 0.9, 1.0, 0.8), 2.0)
			draw_line(dest + Vector2(0, -10), dest + Vector2(0, 10), Color(0.6, 0.9, 1.0, 0.8), 2.0)


func _end_attack(pause: float = -1.0) -> void:
	modulate.a = 1.0
	super._end_attack(pause)
