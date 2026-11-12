extends SceneTree
## Builds the EffectSheet resources of the Super Pixel Effects Gigapack effects
## used by the game (EffectLibrary) from each sheet's `spritesheet.txt`
## metadata: frame size, columns and frame count. The source sheets are not
## modified. Only the variants listed in EFFECTS are imported; every other
## folder of the pack carries a .gdignore (see assets/effects/README.md).
##
## Usage (run after the textures have been imported):
##   godot --headless --path . --script res://tools/build_gigapack_effects.gd
##
## Output: res://scenes/effects/gigapack/<id>.tres (one per EFFECTS entry).

const PACK_DIR := "res://assets/effects/Super Pixel Effects Gigapack (Free Version)/spritesheet/"
const OUTPUT_DIR := "res://scenes/effects/gigapack/"
## Recommended playback rate of the pack (readme.txt).
const FPS := 15.0

## Effect id -> sheet folder (relative to PACK_DIR) and EffectSheet overrides:
## "scale" (world size per source pixel), optional "first_frame"/"frame_count"
## (a sub-range of the frames) and "loop".
const EFFECTS := {
	# Dash start puff, rotated against the dash direction (Stage 3).
	&"dash_puff": {"sheet": "Smoke Bursts/directional_smoke_burst_001/directional_smoke_burst_001_large_white", "scale": 0.6},
	# Home Teleport cast: the clean ring frame of a blue impact, held and scaled with the cast progress (Stage 4).
	&"teleport_ring": {"sheet": "Impacts/symmetrical_impact_002/symmetrical_impact_002_large_blue", "scale": 1.0,
			"first_frame": 7, "frame_count": 1, "loop": true},
	# Home Teleport cast: crackling aura around the Mage while casting (Stage 4).
	&"teleport_aura": {"sheet": "Lightning/lightning_aura_002/lightning_aura_002_large_blue", "scale": 0.8, "loop": true},
	# Home Teleport arrival beam in the start room (Stage 4).
	&"teleport_arrive": {"sheet": "Sci-fi/scifi_warp_003/scifi_warp_003_large_blue", "scale": 0.9},
	# Health Potion drunk.
	&"heal": {"sheet": "Fantasy Spells/spell_heal_001/spell_heal_001_large_red", "scale": 0.6},
	# Speed Potion drunk.
	&"haste": {"sheet": "Fantasy Spells/spell_haste_001/spell_haste_001_large_green", "scale": 0.6},
	# Anvil supply bought.
	&"coin_burst": {"sheet": "Magic Bursts/directional_coin_burst_001/directional_coin_burst_001_large_yellow", "scale": 0.45},
	# Water Caster miniboss: big water bolt impact (Issue #51; same imported sheet as teleport_ring, all frames).
	&"water_impact": {"sheet": "Impacts/symmetrical_impact_002/symmetrical_impact_002_large_blue", "scale": 2.0},
}


func _init() -> void:
	quit(_build())


func _build() -> int:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var failures := 0
	for id: StringName in EFFECTS:
		var sheet := build_sheet(EFFECTS[id])
		if sheet == null:
			push_error("build_gigapack_effects: could not build %s" % id)
			failures += 1
			continue
		var path := "%s%s.tres" % [OUTPUT_DIR, id]
		if ResourceSaver.save(sheet, path) != OK:
			push_error("build_gigapack_effects: could not save %s" % path)
			failures += 1
			continue
		print("%s: %dx%d, %d columns, frames %d-%d%s -> %s" % [id, sheet.frame_size.x, sheet.frame_size.y, sheet.columns,
				sheet.first_frame, sheet.first_frame + sheet.frame_count - 1, " (loop)" if sheet.loop else "", path])
	return 1 if failures > 0 else 0


## EffectSheet for one EFFECTS entry, or null if its sheet or metadata is unusable.
static func build_sheet(data: Dictionary) -> EffectSheet:
	var folder: String = PACK_DIR + String(data["sheet"]) + "/"
	var layout := parse_metadata(folder + "spritesheet.txt")
	var texture := load(folder + "spritesheet.png") as Texture2D
	if layout.is_empty() or texture == null:
		return null
	var size: Vector2i = layout["frame_size"]
	var columns: int = layout["columns"]
	var rows := ceili(float(layout["frames"]) / columns)
	# Sheets may be padded (e.g. 5 x 96 px cells in a 512 px texture): the
	# cells only have to fit, they need not fill the texture.
	if columns * size.x > texture.get_width() or rows * size.y > texture.get_height():
		push_error("build_gigapack_effects: %s cells do not fit the texture" % folder)
		return null
	var sheet := EffectSheet.new()
	sheet.texture = texture
	sheet.frame_size = size
	sheet.columns = columns
	var total: int = layout["frames"]
	sheet.first_frame = clampi(data.get("first_frame", 0), 0, total - 1)
	sheet.frame_count = clampi(data.get("frame_count", total), 1, total - sheet.first_frame)
	sheet.fps = FPS
	sheet.scale = data.get("scale", 1.0)
	sheet.loop = data.get("loop", false)
	return sheet


## Parses a pack `spritesheet.txt` ("<frame>.png = x y w h" per line, frames
## in order, row by row from the top-left): {"frame_size": Vector2i,
## "columns": int, "frames": int}, or {} if it is missing, empty, its frames
## differ in size or a frame is not where that grid puts it.
static func parse_metadata(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var rects: Array[Rect2i] = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parts := line.get_slice("=", 1).strip_edges().split(" ", false)
		if parts.size() != 4:
			return {}
		rects.append(Rect2i(parts[0].to_int(), parts[1].to_int(), parts[2].to_int(), parts[3].to_int()))
	if rects.is_empty() or rects[0].size.x <= 0 or rects[0].size.y <= 0:
		return {}
	var size := rects[0].size
	var columns := 0
	for rect in rects:
		columns = maxi(columns, floori(rect.position.x / float(size.x)) + 1)
	for i in rects.size():
		if rects[i] != Rect2i(Vector2i(i % columns, floori(i / float(columns))) * size, size):
			return {}
	return {"frame_size": size, "columns": columns, "frames": rects.size()}
