class_name Boss
extends Enemy
## Boss enemy for the boss room. Chases slowly (with contact damage like Enemy)
## and uses telegraphed attacks, each with its own cooldown:
## - Volley: locks its aim on the target, shows aim lines for
##   `volley_windup` seconds, then fires a spread of bolts.
## - Slam: when the target is within `slam_trigger_range`, a growing circle of
##   exactly `slam_radius` is shown for the phase's wind-up, then everything
##   whose origin is still inside takes `slam_damage`.
## - Ring (phase 3): every other volley becomes a ring of `ring_count` bolts.
## Health phases: phase 1 above `phase_thresholds[0]` of max HP, phase 2 at or
## below it, phase 3 at or below `phase_thresholds[1]`. Phases only go up, one
## step at a time (a big hit emits every skipped phase in order), and each is
## entered once. Volley size/spread and slam wind-up come from the per-phase
## arrays; an attack keeps the values it started its telegraph with.
## After each attack the boss pauses for `recover_time`. Timers advance in
## _physics_process, so they pause while the room keeps the boss inactive.
## Rewards use Enemy.xp_reward/currency_reward (granted once by the Dungeon
## when the room reports the death). Its own bolts are removed when it dies.

## Emitted when an attack's telegraph starts (&"volley", &"ring" or &"slam").
signal attack_started(attack: StringName)
## Emitted when a telegraphed attack resolves; `hit` tells if a slam hit.
signal attack_resolved(attack: StringName, hit: bool)
## Emitted once per health phase entered (2, then 3).
signal phase_changed(phase: int)

enum State { CHASE, WINDUP, RECOVER }

const PHASE_FLASH_TIME := 0.6

@export var display_name: String = "Abyss Warden"
## Seconds after activation before the first attack.
@export var opening_delay: float = 1.5
## Pause after each attack.
@export var recover_time: float = 0.6
## Spawn point offset from the feet for bolts.
@export var muzzle_offset := Vector2(0, -40)

@export_group("Phases")
## Max-HP ratios at or below which phase 2 and phase 3 start.
@export var phase_thresholds := PackedFloat32Array([0.66, 0.33])
## Sprite tint per phase (self_modulate).
@export var phase_tints := PackedColorArray([Color(0.75, 0.55, 1.0), Color(0.95, 0.45, 0.8), Color(1.0, 0.35, 0.35)])

@export_group("Volley")
## Spell used for the bolts (scene, art, collision radius, lifetime).
@export var projectile: Spell
@export var volley_damage: float = 10.0
## Each volley / ring bolt that hits deals this fraction of the target's current
## max HP (so it scales with Vitality, level-ups and items). It replaces
## volley_damage on a hit and ignores difficulty, level, Pact and global enemy
## damage multipliers; targets without a Health fall back to volley_damage.
@export var volley_max_hp_fraction: float = 0.25
@export var volley_speed: float = 230.0
## Bolts per volley in phases 1-3. Even counts leave a gap on the aim line.
@export var volley_counts := PackedInt32Array([3, 5, 8])
## Degrees between neighbouring bolts in phases 1-3.
@export var volley_spreads_degrees := PackedFloat32Array([14.0, 14.0, 12.0])
@export var volley_windup: float = 0.7
@export var volley_cooldown: float = 2.4
@export var volley_range: float = 560.0

@export_group("Slam")
## Ring shown over the slam radius while the slam winds up (optional).
@export var slam_telegraph: EffectSheet
@export var slam_damage: float = 22.0
@export var slam_radius: float = 200.0
## The slam is only started when the target is this close.
@export var slam_trigger_range: float = 110.0
## Slam telegraph seconds in phases 1-3 (long enough to walk out of the radius).
@export var slam_windups := PackedFloat32Array([1.4, 1.5, 1.6])
@export var slam_cooldown: float = 4.0

@export_group("Ring")
@export var ring_count: int = 10

## Attack state.
var state: State = State.CHASE
## Health phase, 1-3.
var phase: int = 1
## Attack being telegraphed (&"" when none).
var current_attack: StringName = &""

var _spell: Spell
var _state_left := 0.0
var _volley_left := 0.0
var _slam_left := 0.0
var _aim := Vector2.DOWN
var _next_ranged_is_ring := false
var _slam_flash := 0.0
var _phase_flash := 0.0
## Values locked in when the current telegraph started.
var _windup_total := 0.0
var _volley_count := 0
var _volley_spread := 0.0


func _ready() -> void:
	super._ready()
	health.damaged.connect(func(_amount: float, _current: float) -> void: _update_phase())
	_apply_phase_visuals()
	_volley_left = opening_delay
	_slam_left = opening_delay
	if projectile:
		_spell = projectile.duplicate() as Spell
		_spell.damage = volley_damage
		_spell.speed = volley_speed


## Volley/ring and slam damage scale with damage; attack cooldowns and bolt
## speed with pace. Telegraph wind-ups are kept so attacks stay readable.
func _scale_attacks(damage_mult: float, pace_mult: float) -> void:
	super._scale_attacks(damage_mult, pace_mult)
	volley_damage *= damage_mult
	slam_damage *= damage_mult
	volley_speed *= pace_mult
	volley_cooldown /= maxf(pace_mult, 0.01)
	slam_cooldown /= maxf(pace_mult, 0.01)
	if _spell:
		_spell.damage = volley_damage
		_spell.speed = volley_speed


## Health phase (1-3) for a current/max HP ratio.
func phase_for_ratio(ratio: float) -> int:
	var result := 1
	for threshold in phase_thresholds:
		if ratio <= threshold:
			result += 1
	return result


func current_volley_count() -> int:
	return volley_counts[clampi(phase - 1, 0, volley_counts.size() - 1)]


func current_volley_spread_degrees() -> float:
	return volley_spreads_degrees[clampi(phase - 1, 0, volley_spreads_degrees.size() - 1)]


func current_slam_windup() -> float:
	return slam_windups[clampi(phase - 1, 0, slam_windups.size() - 1)]


func _physics_process(delta: float) -> void:
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	_volley_left = maxf(_volley_left - delta, 0.0)
	_slam_left = maxf(_slam_left - delta, 0.0)
	_slam_flash = maxf(_slam_flash - delta, 0.0)
	_phase_flash = maxf(_phase_flash - delta, 0.0)
	target = _find_target()
	velocity = Vector2.ZERO

	match state:
		State.CHASE:
			_chase()
		State.WINDUP:
			_state_left -= delta
			if _state_left <= 0.0:
				_resolve_attack()
		State.RECOVER:
			_state_left -= delta
			if _state_left <= 0.0:
				state = State.CHASE

	move_and_slide()
	_play(&"walk" if velocity != Vector2.ZERO else &"idle")
	queue_redraw()


## Starts telegraphing `attack` (&"volley", &"ring" or &"slam") right away,
## ignoring cooldowns and range. Returns false if busy or without a target.
func begin_attack(attack: StringName) -> bool:
	if state != State.CHASE:
		return false
	if target == null:
		target = _find_target()
	if target == null:
		return false
	current_attack = attack
	state = State.WINDUP
	match attack:
		&"slam":
			_state_left = current_slam_windup()
			_slam_left = slam_cooldown
			PixelEffect.spawn(slam_telegraph, self, global_position, _state_left, slam_radius * 2.0)
		_:
			_state_left = volley_windup
			_volley_left = volley_cooldown
			_volley_count = current_volley_count()
			_volley_spread = deg_to_rad(current_volley_spread_degrees())
			_aim = (target.global_position - (global_position + muzzle_offset)).normalized()
			if _aim == Vector2.ZERO:
				_aim = Vector2.DOWN
	_windup_total = _state_left
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
		var ring := phase >= 3 and _next_ranged_is_ring
		_next_ranged_is_ring = phase >= 3 and not ring
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
			for dir in _volley_directions():
				_fire(dir)
	current_attack = &""
	state = State.RECOVER
	_state_left = recover_time
	_sprite.modulate = Color.WHITE
	attack_resolved.emit(attack, hit)


## Bolt directions of the volley being telegraphed, centred on the locked aim.
func _volley_directions() -> Array[Vector2]:
	var dirs: Array[Vector2] = []
	for i in _volley_count:
		dirs.append(_aim.rotated((i - (_volley_count - 1) / 2.0) * _volley_spread))
	return dirs


## Steps through every phase the current HP has reached, in order, once each.
func _update_phase() -> void:
	if health.is_dead():
		return
	var reached := phase_for_ratio(health.current / maxf(health.max_health, 1.0))
	while phase < reached:
		phase += 1
		_phase_flash = PHASE_FLASH_TIME
		_apply_phase_visuals()
		_sprite.modulate = Color(2.0, 2.0, 2.0)
		create_tween().tween_property(_sprite, ^"modulate", Color.WHITE, 0.4)
		phase_changed.emit(phase)


func _apply_phase_visuals() -> void:
	if not phase_tints.is_empty():
		_sprite.self_modulate = phase_tints[clampi(phase - 1, 0, phase_tints.size() - 1)]
	var name_label := get_node_or_null(^"BossBar/NameLabel") as Label
	if name_label:
		name_label.text = "%s  -  Phase %d" % [display_name, phase]


func _fire(direction: Vector2) -> Projectile:
	if _spell == null or _spell.projectile_scene == null:
		return null
	var shot := _spell.projectile_scene.instantiate() as Projectile
	if shot == null:
		push_error("Boss: projectile_scene root is not a Projectile")
		return null
	shot.setup(_spell, direction, self)
	shot.max_hp_fraction = volley_max_hp_fraction
	var container: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	container.add_child(shot)
	shot.global_position = global_position + muzzle_offset
	return shot


func _draw() -> void:
	if _slam_flash > 0.0:
		draw_circle(Vector2.ZERO, slam_radius, Color(1.0, 0.9, 0.7, 0.45))
	if _phase_flash > 0.0:
		var t := 1.0 - _phase_flash / PHASE_FLASH_TIME
		draw_arc(muzzle_offset, 40.0 + 160.0 * t, 0.0, TAU, 48, Color(1.0, 0.85, 1.0, 1.0 - t), 4.0)
	if state != State.WINDUP:
		return
	var progress := clampf(1.0 - _state_left / maxf(_windup_total, 0.01), 0.0, 1.0)
	match current_attack:
		&"slam":
			# Same radius and centre (the feet) as the damage check in _resolve_attack().
			draw_circle(Vector2.ZERO, slam_radius, Color(1.0, 0.25, 0.1, 0.12 + 0.18 * progress))
			draw_circle(Vector2.ZERO, slam_radius * progress, Color(1.0, 0.35, 0.1, 0.25))
			draw_arc(Vector2.ZERO, slam_radius, 0.0, TAU, 64, Color(1.0, 0.4, 0.2, 0.9), 2.0)
		&"ring":
			draw_arc(muzzle_offset, 30.0 + 40.0 * progress, 0.0, TAU, 32, Color(0.8, 0.5, 1.0, 0.9), 3.0)
		_:
			for dir in _volley_directions():
				draw_line(muzzle_offset, muzzle_offset + dir * 280.0, Color(0.8, 0.5, 1.0, 0.2 + 0.5 * progress), 2.0)


func _on_died() -> void:
	# Remove this boss's bolts so nothing hits the Mage after victory.
	var container: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	for child in container.get_children():
		if child is Projectile and (child as Projectile).source == self:
			child.queue_free()
	super._on_died()
