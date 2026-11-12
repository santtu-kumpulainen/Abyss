class_name Goblin
extends TelegraphedMelee
## Giant Goblin (Issue #47): a standard pursuer whose attack cycle is
##   `swings_before_special` normal sword swings -> telegraphed special strike
##   -> recovery -> normal swings again.
##
## Normal swing: when the Mage is within `attack_range` and the attack cooldown
## is ready, the goblin stops for `swing_windup` s (an outlined steel-blue
## sector marks the danger area), then hits once for `contact_damage` if the
## Mage is inside the swing sector (`swing_reach` radius, +-`swing_half_angle`
## around the aim locked at the windup start). A `swing_slash_time` s sword trail
## then sweeps across exactly that sector (with an impact flash on a hit), and
## the goblin stands for `swing_recover` s. `attack_cooldown` runs from the swing start.
## Every swing counts, hit or miss. Once `swings_before_special` swings are done
## it swings no more until the special has been used.
##
## Special strike: starts once the swings are done and the Mage is within
## `special_max_range`. The goblin stops and shows the strike rectangle in red
## for the whole `special_windup`: it starts at the goblin's feet, is
## 2*`strike_half_width` wide and `strike_length` + the lunge long. The lunge
## (0..`lunge_max`) carries the goblin to `lunge_stop` px short of the Mage, so a
## Mage next to it gets the in-place strike and a Mage further away gets a lunging
## one. Windup timeline (Issue #51, same on every difficulty, never scaled by pace):
##   tracking      `special_track_time` s   - aim and lunge follow the Mage (thin outline)
##   locked        `special_lock_time` s    - aim locked (bold outline, the fill sweeps to the tip)
##   anticipation  `special_anticipation` s - still locked and standing still; the whole
##                                            rectangle pulses bright (is_anticipating())
## so special_windup = their sum (0.95 s) and the Mage has 0.65 s after the lock.
## In the `strike_active` s window the goblin lunges along the locked aim and the
## Mage takes `special_damage` once if its position is inside the locked
## rectangle; a gold slash covers exactly that rectangle and fades over
## `slash_fade` s (the fade deals no damage). Leaving the rectangle after the
## lock (e.g. a sidestep or a Dash) avoids the hit. Walking straight away from
## the lock on also escapes now, but a Mage that only starts to leave during the
## anticipation is still hit.
##
## Anti-kiting: after `kite_patience` s of chasing a Mage outside its swing range
## without swinging, the goblin skips its remaining swings, so the special
## follows as soon as the Mage is within `special_max_range`. Kiting therefore
## no longer avoids the attack cycle.
##
## The Dungeon sets `swings_before_special` from RunState.goblin_swings_before_special()
## (difficulty x dungeon level, always 1-3). Only giant_goblin.tscn uses this
## script (the biome-2 Blood Monster replaces the whole scene).

## Normal swings before each special (1-3; set per run by the Dungeon).
@export_range(1, 3) var swings_before_special: int = 3

@export_group("Normal swing")
## Telegraph time of a normal swing (not scaled by pace).
@export var swing_windup: float = 0.25
## Pause after a normal swing.
@export var swing_recover: float = 0.3
## Radius of the swing sector from the goblin's feet (was 48).
@export var swing_reach: float = 60.0
## Half the opening angle of the swing sector, in degrees (70 = a 140 degree arc; was 60).
@export var swing_half_angle: float = 70.0
## Seconds the swing's sword trail is shown after the hit check (visual only).
@export var swing_slash_time: float = 0.18

@export_group("Sword strike")
## Seconds the strike can hit after the windup (unchanged by the 1.35x area).
@export var strike_active: float = 0.12
## Reach of the strike rectangle from the goblin's feet along the aim
## (1.35 x the original 80).
@export var strike_length: float = 108.0
## Half the width of the strike rectangle (1.35 x the original 18).
@export var strike_half_width: float = 24.3
## Seconds the strike's slash stays visible after the active window (visual only).
@export var slash_fade: float = 0.2
## Most distance the strike lunges forward during its active window.
@export var lunge_max: float = 150.0
## The lunge stops this far short of the Mage's position at the lock, so the
## blade still reaches strike_length - lunge_stop past it.
@export var lunge_stop: float = 30.0
## Seconds at the start of the windup during which aim and lunge follow the Mage
## (never scaled by pace).
@export var special_track_time: float = 0.3
## Seconds of the locked warning after the tracking (never scaled by pace).
@export var special_lock_time: float = 0.35
## Seconds of the anticipation after the locked warning, right before the strike:
## the goblin stands still and the locked rectangle pulses (never scaled by pace).
@export var special_anticipation: float = 0.3

@export_group("Anti-kiting")
## Seconds of chasing a Mage outside swing range without swinging before the
## remaining swings are skipped and the special becomes ready.
@export var kite_patience: float = 2.0

enum Swing { NONE, WINDUP, RECOVER }

## Float slack so the lock lands on the frame where special_track_time is reached.
const TIME_EPSILON := 0.0001

## Normal swings done since the last special.
var swings_done := 0
## Total normal swings (hit or miss) since the goblin was created.
var swings_total := 0
var swing_phase: Swing = Swing.NONE
## Aim of the current / last normal swing (unit vector).
var swing_aim := Vector2.DOWN

var _swing_left := 0.0
var _swing_slash_left := 0.0
## Local position of the last swing's hit (impact flash), when it hit.
var _swing_hit := false
var _swing_hit_pos := Vector2.ZERO
## True if the current / last special skipped swings because the Mage kept its distance.
var special_from_kiting := false
## Locked lunge distance of the current / last special.
var lunge := 0.0

var _active_left := 0.0
var _slash_left := 0.0
var _struck := false
var _kite_left := 0.0
var _track_left := 0.0
var _lunged := 0.0
var _strike_origin := Vector2.ZERO
var _origin_locked := false


func _ready() -> void:
	_sync_windup()
	super._ready()
	_kite_left = kite_patience


## special_windup is always tracking + locked warning + anticipation.
func _sync_windup() -> void:
	special_windup = special_track_time + special_lock_time + special_anticipation


## Pace (and any future tempo scaling) never shortens the warning intervals.
func _scale_attacks(damage_mult: float, pace_mult: float) -> void:
	super._scale_attacks(damage_mult, pace_mult)
	_sync_windup()


## Post-attack pauses: the special's recovery (TelegraphedMelee) and the swing
## recovery. Tracking, lock, anticipation and strike times are never scaled.
func _scale_recovery(mult: float) -> void:
	super._scale_recovery(mult)
	swing_recover /= mult


## True if global `pos` is inside the strike rectangle (the telegraphed area).
func in_strike_area(pos: Vector2) -> bool:
	var local := pos - strike_origin()
	var along := local.dot(aim)
	return along >= 0.0 and along <= strike_reach() and absf(local.dot(aim.orthogonal())) <= strike_half_width


## Global start of the strike rectangle: where the goblin stood when the special
## began (it lunges away from it), else its current position.
func strike_origin() -> Vector2:
	return _strike_origin if _origin_locked else global_position


## Length of the strike rectangle: the blade plus the lunge.
func strike_reach() -> float:
	return strike_length + lunge


## True once the special's aim and lunge are locked (after special_track_time of the windup).
func is_aim_locked() -> bool:
	return phase != Phase.CHASE and _track_left <= TIME_EPSILON


## No knockback during the swing telegraph either (besides the special's phases).
func can_be_knocked_back() -> bool:
	return super.can_be_knocked_back() and swing_phase != Swing.WINDUP


## True during the anticipation: the last `special_anticipation` s of the windup.
func is_anticipating() -> bool:
	return phase == Phase.WINDUP and is_aim_locked() and _phase_left <= special_anticipation


## True if global `pos` is inside the current normal swing's sector.
func in_swing_area(pos: Vector2) -> bool:
	var local := pos - global_position
	if local.length() > swing_reach:
		return false
	return local.length() < 0.001 or absf(rad_to_deg(swing_aim.angle_to(local))) <= swing_half_angle


## Corners of the strike rectangle (local), shared by the telegraph, the slash and in_strike_area().
func strike_polygon() -> PackedVector2Array:
	var origin := strike_origin() - global_position
	var side := aim.orthogonal() * strike_half_width
	var tip := aim * strike_reach()
	return PackedVector2Array([origin + side, origin + tip + side, origin + tip - side, origin - side])


## Normal swing sector (local; the drawn cue and in_swing_area() use the same
## radius and angles; the arc is drawn with 12 segments).
func swing_polygon() -> PackedVector2Array:
	var start := swing_aim.angle() - deg_to_rad(swing_half_angle)
	var end := swing_aim.angle() + deg_to_rad(swing_half_angle)
	var points := PackedVector2Array([Vector2.ZERO])
	for i in 13:
		points.append(Vector2.from_angle(lerpf(start, end, i / 12.0)) * swing_reach)
	return points


## True while a normal swing or the special is in progress.
func is_attacking() -> bool:
	return swing_phase != Swing.NONE or phase != Phase.CHASE


func _special_ready() -> bool:
	return swing_phase == Swing.NONE and swings_done >= swings_before_special



func _lock_special() -> void:
	swings_done = 0
	_kite_left = kite_patience
	_strike_origin = global_position
	_origin_locked = true
	_track_left = special_track_time
	_update_lunge(target)


## Aims the special at `victim` and sets the lunge for its distance (only while tracking).
func _update_lunge(victim: Node2D) -> void:
	if victim == null:
		return
	var to_victim := victim.global_position - _strike_origin
	if to_victim != Vector2.ZERO:
		aim = to_victim.normalized()
		facing = direction_name(aim)
	lunge = clampf(to_victim.length() - lunge_stop, 0.0, lunge_max)


## Normal behaviour: chase, then the normal swing cycle (replaces Enemy's instant contact hit).
func _pursue() -> void:
	var delta := get_physics_process_delta_time()
	match swing_phase:
		Swing.WINDUP:
			_swing_left -= delta
			if _swing_left <= 0.0:
				_resolve_swing()
		Swing.RECOVER:
			_swing_left -= delta
			if _swing_left <= 0.0:
				swing_phase = Swing.NONE
		Swing.NONE:
			var to_target := target.global_position - global_position
			facing = direction_name(to_target)
			if to_target.length() > attack_range:
				velocity = to_target.normalized() * speed
				# Kept at a distance: after kite_patience the remaining swings are skipped.
				_kite_left -= delta
				if _kite_left <= 0.0 and swings_done < swings_before_special:
					swings_done = swings_before_special
					special_from_kiting = true
			elif _attack_cooldown_left <= 0.0 and swings_done < swings_before_special:
				_start_swing(to_target)


func _start_swing(to_target: Vector2) -> void:
	swing_aim = to_target.normalized() if to_target != Vector2.ZERO else Vector2.DOWN
	facing = direction_name(swing_aim)
	swing_phase = Swing.WINDUP
	_swing_left = swing_windup
	_attack_cooldown_left = attack_cooldown
	_kite_left = kite_patience
	special_from_kiting = false


func _resolve_swing() -> void:
	var victim := _find_target()
	_swing_hit = victim != null and in_swing_area(victim.global_position)
	if _swing_hit:
		_swing_hit_pos = victim.global_position - global_position
		victim.take_damage(contact_damage)
		HitFeedback.knock(victim, victim.global_position - global_position)
	swings_done += 1
	swings_total += 1
	swing_phase = Swing.RECOVER
	_swing_left = swing_recover
	_swing_slash_left = swing_slash_time


func _start_active() -> void:
	_active_left = strike_active
	_slash_left = strike_active + slash_fade
	_struck = false
	_lunged = 0.0


func _special_active(delta: float) -> bool:
	# Lunge along the locked aim; the whole locked rectangle is the hit area.
	if _lunged < lunge and not (_lunged > 0.0 and is_on_wall()):
		var step := minf(lunge / maxf(strike_active, 0.01) * delta, lunge - _lunged)
		velocity = aim * step / maxf(delta, 0.0001)
		_lunged += step
	if not _struck:
		var victim := _find_target()
		if victim and in_strike_area(victim.global_position):
			_struck = true
			victim.take_damage(special_damage)
			HitFeedback.knock(victim, aim)
	_active_left -= delta
	return _active_left <= 0.0


func _physics_process(delta: float) -> void:
	_swing_slash_left = maxf(_swing_slash_left - delta, 0.0)
	_slash_left = maxf(_slash_left - delta, 0.0)
	if phase == Phase.WINDUP and _track_left > TIME_EPSILON:
		_update_lunge(_find_target())
		_track_left -= delta
	elif phase == Phase.CHASE and _slash_left <= 0.0:
		_origin_locked = false
		lunge = 0.0
	super._physics_process(delta)


func _draw() -> void:
	if phase == Phase.WINDUP:
		_draw_strike_telegraph()
	elif _slash_left > 0.0:
		_draw_strike_slash()
	if swing_phase == Swing.WINDUP:
		_draw_swing_warning(clampf(1.0 - _swing_left / maxf(swing_windup, 0.01), 0.0, 1.0))
	elif _swing_slash_left > 0.0:
		_draw_swing_slash(clampf(1.0 - _swing_slash_left / maxf(swing_slash_time, 0.01), 0.0, 1.0))


## Red strike rectangle: a thin outline while the aim still follows the Mage,
## then a bold outline with a fill sweeping towards the tip over the locked
## warning, then (anticipation) the full rectangle pulsing white-hot until the strike.
func _draw_strike_telegraph() -> void:
	var area := strike_polygon()
	var outline := area + PackedVector2Array([area[0]])
	draw_colored_polygon(area, Color(1.0, 0.3, 0.2, 0.1))
	if not is_aim_locked():
		draw_polyline(outline, Color(1.0, 0.45, 0.25, 0.5), 1.0)
		return
	if is_anticipating():
		var pulse := 0.5 + 0.5 * cos(TAU * 3.0 * (special_anticipation - _phase_left) / maxf(special_anticipation, 0.01))
		draw_colored_polygon(area, Color(1.0, 0.25 + 0.55 * pulse, 0.2 + 0.5 * pulse, 0.35 + 0.25 * pulse))
		draw_polyline(outline, Color(0.0, 0.0, 0.0, 0.6), 5.0)
		draw_polyline(outline, Color(1.0, 0.9 + 0.1 * pulse, 0.75 + 0.25 * pulse, 1.0), 3.0)
		return
	var progress := clampf(1.0 - (_phase_left - special_anticipation) / maxf(special_lock_time, 0.01), 0.0, 1.0)
	var origin := area[0] - aim.orthogonal() * strike_half_width
	var side := aim.orthogonal() * strike_half_width
	var reach := aim * strike_reach() * progress
	draw_colored_polygon(PackedVector2Array([origin + side, origin + reach + side, origin + reach - side, origin - side]),
			Color(1.0, 0.35, 0.2, 0.15 + 0.25 * progress))
	draw_polyline(outline, Color(0.0, 0.0, 0.0, 0.5), 4.0)
	draw_polyline(outline, Color(1.0, 0.45, 0.25, 0.95), 2.0)


## Gold sword slash over exactly the strike rectangle: a filled impact area, a
## blade streak along the aim to the tip and curved sweep lines across the width.
func _draw_strike_slash() -> void:
	var fade := clampf(_slash_left / maxf(strike_active + slash_fade, 0.01), 0.0, 1.0)
	var area := strike_polygon()
	var side := aim.orthogonal() * strike_half_width
	var origin := area[0] - side
	var tip := origin + aim * strike_reach()
	draw_colored_polygon(area, Color(1.0, 0.85, 0.45, 0.45 * fade))
	draw_polyline(area + PackedVector2Array([area[0]]), Color(1.0, 0.95, 0.7, 0.9 * fade), 2.0)
	draw_line(origin, tip, Color(1.0, 1.0, 0.9, fade), 4.0)
	for t: float in [0.45, 0.7, 0.95]:
		var centre := origin + aim * strike_reach() * t
		var arc := PackedVector2Array()
		for i in 9:
			var s := lerpf(-1.0, 1.0, i / 8.0)
			arc.append(centre + side * s - aim * strike_length * 0.12 * (1.0 - s * s))
		draw_polyline(arc, Color(1.0, 0.98, 0.85, 0.85 * fade), 2.0)


## Swing windup: the exact swing sector, outlined dark-under-light for contrast
## on any floor, getting stronger as the swing nears (`progress` 0..1).
func _draw_swing_warning(progress: float) -> void:
	var sector := swing_polygon()
	var outline := sector + PackedVector2Array([Vector2.ZERO])
	draw_colored_polygon(sector, Color(0.55, 0.75, 1.0, 0.08 + 0.12 * progress))
	draw_polyline(outline, Color(0.0, 0.0, 0.0, 0.35 + 0.25 * progress), 3.5)
	draw_polyline(outline, Color(0.8, 0.9, 1.0, 0.4 + 0.45 * progress), 1.5)


## Swing slash at `t` 0..1 of swing_slash_time: during the first 55% a bright
## crescent trail sweeps from one edge of the sector to the other with a
## leading blade streak; the whole danger sector is filled and outlined; then
## everything fades. On a hit, an impact flash marks where the Mage was struck.
## Everything stays inside swing_polygon() (the hit area).
func _draw_swing_slash(t: float) -> void:
	var sweep := clampf(t / 0.55, 0.0, 1.0)
	var fade := 1.0 if t < 0.55 else 1.0 - (t - 0.55) / 0.45
	var start := swing_aim.angle() - deg_to_rad(swing_half_angle)
	var lead := start + deg_to_rad(swing_half_angle * 2.0) * sweep
	var sector := swing_polygon()
	var outline := sector + PackedVector2Array([Vector2.ZERO])
	draw_colored_polygon(sector, Color(0.75, 0.9, 1.0, 0.22 * fade))
	draw_polyline(outline, Color(0.0, 0.0, 0.0, 0.5 * fade), 4.0)
	draw_polyline(outline, Color(0.85, 0.95, 1.0, 0.9 * fade), 2.0)
	# Crescent trail: brighter towards the blade.
	var inner := swing_reach * 0.45
	var steps := 10
	for i in steps:
		var a0 := lerpf(start, lead, float(i) / steps)
		var a1 := lerpf(start, lead, float(i + 1) / steps)
		var quad := PackedVector2Array([Vector2.from_angle(a0) * inner, Vector2.from_angle(a0) * swing_reach,
				Vector2.from_angle(a1) * swing_reach, Vector2.from_angle(a1) * inner])
		draw_colored_polygon(quad, Color(0.92, 0.98, 1.0, fade * (0.2 + 0.65 * float(i + 1) / steps)))
	# Secondary streak along the trail.
	var streak := PackedVector2Array()
	for i in steps + 1:
		streak.append(Vector2.from_angle(lerpf(start, lead, float(i) / steps)) * swing_reach * 0.8)
	draw_polyline(streak, Color(1.0, 1.0, 1.0, 0.9 * fade), 2.0)
	# Leading blade edge.
	var blade_dir := Vector2.from_angle(lead)
	draw_line(blade_dir * swing_reach * 0.25, blade_dir * swing_reach, Color(0.05, 0.05, 0.1, 0.7 * fade), 6.0)
	draw_line(blade_dir * swing_reach * 0.25, blade_dir * swing_reach, Color(1.0, 1.0, 1.0, fade), 3.0)
	if _swing_hit:
		var size := 9.0 + 5.0 * sweep
		draw_circle(_swing_hit_pos, 5.0 * fade + 1.0, Color(1.0, 0.95, 0.6, 0.8 * fade))
		for k in 4:
			var ray := Vector2.from_angle(PI / 4.0 + k * PI / 2.0) * size
			draw_line(_swing_hit_pos - ray, _swing_hit_pos + ray, Color(1.0, 0.9, 0.4, fade), 2.0)
