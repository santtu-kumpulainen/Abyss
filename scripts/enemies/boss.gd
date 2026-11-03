class_name Boss
extends Enemy
## Boss enemy for the boss room. Chases slowly (with contact damage like Enemy)
## and uses telegraphed attacks, each with its own cooldown:
## - Volley: locks its aim on the target, shows an aim line for
##   `volley_windup` seconds, then fires `volley_count` bolts in a spread.
## - Slam: when the target is within `slam_trigger_range`, a growing circle of
##   `slam_radius` is shown for `slam_windup` seconds, then everything still
##   inside takes `slam_damage`.
## - Ring (enraged, at or below `enrage_health_ratio` HP): every other volley
##   becomes a ring of `ring_count` bolts in all directions.
## After each attack the boss pauses for `recover_time`. Timers advance in
## _physics_process, so they pause while the room keeps the boss inactive.
## Rewards use Enemy.xp_reward/currency_reward (granted once by the Dungeon
## when the room reports the death). Its own bolts are removed when it dies.

## Emitted when an attack's telegraph starts (&"volley", &"ring" or &"slam").
signal attack_started(attack: StringName)
## Emitted when a telegraphed attack resolves; `hit` tells if a slam hit.
signal attack_resolved(attack: StringName, hit: bool)

enum Phase { CHASE, WINDUP, RECOVER }

@export var display_name: String = "Abyss Warden"
## Seconds after activation before the first attack.
@export var opening_delay: float = 1.5
## Pause after each attack.
@export var recover_time: float = 0.6
## Spawn point offset from the feet for bolts.
@export var muzzle_offset := Vector2(0, -40)

@export_group("Volley")
## Spell used for the bolts (scene, art, collision radius, lifetime).
@export var projectile: Spell
@export var volley_damage: float = 10.0
@export var volley_speed: float = 230.0
@export var volley_count: int = 3
@export var volley_spread_degrees: float = 14.0
@export var volley_windup: float = 0.7
@export var volley_cooldown: float = 2.4
@export var volley_range: float = 560.0

@export_group("Slam")
@export var slam_damage: float = 22.0
@export var slam_radius: float = 120.0
## The slam is only started when the target is this close.
@export var slam_trigger_range: float = 110.0
@export var slam_windup: float = 0.9
@export var slam_cooldown: float = 4.0

@export_group("Ring")
## Health ratio at or below which the boss is enraged and alternates volleys with rings.
@export var enrage_health_ratio: float = 0.5
@export var ring_count: int = 10

var phase: Phase = Phase.CHASE
## Attack being telegraphed (&"" when none).
var current_attack: StringName = &""

var _spell: Spell
var _phase_left := 0.0
var _volley_left := 0.0
var _slam_left := 0.0
var _aim := Vector2.DOWN
var _next_ranged_is_ring := false
var _slam_flash := 0.0


func _ready() -> void:
	super._ready()
	var name_label := get_node_or_null(^"BossBar/NameLabel") as Label
	if name_label:
		name_label.text = display_name
	_volley_left = opening_delay
	_slam_left = opening_delay
	if projectile:
		_spell = projectile.duplicate() as Spell
		_spell.damage = volley_damage
		_spell.speed = volley_speed


func is_enraged() -> bool:
	return health.current <= health.max_health * enrage_health_ratio


func _physics_process(delta: float) -> void:
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	_volley_left = maxf(_volley_left - delta, 0.0)
	_slam_left = maxf(_slam_left - delta, 0.0)
	_slam_flash = maxf(_slam_flash - delta, 0.0)
	target = _find_target()
	velocity = Vector2.ZERO

	match phase:
		Phase.CHASE:
			_chase()
		Phase.WINDUP:
			_phase_left -= delta
			if _phase_left <= 0.0:
				_resolve_attack()
		Phase.RECOVER:
			_phase_left -= delta
			if _phase_left <= 0.0:
				phase = Phase.CHASE

	move_and_slide()
	_play(&"walk" if velocity != Vector2.ZERO else &"idle")
	queue_redraw()


## Starts telegraphing `attack` (&"volley", &"ring" or &"slam") right away,
## ignoring cooldowns and range. Returns false if busy or without a target.
func begin_attack(attack: StringName) -> bool:
	if phase != Phase.CHASE:
		return false
	if target == null:
		target = _find_target()
	if target == null:
		return false
	current_attack = attack
	phase = Phase.WINDUP
	match attack:
		&"slam":
			_phase_left = slam_windup
			_slam_left = slam_cooldown
		_:
			_phase_left = volley_windup
			_volley_left = volley_cooldown
			_aim = (target.global_position - (global_position + muzzle_offset)).normalized()
			if _aim == Vector2.ZERO:
				_aim = Vector2.DOWN
	_sprite.modulate = Color(1.0, 0.6, 0.3) if attack == &"slam" else Color(0.8, 0.6, 1.0)
	attack_started.emit(attack)
	return true


func _chase() -> void:
	if target == null:
		return
	var to_target := target.global_position - global_position
	var dist := to_target.length()
	facing = direction_name(to_target)
	if dist <= slam_trigger_range and _slam_left <= 0.0:
		begin_attack(&"slam")
	elif dist <= volley_range and _volley_left <= 0.0:
		var ring := is_enraged() and _next_ranged_is_ring
		_next_ranged_is_ring = is_enraged() and not ring
		begin_attack(&"ring" if ring else &"volley")
	elif dist > attack_range:
		velocity = to_target.normalized() * speed
	elif _attack_cooldown_left <= 0.0:
		_attack_cooldown_left = attack_cooldown
		target.take_damage(contact_damage)


func _resolve_attack() -> void:
	var attack := current_attack
	var hit := false
	match attack:
		&"slam":
			_slam_flash = 0.15
			var victim := _find_target()
			if victim and global_position.distance_to(victim.global_position) <= slam_radius:
				victim.take_damage(slam_damage)
				hit = true
		&"ring":
			var step := TAU / maxi(ring_count, 1)
			for i in ring_count:
				_fire(Vector2.RIGHT.rotated(step * (i + 0.5)))
		_:
			var spread := deg_to_rad(volley_spread_degrees)
			for i in volley_count:
				_fire(_aim.rotated((i - (volley_count - 1) / 2.0) * spread))
	current_attack = &""
	phase = Phase.RECOVER
	_phase_left = recover_time
	_sprite.modulate = Color.WHITE
	attack_resolved.emit(attack, hit)


func _fire(direction: Vector2) -> Projectile:
	if _spell == null or _spell.projectile_scene == null:
		return null
	var shot := _spell.projectile_scene.instantiate() as Projectile
	if shot == null:
		push_error("Boss: projectile_scene root is not a Projectile")
		return null
	shot.setup(_spell, direction, self)
	var container: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	container.add_child(shot)
	shot.global_position = global_position + muzzle_offset
	return shot


func _draw() -> void:
	if _slam_flash > 0.0:
		draw_circle(Vector2.ZERO, slam_radius, Color(1.0, 0.9, 0.7, 0.45))
	if phase != Phase.WINDUP:
		return
	var windup := slam_windup if current_attack == &"slam" else volley_windup
	var progress := clampf(1.0 - _phase_left / maxf(windup, 0.01), 0.0, 1.0)
	match current_attack:
		&"slam":
			draw_circle(Vector2.ZERO, slam_radius, Color(1.0, 0.25, 0.1, 0.12 + 0.18 * progress))
			draw_circle(Vector2.ZERO, slam_radius * progress, Color(1.0, 0.35, 0.1, 0.25))
			draw_arc(Vector2.ZERO, slam_radius, 0.0, TAU, 48, Color(1.0, 0.4, 0.2, 0.9), 2.0)
		&"ring":
			draw_arc(muzzle_offset, 30.0 + 40.0 * progress, 0.0, TAU, 32, Color(0.8, 0.5, 1.0, 0.9), 3.0)
		_:
			var spread := deg_to_rad(volley_spread_degrees)
			for i in volley_count:
				var dir := _aim.rotated((i - (volley_count - 1) / 2.0) * spread)
				draw_line(muzzle_offset, muzzle_offset + dir * 280.0, Color(0.8, 0.5, 1.0, 0.2 + 0.5 * progress), 2.0)


func _on_died() -> void:
	# Remove this boss's bolts so nothing hits the Mage after victory.
	var container: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	for child in container.get_children():
		if child is Projectile and (child as Projectile).source == self:
			child.queue_free()
	super._on_died()
