extends SceneTree
## Headless check of Issue #51 Stage 3 (hit feedback and knockback): Mage and
## regular-enemy knockback (distance, duration, walls), no Mage knockback during
## the dash, no enemy knockback in committed attack phases, minibosses and the
## boss never displaced, the white / red hit flash and scale pop always returning
## to the original state, and the bigger Fireball hit spark.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_hit_feedback.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const MAGE := "res://scenes/mage/mage.tscn"
const DEMON := "res://scenes/enemies/demon.tscn"
const GOBLIN := "res://scenes/enemies/giant_goblin.tscn"
const BLOOD_MONSTER := "res://scenes/enemies/blood_monster.tscn"
const CASTER := "res://scenes/enemies/water_caster.tscn"
const BOSSES: Array[String] = ["res://scenes/enemies/brood_mother.tscn", "res://scenes/enemies/hexcaller.tscn",
		"res://scenes/enemies/water_caster_boss.tscn", "res://scenes/enemies/abyss_warden.tscn"]
const FIREBALL := "res://scenes/spells/fire_ball/fire_ball.tres"
const FRAME := 1.0 / 60.0

var _failures := 0


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	await _test_mage_knockback()
	await _test_mage_wall()
	await _test_mage_dash()
	await _test_enemy_knockback()
	await _test_enemy_wall()
	await _test_projectile_hit()
	await _test_protected_phases()
	await _test_bosses_never_displaced()
	await _test_enemy_flash()
	await _test_mage_flash()
	_test_hit_spark()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


# --- Mage -------------------------------------------------------------------------------

func _test_mage_knockback() -> void:
	var mage := await _spawn(MAGE, Vector2(0, 0)) as Mage
	var start := mage.global_position
	var started := mage.apply_knockback(Vector2.RIGHT)
	var frames := await _frames_while(func() -> bool: return mage.is_knocked_back())
	await _physics(3)
	var moved := mage.global_position - start
	_check(started and absf(moved.x - 13.2) <= 1.0 and absf(moved.y) < 0.01,
			"Mage knockback: %.1f px along the hit (220 px/s fading over 0.12 s, ~13 px)" % moved.x)
	_check(absf(frames * FRAME - mage.knockback_duration) <= FRAME + 0.001 and is_equal_approx(mage.knockback_duration, 0.12)
			and is_equal_approx(mage.knockback_speed, 220.0),
			"Mage knockback lasts %.3f s (0.12 s)" % (frames * FRAME))
	# A second hit restarts it rather than stacking.
	mage.apply_knockback(Vector2.UP)
	await _physics(1)
	mage.apply_knockback(Vector2.UP)
	start = mage.global_position
	await _frames_while(func() -> bool: return mage.is_knocked_back())
	_check(absf((start - mage.global_position).y - 13.2 * (1.0 - 0.0)) <= 1.2,
			"a repeated hit restarts the knockback instead of stacking speed (%.1f px)" % (start - mage.global_position).y)
	mage.free()


func _test_mage_wall() -> void:
	var mage := await _spawn(MAGE, Vector2(0, 0)) as Mage
	var edge := _right_edge(mage)
	var wall := _wall(Vector2(edge + 4.0 + 50.0, mage.global_position.y), Vector2(100, 200))
	await _physics(2)
	var start := mage.global_position.x
	mage.apply_knockback(Vector2.RIGHT)
	await _frames_while(func() -> bool: return mage.is_knocked_back())
	await _physics(2)
	var moved := mage.global_position.x - start
	_check(moved <= 4.0 + 0.6 and _right_edge(mage) <= edge + 4.0 + 0.6,
			"Mage knockback stops at a wall (%.1f px of a 4 px gap)" % moved)
	mage.free()
	wall.free()


func _test_mage_dash() -> void:
	var mage := await _spawn(MAGE, Vector2(0, 0)) as Mage
	var dashed := mage.try_dash(Vector2.RIGHT)
	_check(dashed and mage.is_dashing() and not mage.apply_knockback(Vector2.LEFT) and not mage.is_knocked_back(),
			"no Mage knockback during the dash")
	await _frames_while(func() -> bool: return mage.is_dashing())
	_check(mage.is_dash_invulnerable() and not mage.apply_knockback(Vector2.LEFT), "no Mage knockback during the dash's invulnerability")
	await _frames_while(func() -> bool: return mage.is_dash_invulnerable())
	await _physics(1)
	# A running knockback ends when a dash starts (the dash keeps its own path).
	mage._dash_cooldown_left = 0.0
	_check(mage.apply_knockback(Vector2.LEFT), "knockback works again after the dash")
	var dash_start := mage.global_position
	mage.try_dash(Vector2.UP)
	await _physics(1)
	_check(not mage.is_knocked_back() and absf(mage.global_position.x - dash_start.x) < 3.0,
			"starting a dash cancels a running knockback (no sideways drift: %.1f px)" % absf(mage.global_position.x - dash_start.x))
	# cancel_dash() (room change, death, end of run) also stops a knockback.
	await _frames_while(func() -> bool: return mage.is_dashing() or mage.is_dash_invulnerable())
	mage.apply_knockback(Vector2.LEFT)
	mage.cancel_dash()
	_check(not mage.is_knocked_back(), "room change / end of run (cancel_dash) stops a knockback")
	mage.free()


# --- Regular enemies ----------------------------------------------------------------------

func _test_enemy_knockback() -> void:
	for path in [DEMON, GOBLIN, BLOOD_MONSTER, CASTER]:
		var enemy := await _spawn(path, Vector2(0, 0)) as Enemy
		var start := enemy.global_position
		var started := enemy.apply_knockback(Vector2.RIGHT)
		var frames := await _frames_while(func() -> bool: return enemy.is_knocked_back())
		await _physics(2)
		var moved := enemy.global_position - start
		_check(started and absf(moved.x - 8.0) <= 1.0 and absf(moved.y) < 0.01 and absf(frames * FRAME - 0.10) <= FRAME + 0.001,
				"%s knockback: %.1f px in %.3f s (80 px/s x 0.10 s)" % [path.get_file().get_basename(), moved.x, frames * FRAME])
		enemy.free()


func _test_enemy_wall() -> void:
	var enemy := await _spawn(DEMON, Vector2(0, 0)) as Enemy
	var edge := _right_edge(enemy)
	var wall := _wall(Vector2(edge + 3.0 + 50.0, enemy.global_position.y), Vector2(100, 200))
	await _physics(2)
	var start := enemy.global_position.x
	enemy.apply_knockback(Vector2.RIGHT)
	await _frames_while(func() -> bool: return enemy.is_knocked_back())
	await _physics(2)
	var moved := enemy.global_position.x - start
	_check(moved <= 3.0 + 0.6 and not enemy.is_knocked_back(), "enemy knockback stops at a wall (%.1f px of a 3 px gap)" % moved)
	enemy.free()
	wall.free()


func _test_projectile_hit() -> void:
	var enemy := await _spawn(DEMON, Vector2(0, 0)) as Enemy
	var hp := enemy.health.current
	var start := enemy.global_position
	var src := Node2D.new()
	root.add_child(src)
	var spell := load(FIREBALL) as Spell
	var shot := spell.projectile_scene.instantiate() as Projectile
	shot.setup(spell, Vector2.LEFT, src)
	root.add_child(shot)
	shot.global_position = enemy.global_position + Vector2(10, 0)
	shot._on_body_entered(enemy)
	await _frames_while(func() -> bool: return enemy.is_knocked_back())
	await _physics(2)
	_check(enemy.health.current < hp and absf((start - enemy.global_position).x - 8.0) <= 1.0,
			"a Fireball hit damages and pushes the enemy along the shot (%.1f px)" % (start - enemy.global_position).x)
	enemy.free()
	src.free()


## Committed attack phases are never displaced; a running knockback stops when one starts.
func _test_protected_phases() -> void:
	var mage := await _spawn(MAGE, Vector2(60, 0)) as Mage
	mage.invulnerable = true
	var goblin := await _spawn(GOBLIN, Vector2(0, 0), &"player") as Goblin
	# Knocked back, then the special starts: the knockback stops at once.
	goblin.apply_knockback(Vector2.LEFT)
	await _physics(1)
	goblin.begin_special()
	var at := goblin.global_position
	await _physics(3)
	_check(not goblin.is_knocked_back() and goblin.global_position.distance_to(at) < 0.01,
			"Goblin: a running knockback stops when the Dash windup starts")
	var windup_ok := true
	var moved := 0.0
	var origin := goblin.global_position
	var seen := {}
	while goblin.phase == TelegraphedMelee.Phase.WINDUP or goblin.phase == TelegraphedMelee.Phase.ACTIVE:
		var key := "anticipation" if goblin.is_anticipating() else ("active" if goblin.phase == TelegraphedMelee.Phase.ACTIVE
				else ("locked" if goblin.is_aim_locked() else "tracking"))
		seen[key] = true
		windup_ok = windup_ok and not goblin.can_be_knocked_back() and not goblin.apply_knockback(Vector2.LEFT)
		if goblin.phase == TelegraphedMelee.Phase.WINDUP:
			moved = maxf(moved, goblin.global_position.distance_to(origin))
		await physics_frame
	_check(windup_ok and seen.size() == 4 and moved < 0.01,
			"Goblin Dash: no knockback in tracking, locked, anticipation or strike (%s)" % [seen.keys()])
	_check(goblin.phase == TelegraphedMelee.Phase.RECOVER and goblin.apply_knockback(Vector2.LEFT),
			"Goblin: knockback is allowed again in the recovery")
	await _frames_while(func() -> bool: return goblin.phase != TelegraphedMelee.Phase.CHASE)
	goblin._start_swing(Vector2.RIGHT)
	_check(goblin.swing_phase == Goblin.Swing.WINDUP and not goblin.apply_knockback(Vector2.LEFT),
			"Goblin: no knockback during a normal swing's telegraph")
	goblin.free()

	var monster := await _spawn(BLOOD_MONSTER, Vector2(0, 0), &"player") as BloodMonster
	monster.begin_special()
	var monster_ok := true
	var phases := {}
	while monster.phase == TelegraphedMelee.Phase.WINDUP or monster.phase == TelegraphedMelee.Phase.ACTIVE:
		phases[monster.phase] = true
		monster_ok = monster_ok and not monster.apply_knockback(Vector2.LEFT)
		await physics_frame
	_check(monster_ok and phases.size() == 2, "Blood Monster: no knockback during its lane telegraph or dash")
	monster.free()

	var caster := await _spawn(CASTER, Vector2(0, 0), &"player") as RangedEnemy
	mage.global_position = Vector2(150, 0)
	var aimed := await _frames_until(func() -> bool: return caster._telegraph_left > 0.0, 300)
	_check(aimed < 300 and not caster.apply_knockback(Vector2.LEFT), "ranged enemy: no knockback while aiming (telegraph)")
	await _frames_until(func() -> bool: return caster._telegraph_left <= 0.0, 300)
	_check(caster.apply_knockback(Vector2.LEFT), "ranged enemy: knockback allowed again once the shot is fired")
	caster.free()
	mage.free()


func _test_bosses_never_displaced() -> void:
	for path in BOSSES:
		var boss := await _spawn(path, Vector2(0, 0)) as Enemy
		var start := boss.global_position
		var scale_before := (boss.get_node(^"AnimatedSprite2D") as Node2D).scale
		boss.take_damage(1.0)
		var flashed := HitFeedback.flash_amount(boss.get_node(^"AnimatedSprite2D") as CanvasItem) > 0.0
		var refused := not boss.apply_knockback(Vector2.RIGHT) and not boss.can_be_knocked_back()
		HitFeedback.knock(boss, Vector2.RIGHT)
		await _physics(10)
		var sprite := boss.get_node(^"AnimatedSprite2D") as Node2D
		var name := path.get_file().get_basename()
		_check(refused and boss.global_position.distance_to(start) < 0.01 and not boss.is_knocked_back(),
				"%s: never displaced by hits" % name)
		_check(flashed and (boss is WaterCasterBoss or sprite.scale.is_equal_approx(scale_before)),
				"%s: white hit flash, no scale pop" % name)
		boss.free()


# --- Flash and pop --------------------------------------------------------------------------------

func _test_enemy_flash() -> void:
	var enemy := await _spawn(DEMON, Vector2(0, 0)) as Enemy
	var sprite := enemy.get_node(^"AnimatedSprite2D") as AnimatedSprite2D
	var base := Vector2.ONE * enemy.sprite_scale
	sprite.self_modulate = Color(1.0, 0.7, 0.4)  # e.g. a champion tint
	enemy.take_damage(1.0)
	_check(is_equal_approx(HitFeedback.flash_amount(sprite), enemy.hit_flash_strength) and sprite.scale.is_equal_approx(base * 1.12)
			and is_equal_approx(enemy.hit_pop_scale, 1.12),
			"enemy hit: white flash (%.2f) and a 1.12x scale pop" % HitFeedback.flash_amount(sprite))
	await _seconds(0.3)
	_check(is_zero_approx(HitFeedback.flash_amount(sprite)) and sprite.scale.is_equal_approx(base) and not HitFeedback.is_flashing(sprite)
			and sprite.modulate == Color.WHITE and sprite.self_modulate == Color(1.0, 0.7, 0.4),
			"enemy hit feedback returns to the original scale and colour (tints untouched)")
	# Overlapping hits: never above 1.12x, always back to the base state.
	var peak := 0.0
	for i in 12:
		enemy.take_damage(0.1)
		for f in 2:
			await physics_frame
			peak = maxf(peak, sprite.scale.x / base.x)
	await _seconds(0.3)
	_check(peak <= 1.12 + 0.001 and sprite.scale.is_equal_approx(base) and is_zero_approx(HitFeedback.flash_amount(sprite))
			and not HitFeedback.is_flashing(sprite),
			"12 overlapping hits: peak %.3fx, then exactly the original scale and no tint left" % peak)
	enemy.free()


func _test_mage_flash() -> void:
	var mage := await _spawn(MAGE, Vector2(0, 0)) as Mage
	var sprite := mage.get_node(^"AnimatedSprite2D") as AnimatedSprite2D
	var base := sprite.scale
	mage.apply_slow(0.5, 2.0)
	mage.take_damage(1.0)
	var mat := sprite.material as ShaderMaterial
	_check(mat != null and is_equal_approx(HitFeedback.flash_amount(sprite), mage.hit_flash_strength)
			and (mat.get_shader_parameter(&"flash_color") as Color).r > 0.9 and (mat.get_shader_parameter(&"flash_color") as Color).g < 0.4,
			"Mage hit: red-tinted impact flash (%.2f strength)" % HitFeedback.flash_amount(sprite))
	for i in 4:
		mage.take_damage(1.0)
		await _physics(2)
	await _seconds(0.35)
	_check(is_zero_approx(HitFeedback.flash_amount(sprite)) and sprite.scale.is_equal_approx(base) and sprite.modulate == Color.WHITE
			and sprite.self_modulate == mage.slow_tint,
			"Mage hit flash fades fully after repeated hits; the slow tint and scale are untouched")
	mage.free()


func _test_hit_spark() -> void:
	var sheet := load("res://scenes/effects/hit_spark.tres") as EffectSheet
	_check(is_equal_approx(sheet.scale, 0.8), "Fireball hit spark scale 0.8 (was 0.45)")


# --- Helpers --------------------------------------------------------------------------------------

## Spawns `path` at `pos`. Enemies target `target_group` (default: nobody, so they stand still).
func _spawn(path: String, pos: Vector2, target_group: StringName = &"nobody") -> Node2D:
	var node := (load(path) as PackedScene).instantiate() as Node2D
	if node is Enemy:
		(node as Enemy).target_group = target_group
	root.add_child(node)
	node.global_position = pos
	await _physics(2)
	return node


## A static wall (world layer 1) centred at `pos`.
func _wall(pos: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	body.position = pos  # before entering the tree: never overlaps the body under test
	root.add_child(body)
	return body


## Global x of the right edge of `body`'s circular feet collider.
func _right_edge(body: Node2D) -> float:
	var cs := body.get_node(^"CollisionShape2D") as CollisionShape2D
	return cs.global_position.x + (cs.shape as CircleShape2D).radius


func _physics(count: int) -> void:
	for i in count:
		await physics_frame


func _seconds(s: float) -> void:
	await _physics(ceili(s * 60.0))
	await process_frame


## Physics frames while `condition` holds (at most 300); returns how many.
func _frames_while(condition: Callable) -> int:
	var n := 0
	while condition.call() and n < 300:
		await physics_frame
		n += 1
	return n


func _frames_until(condition: Callable, max_frames: int) -> int:
	for i in max_frames:
		if condition.call():
			return i
		await physics_frame
	return max_frames


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
