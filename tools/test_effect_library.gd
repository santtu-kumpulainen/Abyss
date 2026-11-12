extends SceneTree
## Headless check of the Issue #49 effects architecture (Stage 2): the
## EffectLibrary catalog (every id loads a sheet whose frames fit its texture
## and match the Gigapack spritesheet.txt), the generated resources being
## reproducible by tools/build_gigapack_effects.gd, padded sheets (cells not
## filling the texture), PixelEffect one-shot / loop / stop(), rotation, the
## existing 100x100 sheets keeping their layout, the .gdignore set (only the
## used Gigapack sheets are imported) and the Stage 1 feedback effects
## (Health / Speed Potion on the Mage, coin burst at the anvil).
##
## Usage (after importing):
##   godot --headless --path . --script res://tools/test_effect_library.gd
##
## Prints PASS/FAIL per check and exits with code 1 if any check failed.

const SEED := 4949
const SCENE := "res://scenes/dungeon/dungeon.tscn"
const BUILD := "res://tools/build_gigapack_effects.gd"
const PACK := "res://assets/effects/Super Pixel Effects Gigapack (Free Version)/"
const EXPECTED_IDS: Array[StringName] = [&"dash_puff", &"teleport_ring", &"teleport_aura", &"teleport_arrive",
		&"heal", &"haste", &"coin_burst", &"water_impact", &"green_splatter", &"skull_smoke"]

var _failures := 0
var _dungeon: Dungeon
var _mage: Mage
var _run: RunState


func _initialize() -> void:
	_run_tests.call_deferred()


func _run_tests() -> void:
	RunState.seed_override = SEED
	_test_catalog()
	_test_metadata_parser()
	_test_imports()
	await _load_dungeon()
	await _test_spawning()
	await _test_old_sheets()
	await _test_feedback()
	print("RESULT: %s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	RunState.seed_override = 0
	quit(1 if _failures > 0 else 0)


# --- Catalog / resources ----------------------------------------------------------

func _test_catalog() -> void:
	var build: GDScript = load(BUILD)
	_check(EffectLibrary.SHEETS.keys() == EXPECTED_IDS, "catalog holds the 7 Issue #49 effects and the Issue #51 water impact, green splatter and skull smoke")
	_check(build.EFFECTS.keys() == EffectLibrary.SHEETS.keys(), "build tool and catalog list the same ids")
	for id: StringName in EXPECTED_IDS:
		var sheet := EffectLibrary.sheet(id)
		var ok := sheet != null and sheet.texture != null and EffectLibrary.has(id)
		if ok:
			var last := sheet.frame_rect(sheet.first_frame + sheet.frame_count - 1)
			ok = is_equal_approx(sheet.fps, 15.0) and sheet.frame_count >= 1 \
					and last.end.x <= sheet.texture.get_width() and last.end.y <= sheet.texture.get_height() \
					and String(sheet.texture.resource_path).begins_with(PACK + "spritesheet/")
		_check(ok, "%s: loads a Gigapack sheet at 15 FPS whose frames fit the texture" % id)
		# The saved resource equals a fresh build from spritesheet.txt.
		var fresh: EffectSheet = build.build_sheet(build.EFFECTS[id])
		_check(fresh != null and sheet != null and fresh.frame_size == sheet.frame_size and fresh.columns == sheet.columns
				and fresh.first_frame == sheet.first_frame and fresh.frame_count == sheet.frame_count and fresh.loop == sheet.loop
				and is_equal_approx(fresh.scale, sheet.scale), "%s: resource matches its spritesheet.txt (rebuild is identical)" % id)
	_check(EffectLibrary.sheet(&"teleport_ring").loop and EffectLibrary.sheet(&"teleport_aura").loop and not EffectLibrary.sheet(&"heal").loop,
			"loop flags: teleport ring/aura loop, one-shots do not")
	var aura := EffectLibrary.sheet(&"teleport_aura")
	_check(aura.columns == 5 and aura.frame_size == Vector2i(96, 96) and aura.texture.get_width() == 512,
			"padded sheet: 5 x 96 px columns in a 512 px texture")
	_check(aura.frame_rect(5) == Rect2(0, 96, 96, 96) and aura.frame_rect(7) == Rect2(192, 96, 96, 96), "padded sheet: frames cut row by row")
	_check(not EffectLibrary.has(&"no_such_effect") and EffectLibrary.spawn(&"no_such_effect", root, Vector2.ZERO) == null,
			"unknown id: nothing spawned")


func _test_metadata_parser() -> void:
	var build: GDScript = load(BUILD)
	var layout: Dictionary = build.parse_metadata(PACK + "spritesheet/Lightning/lightning_aura_002/lightning_aura_002_large_blue/spritesheet.txt")
	_check(layout.get("frame_size") == Vector2i(96, 96) and layout.get("columns") == 5 and layout.get("frames") == 16,
			"spritesheet.txt parser: 16 frames of 96x96 in 5 columns (%s)" % layout)
	_check(build.parse_metadata(PACK + "missing/spritesheet.txt").is_empty(), "spritesheet.txt parser: missing file -> {}")


func _test_imports() -> void:
	var sheets := 0
	var visible: Array[String] = []
	_collect_imported(PACK + "spritesheet", visible)
	for path in visible:
		if path.ends_with("spritesheet.png"):
			sheets += 1
	# Ids may share one sheet (water_impact plays all frames of teleport_ring's sheet).
	var used := {}
	var build: GDScript = load(BUILD)
	for id: StringName in build.EFFECTS:
		used[build.EFFECTS[id]["sheet"]] = true
	_check(sheets == used.size(), "only the %d used Gigapack sheets are visible to the importer (%d)" % [used.size(), sheets])
	_check(FileAccess.file_exists(PACK + "PNG/.gdignore"), "PNG/ frame sequences are not imported (.gdignore)")
	_check(FileAccess.file_exists(PACK + "spritesheet/Explosions/.gdignore") and FileAccess.file_exists(
			PACK + "spritesheet/Fantasy Spells/spell_heal_001/spell_heal_001_small_red/.gdignore"), "unused categories and size variants are ignored")
	for id: StringName in EXPECTED_IDS:
		var texture_path: String = EffectLibrary.sheet(id).texture.resource_path
		_check(FileAccess.file_exists(texture_path + ".import") and FileAccess.file_exists(texture_path.get_base_dir() + "/spritesheet.txt"),
				"%s: source sheet kept with its .import and spritesheet.txt" % id)


## Files under `dir` that are not hidden by a .gdignore (as the importer sees them).
func _collect_imported(dir: String, out: Array[String]) -> void:
	if FileAccess.file_exists(dir + "/.gdignore"):
		return
	for file in DirAccess.get_files_at(dir):
		out.append(dir + "/" + file)
	for sub in DirAccess.get_directories_at(dir):
		_collect_imported(dir + "/" + sub, out)


# --- Spawning ----------------------------------------------------------------------

func _test_spawning() -> void:
	var host := Node2D.new()
	current_scene.add_child(host)
	var heal := EffectLibrary.spawn(&"heal", host, Vector2(40, 50), PI / 2.0)
	_check(heal != null and heal.get_parent() == host and heal.global_position.is_equal_approx(Vector2(40, 50))
			and is_equal_approx(heal.rotation, PI / 2.0), "spawn by id: parent, position and rotation")
	var sprite := heal.sprite()
	_check(sprite.region_enabled and sprite.region_rect == Rect2(0, 0, 128, 128) and is_equal_approx(sprite.scale.x, 0.6)
			and sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "first frame region, scale and pixel filtering")
	var lifetime := heal.total_time()
	_check(is_equal_approx(lifetime, 16.0 / 15.0), "one pass of 16 frames at 15 FPS = %.2f s" % lifetime)
	await _seconds(0.5)
	_check(is_instance_valid(heal) and heal.current_frame() > 0 and heal.sprite().region_rect != Rect2(0, 0, 128, 128), "frames advance")
	await _seconds(lifetime)
	_check(not is_instance_valid(heal) or heal.is_queued_for_deletion(), "one-shot frees itself after one pass")

	var aura := EffectLibrary.spawn(&"teleport_aura", host, Vector2.ZERO)
	var aura_time := aura.total_time()
	await _seconds(aura_time * 1.6)
	_check(is_instance_valid(aura) and not aura.is_queued_for_deletion() and aura.current_frame() < 16, "loop keeps playing past one pass")
	aura.stop(0.2)
	aura.stop(0.2)
	await _frames(2)
	_check(is_instance_valid(aura) and aura.modulate.a < 1.0, "stop(fade): fades out")
	await _seconds(0.4)
	_check(not is_instance_valid(aura), "stop(fade): freed after the fade (double stop is safe)")

	var ring := EffectLibrary.spawn(&"teleport_ring", host, Vector2.ZERO)
	await _seconds(0.5)
	_check(is_instance_valid(ring) and ring.current_frame() == 7 and ring.sprite().region_rect == Rect2(7 * 96, 0, 96, 96),
			"teleport ring holds its single ring frame")
	ring.stop()
	await _frames(1)
	_check(not is_instance_valid(ring), "stop(): freed at once")
	var stretched := EffectLibrary.spawn(&"dash_puff", host, Vector2.ZERO, 0.0, 0.5, 32.0)
	_check(is_equal_approx(stretched.total_time(), 0.5) and is_equal_approx(stretched.sprite().scale.x, 0.5),
			"duration/diameter use the sheet's own cell size (64 px -> 32 px = x0.5)")
	host.queue_free()
	await _frames(1)


func _test_old_sheets() -> void:
	# The Free Pixel Effects Pack sheets (100x100 cells) keep their old layout.
	for name in ["cast_flash", "hit_spark", "death_bubbles", "freeze_burst", "water_telegraph", "slam_telegraph"]:
		var sheet := load("res://scenes/effects/%s.tres" % name) as EffectSheet
		_check(sheet.frame_size == Vector2i(100, 100) and not sheet.loop and sheet.frame_rect(sheet.columns + 1) == Rect2(100, 100, 100, 100),
				"%s: default 100x100 cells, one-shot, same grid" % name)
	var spark := PixelEffect.spawn(load("res://scenes/effects/hit_spark.tres"), current_scene, Vector2.ZERO, 0.0, 56.0)
	_check(spark != null and spark.sprite().region_rect == Rect2(100, 0, 100, 100) and is_equal_approx(spark.sprite().scale.x, 0.56),
			"hit_spark spawns at its first filled cell with the old diameter scaling")
	spark.stop()


# --- Stage 1 feedback --------------------------------------------------------------

func _test_feedback() -> void:
	_run.add_rewards(0, 5000)
	var station := _dungeon.current_room.get_node_or_null(^"Decor/UpgradeStation") as UpgradeStation
	_mage.global_position = station.global_position + Vector2(50, 0)
	await _frames(3)
	station.set_open(true)
	station.purchase_supply(&"health_potion")
	_check(_effects_of(station, &"coin_burst").size() == 1, "anvil supply purchase plays the coin burst at the anvil")
	var failed := station.purchase_supply(&"home_teleport") and station.purchase_supply(&"home_teleport")
	_check(not failed and _effects_of(station, &"coin_burst").size() == 2, "a refused purchase plays no coin burst")
	station.purchase_supply(&"speed_potion")
	station.set_open(false)
	_mage.take_damage(_mage.health.max_health * 0.5 / _mage.damage_taken_multiplier)
	_dungeon.use_health_potion()
	var heals := _effects_of(_mage, &"heal")
	_check(heals.size() == 1 and (heals[0] as Node2D).global_position.is_equal_approx(_mage.caster.global_position),
			"Health Potion plays the heal effect on the Mage")
	_dungeon.use_speed_potion()
	_check(_effects_of(_mage, &"haste").size() == 1, "Speed Potion plays the haste effect on the Mage")
	_dungeon.use_health_potion()
	_check(_effects_of(_mage, &"heal").size() == 1, "an unused potion (none left) plays no effect")
	_run.add_rewards(0, 500)
	station.set_open(true)
	station.purchase_supply(&"health_potion")
	station.set_open(false)
	_mage.health.increase_max_health(0.0, _mage.health.max_health)
	_check(not _dungeon.use_health_potion() and _run.consumable_count(&"health_potion") == 1
			and _effects_of(_mage, &"heal").size() == 1, "a refused potion at full HP plays no heal effect")


func _effects_of(parent: Node, id: StringName) -> Array:
	return parent.get_children().filter(func(n: Node) -> bool:
		return n is PixelEffect and not n.is_queued_for_deletion() and (n as PixelEffect).sheet == EffectLibrary.sheet(id))


func _load_dungeon() -> void:
	var old_id := current_scene.get_instance_id() if current_scene else 0
	change_scene_to_file(SCENE)
	await _wait_until(func() -> bool:
		return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.is_node_ready(), 600)
	await _frames(2)
	_dungeon = current_scene as Dungeon
	_mage = _dungeon.mage
	_run = _dungeon.run_state


func _seconds(time: float) -> void:
	var end := Time.get_ticks_msec() + int(time * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame


func _wait_until(condition: Callable, max_frames: int = 240) -> void:
	for i in max_frames:
		if condition.call():
			return
		await physics_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	print("%s: %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		_failures += 1
