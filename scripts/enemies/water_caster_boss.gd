class_name WaterCasterBoss
extends Miniboss
## Miniboss version of the Water Caster (Issue #51, Stage 2). Keeps between
## `preferred_min` and `preferred_max` from the Mage and uses three attacks,
## one at a time (no new attack starts while its own wave is on the floor):
## - Big bolt: locks its aim and shows the aim lane (the bolt's full width) and
##   the water telegraph for `bolt_windup` s, then fires `bolt_burst` large
##   water bolts `bolt_burst_interval` s apart along that locked lane. The bolts
##   bounce off walls (the Spell's `max_bounces`, with a splash each time), then
##   end at the next wall or on the Mage with a big water impact. They also end
##   after the Spell's lifetime or when they leave the room floor.
## - Staggered zones: a short cast, then `zone_count` blue FloorHazards: one on
##   the Mage and the rest in a ring `zone_spacing` around it. Each erupts at a
##   different time (`zone_delay` + i x `zone_stagger`), the one on the Mage
##   first, so there is always a safe gap to step into and the zones that have
##   erupted are safe again.
## - Water wave: a WaveHazard lane across the whole room floor in one axis
##   (alternating horizontal / vertical), `wave_lane_fraction` of the floor
##   wide and centred on the Mage, travelling away from the caster's side. The
##   lane is telegraphed for `wave_telegraph` s (never shortened), then the
##   front sweeps it; a hit deals `wave_damage` and slows the Mage to
##   `wave_slow_factor` x walking speed for `wave_slow_duration` s. Stepping
##   out of the lane or dashing through the front avoids it. It only starts
##   while none of its zones is still waiting to erupt.
## Behaviour tiers (TIERS, by dungeon level: the Dungeon calls
## configure_for_level() -> apply_level_tier() at spawn) add zones,
## a bolt burst and zones after the wave, and shorten the cooldowns by
## `tier_cooldown_step` per tier. Damage and cooldowns also scale through
## _scale_attacks() (level and difficulty); telegraph times never scale.
## Look: the regular Water Caster's sprite frames and blue tint (scenes/enemies/
## water_caster.tscn, itself the Blood Monster frames tinted blue: the pack has
## no Water Caster art), as its giant version: a bigger `sprite_scale`, a deeper
## tint, a pulsing water aura at its feet and a cast pose (the sprite stretches
## up during attack windups). Hurt flash comes from Enemy; the death visual is
## the shared one until the death-animation stage.

## Behaviour tier table (Issue #51 D), index 0 = tier 1. Tier 1 = level 1,
## tier 2 = level 2, tier 3 = level 3 and later (the enhanced L4+ tier is Stage 4).
const TIERS: Array[Dictionary] = [
	{"zone_count": 3, "bolt_burst": 1, "wave_followup_zones": 0},
	{"zone_count": 4, "bolt_burst": 2, "wave_followup_zones": 0},
	{"zone_count": 5, "bolt_burst": 2, "wave_followup_zones": 2},
]

@export_group("Big bolt")
@export var projectile: Spell
@export var bolt_telegraph: EffectSheet
@export var bolt_damage: float = 14.0
@export var bolt_speed: float = 300.0
@export var bolt_windup: float = 0.7
@export var bolt_cooldown: float = 2.6
## Bolts per attack, all along the locked lane.
@export var bolt_burst: int = 1
@export var bolt_burst_interval: float = 0.3
@export var bolt_range: float = 700.0

@export_group("Staggered zones")
@export var zone_count: int = 3
@export var zone_radius: float = 95.0
## Telegraph of the first zone (on the Mage); each further zone erupts `zone_stagger` s later.
@export var zone_delay: float = 1.1
@export var zone_stagger: float = 0.4
## Distance of the ring zones from the Mage.
@export var zone_spacing: float = 210.0
@export var zone_damage: float = 12.0
@export var zone_windup: float = 0.6
@export var zone_cooldown: float = 6.5
@export var zone_color := Color(0.3, 0.65, 1.0)
## Played over each zone when it erupts (sized to the zone).
@export var zone_erupt_effect: EffectSheet

@export_group("Water wave")
## Cast pause of the caster (the lane is already telegraphed during it).
@export var wave_cast: float = 0.5
## Seconds the lane is telegraphed before the front starts moving (never scaled).
@export var wave_telegraph: float = 1.4
@export var wave_speed: float = 520.0
@export var wave_thickness: float = 80.0
## Width of the lane as a fraction of the floor across the travel axis (kept below 0.8).
@export_range(0.2, 0.8) var wave_lane_fraction: float = 0.5
@export var wave_damage: float = 12.0
@export var wave_slow_factor: float = 0.6
## Initial playtest target (Issue #51): 2.5 s.
@export var wave_slow_duration: float = 2.5
@export var wave_cooldown: float = 10.0
## Zones placed at the far end of the lane when the wave has passed (tier 3).
@export var wave_followup_zones: int = 0
@export var wave_color := Color(0.35, 0.7, 1.0)

@export_group("Movement")
@export var preferred_min: float = 220.0
@export var preferred_max: float = 380.0

@export_group("Look")
## Pulsing water aura under the caster's feet.
@export var aura_color := Color(0.35, 0.7, 1.0, 0.4)
@export var aura_radius: float = 48.0
## Cast pose: at the end of a windup the sprite is this much taller (and a bit narrower).
@export var cast_stretch: float = 0.08

@export_group("Tiers")
## Cooldown reduction per behaviour tier above 1 (0.1 = -10 % per tier).
@export var tier_cooldown_step: float = 0.1

## Behaviour tier in use (1..TIERS.size(), set by apply_level_tier()).
var behaviour_tier := 1

var _spell: Spell
var _bolt_left := 0.0
var _zone_left := 0.0
var _wave_left := 0.0
var _aim := Vector2.DOWN
var _shots_left := 0
var _shot_left := 0.0
var _waves_cast := 0
var _wave: WaveHazard
var _tier_applied := false
var _look_time := 0.0


func _ready() -> void:
	super._ready()
	_bolt_left = opening_delay
	_zone_left = opening_delay + 1.0
	_wave_left = opening_delay + 4.0
	if projectile:
		_spell = projectile.duplicate() as Spell
		_spell.damage = bolt_damage
		_spell.speed = bolt_speed


## Dungeon hook (spawn): the behaviour tier of dungeon level `level`.
func configure_for_level(level: int) -> void:
	apply_level_tier(level)


## Applies the behaviour tier of dungeon level `level` (level 1 -> tier 1,
## level 3+ -> tier 3). Only the first call has an effect.
func apply_level_tier(level: int) -> void:
	if _tier_applied:
		return
	_tier_applied = true
	behaviour_tier = clampi(level, 1, TIERS.size())
	var data: Dictionary = TIERS[behaviour_tier - 1]
	zone_count = data["zone_count"]
	bolt_burst = data["bolt_burst"]
	wave_followup_zones = data["wave_followup_zones"]
	var factor := maxf(1.0 - tier_cooldown_step * (behaviour_tier - 1), 0.1)
	bolt_cooldown *= factor
	zone_cooldown *= factor
	wave_cooldown *= factor


## Damage scales with damage; bolt speed and cooldowns with pace. Telegraphs
## and the wave's speed never scale.
func _scale_attacks(damage_mult: float, pace_mult: float) -> void:
	super._scale_attacks(damage_mult, pace_mult)
	bolt_damage *= damage_mult
	zone_damage *= damage_mult
	wave_damage *= damage_mult
	bolt_speed *= pace_mult
	var pace := maxf(pace_mult, 0.01)
	bolt_cooldown /= pace
	zone_cooldown /= pace
	wave_cooldown /= pace
	if _spell:
		_spell.damage = bolt_damage
		_spell.speed = bolt_speed


## Starts the big bolt telegraph now. Returns false if busy or without a target.
func begin_bolt() -> bool:
	if not _ready_to_attack():
		return false
	_bolt_left = bolt_cooldown
	_aim = (target.global_position - (global_position + muzzle_offset)).normalized()
	if _aim == Vector2.ZERO:
		_aim = Vector2.DOWN
	_begin(&"bolt", bolt_windup)
	if bolt_telegraph:
		PixelEffect.spawn(bolt_telegraph, self, global_position + muzzle_offset, bolt_windup, 90.0)
	return true


## Starts the staggered zone cast now. Returns false if busy or without a target.
func begin_zones() -> bool:
	if not _ready_to_attack():
		return false
	_zone_left = zone_cooldown
	_begin(&"zones", zone_windup)
	return true


## Starts the water wave now: its lane is telegraphed at once. Returns false if
## busy, without a target or while its zones are still waiting to erupt.
func begin_wave() -> bool:
	if not _ready_to_attack() or not wave_allowed():
		return false
	_wave_left = wave_cooldown
	var horizontal := _waves_cast % 2 == 0
	_waves_cast += 1
	var lane := wave_lane(horizontal)
	var to_target := target.global_position - global_position
	var dir := Vector2(signf(to_target.x) if to_target.x != 0.0 else 1.0, 0.0) if horizontal \
			else Vector2(0.0, signf(to_target.y) if to_target.y != 0.0 else 1.0)
	_wave = WaveHazard.spawn(_hazard_parent(), lane, dir, wave_telegraph, wave_speed,
			wave_damage, wave_slow_factor, wave_slow_duration, self, wave_thickness, wave_color)
	if wave_followup_zones > 0:
		_wave.finished.connect(_spawn_followup_zones.bind(_wave.lane, _wave.direction))
	_begin(&"wave", wave_cast)
	return true


## True while no zone of this caster is waiting to erupt and no wave of it is
## on the floor (the wave never stacks with other area attacks).
func wave_allowed() -> bool:
	if wave_active():
		return false
	for node in get_tree().get_nodes_in_group(&"floor_hazards"):
		var zone := node as FloorHazard
		if zone.source == self and not zone.is_queued_for_deletion() and zone.phase == FloorHazard.Phase.TELEGRAPH:
			return false
	return true


## True while this caster's wave is telegraphed or sweeping.
func wave_active() -> bool:
	return _wave != null and is_instance_valid(_wave) and not _wave.is_queued_for_deletion()


## The current (or last) wave, or null.
func current_wave() -> WaveHazard:
	return _wave if wave_active() else null


## Locked direction of the big bolt attack being telegraphed / fired.
func bolt_direction() -> Vector2:
	return _aim


## Global lane of a wave across the room floor: the full floor along the
## travel axis (`horizontal`: along x), `wave_lane_fraction` of it across,
## centred on the target and kept inside the floor.
func wave_lane(horizontal: bool) -> Rect2:
	var floor_rect := _arena()
	var at := target.global_position if target else global_position
	if horizontal:
		var h := floor_rect.size.y * clampf(wave_lane_fraction, 0.2, 0.8)
		var top := clampf(at.y - h * 0.5, floor_rect.position.y, floor_rect.end.y - h)
		return Rect2(floor_rect.position.x, top, floor_rect.size.x, h)
	var w := floor_rect.size.x * clampf(wave_lane_fraction, 0.2, 0.8)
	var left := clampf(at.x - w * 0.5, floor_rect.position.x, floor_rect.end.x - w)
	return Rect2(left, floor_rect.position.y, w, floor_rect.size.y)


## Centres of the staggered zones for the current target (global): the first
## on the Mage, the others evenly around it `zone_spacing` away, starting away
## from the caster and kept inside the floor. A ring zone that the floor edge
## would push onto the Mage's zone or another zone is turned to the nearest
## free angle instead, so the Mage's spot is safe once its zone has erupted.
func zone_targets() -> Array[Vector2]:
	var points: Array[Vector2] = []
	if target == null:
		return points
	var at := target.global_position
	points.append(at)
	var ring := maxi(zone_count - 1, 0)
	var base := (global_position - at).angle()
	for k in ring:
		points.append(_ring_point(at, base + PI / ring + TAU * k / ring, points))
	return points


## The floor-clamped point `zone_spacing` from `at` nearest to `angle` that
## keeps clear of `taken` (the Mage's zone and the zones placed so far); the
## clearest candidate if none is fully clear.
func _ring_point(at: Vector2, angle: float, taken: Array[Vector2]) -> Vector2:
	const STEPS := 24
	var best := _clamp_to_floor(at + Vector2.RIGHT.rotated(angle) * zone_spacing)
	var best_gap := -INF
	for i in STEPS:
		# 0, +1, -1, +2, -2 ... steps away from the intended angle.
		var step := (i + 1) / 2 * (1 if i % 2 == 1 else -1)
		var point := _clamp_to_floor(at + Vector2.RIGHT.rotated(angle + TAU * step / STEPS) * zone_spacing)
		var gap := INF
		for other in taken:
			gap = minf(gap, point.distance_to(other) - zone_radius * 2.0)
		if gap >= 0.0:
			return point
		if gap > best_gap:
			best_gap = gap
			best = point
	return best


func _ready_to_attack() -> bool:
	if state != State.CHASE or wave_active():
		return false
	if target == null:
		target = _find_target()
	return target != null


func _tick(delta: float) -> void:
	_look_time += delta
	_apply_pose()
	_bolt_left = maxf(_bolt_left - delta, 0.0)
	_zone_left = maxf(_zone_left - delta, 0.0)
	_wave_left = maxf(_wave_left - delta, 0.0)


func _choose(_delta: float, can_attack: bool) -> void:
	var to_target := target.global_position - global_position
	var dist := to_target.length()
	if can_attack and _wave_left <= 0.0 and wave_allowed():
		begin_wave()
	elif can_attack and _zone_left <= 0.0 and not wave_active():
		begin_zones()
	elif can_attack and _bolt_left <= 0.0 and dist <= bolt_range and not wave_active():
		begin_bolt()
	elif dist > preferred_max:
		velocity = to_target.normalized() * speed
	elif dist < preferred_min:
		velocity = -to_target.normalized() * speed
		if dist <= attack_range and _attack_cooldown_left <= 0.0:
			_attack_cooldown_left = attack_cooldown
			target.take_damage(contact_damage)


func _windup_finished(attack: StringName) -> void:
	match attack:
		&"bolt":
			_shots_left = maxi(bolt_burst, 1)
			_shot_left = 0.0
			_start_action()
			return
		&"zones":
			var points := zone_targets()
			for i in points.size():
				_spawn_zone(points[i], zone_delay + i * zone_stagger)
	_end_attack()


## Fires the burst along the locked lane, `bolt_burst_interval` s apart.
func _action(delta: float) -> bool:
	_shot_left -= delta
	if _shot_left <= 0.0 and _shots_left > 0:
		_fire(_aim)
		_shots_left -= 1
		_shot_left = bolt_burst_interval
	return _shots_left <= 0


func _spawn_zone(point: Vector2, delay: float) -> FloorHazard:
	var zone := FloorHazard.spawn(_hazard_parent(), point, zone_radius, delay, zone_damage, 0.0, self, zone_color)
	zone.erupt_effect = zone_erupt_effect
	return zone


## Tier 3: zones at the far end of the wave's lane once the wave has passed,
## spread across the lane and erupting one after the other.
func _spawn_followup_zones(lane: Rect2, dir: Vector2) -> void:
	if health.is_dead() or not is_inside_tree():
		return
	var count := wave_followup_zones
	var far := lane.get_center() + dir * (absf(dir.x) * lane.size.x + absf(dir.y) * lane.size.y) * 0.5
	var across := Vector2(absf(dir.y), absf(dir.x))
	var width := absf(across.x) * lane.size.x + absf(across.y) * lane.size.y
	for i in count:
		var offset := (i - (count - 1) / 2.0) * width / maxf(count, 1)
		_spawn_zone(_clamp_to_floor(far + across * offset), zone_delay + i * zone_stagger)


## The floor the caster fights on (Miniboss.floor_rect()), or a room-sized
## area centred on it when there is no floor at all.
func _arena() -> Rect2:
	var area := floor_rect()
	return area if area.has_area() else Rect2(global_position - Vector2(576, 324), Vector2(1152, 648))


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
	shot.bounds = _arena()
	return shot


## Sprite scale of the cast pose: stretched up with the windup, normal otherwise.
func pose_scale() -> Vector2:
	var base := Vector2.ONE * sprite_scale
	if state != State.WINDUP:
		return base
	var p := windup_progress()
	return base * Vector2(1.0 - cast_stretch * 0.6 * p, 1.0 + cast_stretch * p)


func _apply_pose() -> void:
	_sprite.scale = pose_scale()


func _draw() -> void:
	# Water aura at the feet (under the sprite, which is a child).
	var pulse := 0.5 + 0.5 * sin(_look_time * 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, aura_radius * (0.92 + 0.08 * pulse), Color(aura_color, aura_color.a * (0.6 + 0.4 * pulse)))
	draw_arc(Vector2.ZERO, aura_radius * (1.0 + 0.12 * pulse), 0.0, TAU, 40, Color(aura_color.lightened(0.4), 0.5 * (1.0 - pulse) + 0.2), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if state != State.WINDUP:
		return
	var progress := windup_progress()
	match current_attack:
		&"bolt":
			# The lane the bolt will fly along, as wide as the bolt itself.
			var width := (_spell.collision_radius * 2.0) if _spell else 40.0
			var end := muzzle_offset + _aim * 640.0
			draw_line(muzzle_offset, end, Color(wave_color, 0.12 + 0.2 * progress), width)
			draw_line(muzzle_offset, end, Color(wave_color.lightened(0.4), 0.35 + 0.55 * progress), 2.0)
		&"zones":
			var c := muzzle_offset + Vector2(0, -34)
			draw_arc(c, 14.0 + 10.0 * progress, 0.0, TAU, 24, Color(zone_color, 0.9), 3.0)
			for i in 3:
				var p := c + Vector2.UP.rotated(TAU * i / 3.0 + progress * TAU) * 20.0
				draw_circle(p, 4.0, Color(zone_color.lightened(0.4), 0.9))
		&"wave":
			draw_arc(Vector2.ZERO, 40.0 + 30.0 * progress, 0.0, TAU, 40, Color(wave_color, 0.9 - 0.5 * progress), 3.0)


func _on_died() -> void:
	WaveHazard.clear_from(get_tree(), self)
	super._on_died()
