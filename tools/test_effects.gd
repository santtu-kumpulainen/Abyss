extends SceneTree
## Headless check of the Water Caster and the sprite-sheet effects: effect
## resources (verified frame layouts), PixelEffect lifetime, Mage cast flash,
## projectile impact, enemy death puff, boss slam telegraph and the Water
## Caster's 0.4 s telegraph + freezing impact, plus its Cavern Depths biome swap.
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_effects.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SEED := 4242
const SCENE := "res://scenes/dungeon/dungeon.tscn"

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState


## Stand-in target recording the damage it takes.
class Dummy extends Node2D:
	var taken := 0.0

	func take_damage(amount: float) -> void:
		taken += amount


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	RunState.seed_override = SEED
	_test_resources()
	await _load_scene()
	await _test_pixel_effect()
	await _test_mage_and_projectile()
	await _test_enemy_death()
	await _test_boss_telegraph()
	await _test_water_caster()
	_test_biome_swap()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	RunState.seed_override = 0
	quit(1 if _failures > 0 else 0)


func _effects(parent: Node = null) -> Array:
	var root: Node = parent if parent else current_scene
	return root.get_children().filter(func(n: Node) -> bool: return n is PixelEffect and not n.is_queued_for_deletion())


# --- Resources ------------------------------------------------------------------------------------------

func _test_resources() -> void:
	# [file, sheet size in px, columns, first filled cell, filled cells] from scanning the sheets.
	var expected := {
		"cast_flash": [900, 9, 1, 71], "hit_spark": [700, 7, 1, 40], "death_bubbles": [800, 8, 0, 61],
		"freeze_burst": [1000, 10, 0, 86], "water_telegraph": [800, 8, 0, 61], "slam_telegraph": [800, 8, 0, 61],
	}
	for name: String in expected:
		var sheet := load("res://scenes/effects/%s.tres" % name) as EffectSheet
		var e: Array = expected[name]
		_check(sheet != null and sheet.texture != null and sheet.texture.get_width() == e[0] and sheet.columns == e[1]
				and sheet.first_frame == e[2] and sheet.frame_count == e[3] and sheet.first_frame + sheet.frame_count <= e[1] * e[1],
				"%s: %d x %d grid, frames %d..%d" % [name, e[1], e[1], e[2], e[2] + e[3] - 1])
	var frames := load("res://scenes/spells/water_bolt/water_ball_frames.tres") as SpriteFrames
	_check(frames != null and frames.get_frame_count(&"default") == 12, "Water Ball: 12 frames imported (the blocking .gdignore is gone)")
	_check(not FileAccess.file_exists("res://assets/characters/mage/spells/Water Ball/.gdignore"), "only the Water Ball .gdignore was removed")
	_check(FileAccess.file_exists("res://assets/characters/mage/spells/Water Arrow/.gdignore") and FileAccess.file_exists("res://assets/characters/mage/spells/Fire Spell/.gdignore"),
			"other spell folders stay ignored")


# --- Behaviour ----------------------------------------------------------------------------------------------

func _test_pixel_effect() -> void:
	var sheet := load("res://scenes/effects/hit_spark.tres") as EffectSheet
	var effect := PixelEffect.spawn(sheet, current_scene, Vector2(10, 20))
	_check(effect != null and effect.global_position == Vector2(10, 20) and effect.get_child(0) is Sprite2D, "an effect spawns at the given position")
	_check(is_equal_approx(effect.total_time(), 40.0 / 100.0), "plays for frames / fps (%.2f s)" % effect.total_time())
	var stretched := PixelEffect.spawn(sheet, current_scene, Vector2.ZERO, 0.4, 56.0)
	_check(is_equal_approx(stretched.total_time(), 0.4) and is_equal_approx((stretched.get_child(0) as Sprite2D).scale.x, 0.56),
			"duration and diameter override the sheet's speed and scale")
	_check(PixelEffect.spawn(null, current_scene, Vector2.ZERO) == null, "no sheet: nothing spawned")
	await _wait_until(func() -> bool: return _effects().is_empty(), 120)
	_check(_effects().is_empty(), "effects free themselves")


func _test_mage_and_projectile() -> void:
	var caster := _mage.caster
	var before := _effects().size()
	var shot := caster.try_cast(caster.global_position + Vector2(200, 0))
	_check(shot != null and _effects().size() == before + 1, "casting plays one cast flash (also with Twin Cast it is one per cast)")
	var impact_before := _effects().size()
	var dummy := Dummy.new()
	current_scene.add_child(dummy)
	shot._on_body_entered(dummy)
	_check(_effects().size() == impact_before + 1 and dummy.taken > 0.0, "a hit plays the impact spark")
	dummy.free()
	caster._cooldown_left = 0.0
	_run.purchased[&"twin_cast"] = 1
	_run.changed.emit()
	var count := _effects().size()
	caster.try_cast(caster.global_position + Vector2(200, 0))
	_check(_effects().size() == count + 1, "Twin Cast: still a single cast flash")
	_run.purchased.erase(&"twin_cast")
	_run.changed.emit()


func _test_enemy_death() -> void:
	var enemy := (load("res://scenes/enemies/giant_goblin.tscn") as PackedScene).instantiate() as Enemy
	current_scene.add_child(enemy)
	enemy.global_position = Vector2(300, 300)
	_check(enemy.death_effect != null, "enemies carry the death puff")
	var before := _effects().size()
	enemy.take_damage(99999.0)
	await _frames(2)
	_check(_effects().size() == before + 1, "an enemy's death plays the bubble puff")


func _test_boss_telegraph() -> void:
	_run.add_rewards(100000, 0)
	_grant_seals()
	_dungeon.enter_room(_dungeon.boss_index(), &"DoorBottom")
	await _frames(2)
	var boss: Boss = null
	for e in _dungeon.current_room.get_node(^"Enemies").get_children():
		if e is Boss:
			boss = e
	_check(boss != null and boss.slam_telegraph != null, "the boss has a slam telegraph")
	_check(boss.begin_attack(&"slam"), "setup: slam wind-up started")
	var rings := _effects(boss)
	_check(rings.size() == 1 and absf((rings[0] as PixelEffect).total_time() - boss.current_slam_windup()) < 0.001
			and is_equal_approx((rings[0].get_child(0) as Sprite2D).scale.x, boss.slam_radius * 2.0 / 100.0),
			"a ring fits the slam radius and lasts the wind-up (%.1f s)" % boss.current_slam_windup())
	boss.state = Boss.State.CHASE
	_check(_effects(boss).size() == 1 and boss.begin_attack(&"volley") and _effects(boss).size() == 1, "volleys add no ring")


func _test_water_caster() -> void:
	var scene := load("res://scenes/enemies/water_caster.tscn") as PackedScene
	var demon := (load("res://scenes/enemies/demon_caster.tscn") as PackedScene).instantiate() as RangedEnemy
	_check(demon.telegraph_time == 0.0, "the Demon Caster still fires at once")
	demon.free()
	var caster := scene.instantiate() as RangedEnemy
	current_scene.add_child(caster)
	caster.global_position = _mage.global_position + Vector2(220, 0)
	_mage.global_position = Vector2(400, 300)
	caster.global_position = Vector2(400 + 220, 300)
	_check(is_equal_approx(caster.telegraph_time, 0.4) and caster.telegraph_effect != null and caster.projectile.id == &"water_bolt",
			"Water Caster: 0.4 s telegraph, water bolt")
	_check(caster.xp_reward == 2 and caster.currency_reward == 10, "Water Caster rewards match the Demon Caster it replaces")
	caster.detection_radius = 2000.0
	var shots := [0]
	caster.fired.connect(func(_p: Projectile) -> void: shots[0] += 1)
	await _wait_until(func() -> bool: return not _effects(caster).is_empty(), 60)
	_check(_effects(caster).size() == 1 and shots[0] == 0, "the telegraph circle appears before any shot")
	var ring := _effects(caster)[0] as PixelEffect
	_check(absf(ring.total_time() - 0.4) < 0.001, "the telegraph lasts about 0.4 s")
	var frames := 0
	while shots[0] == 0 and frames < 120:
		await physics_frame
		frames += 1
	_check(shots[0] == 1 and frames >= 20 and frames <= 35, "exactly one shot follows after the telegraph (%d frames, ~0.4 s)" % frames)
	var bolt: Projectile = current_scene.get_children().filter(func(n: Node) -> bool: return n is Projectile and n.hostile_to_player).back()
	_check(bolt != null and bolt.spell.id == &"water_bolt" and bolt.spell.frames.get_frame_count(&"default") == 12 and bolt.spell.impact_effect != null,
			"the bolt uses the Water Ball frames and the freezing impact")
	var before := _effects().size()
	var hp := _mage.health.current
	bolt._on_body_entered(_mage)
	_check(_effects().size() == before + 1 and _mage.health.current < hp, "the bolt's hit plays the freezing burst")
	caster.queue_free()


func _test_biome_swap() -> void:
	var level := Biomes.default_levels + 1
	var swapped := Biomes.map_scene(load("res://scenes/enemies/demon_caster.tscn"), level, "enemy_map")
	_check(swapped.resource_path.ends_with("water_caster.tscn"), "Cavern Depths replaces Demon Casters with Water Casters")
	_check(Biomes.map_scene(load("res://scenes/enemies/demon_caster.tscn"), 1, "enemy_map").resource_path.ends_with("demon_caster.tscn"),
			"The Dungeon keeps its Demon Casters")


# --- Helpers --------------------------------------------------------------------------------------------------

func _load_scene() -> void:
	var old_id := current_scene.get_instance_id() if current_scene else 0
	paused = false
	change_scene_to_file(SCENE)
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage
	_run = _dungeon.run_state


func _wait_until(condition: Callable, max_frames: int = 240) -> void:
	for i in max_frames:
		if condition.call():
			return
		await physics_frame
	await process_frame


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	if label.is_empty():
		return
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1


## Ancient Seals (Issue #43): the boss gate also needs this level's seals; collect them all.
func _grant_seals() -> void:
	for i: int in _dungeon.seal_rooms():
		_run.collect_seal(_dungeon.seal_id(i))
