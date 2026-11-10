extends SceneTree
## Builds a SpriteFrames resource from the Mage Hero 128 per-frame PNGs.
##
## Usage (run after the textures have been imported):
##   godot --headless --path . --script res://tools/build_mage_sprite_frames.gd
##
## Output: res://scenes/mage/sprite_frames/mage.tres
## Animations: "<action>_<direction>", e.g. "idle_south", "walk_north_east".
## "dash_<direction>" (Issue #49) is built from the walk frames: every
## DASH_FRAME_STEP-th frame at DASH_FPS, played once (the pack has no dash).
##
## If the output already exists, only the dash animations are (re)built from
## its walk frames, so the idle/walk data, resource ids and uid stay unchanged.
## Pass `-- --rebuild` to rebuild everything from the PNGs (new resource ids).
##
## Frames are 168x168, except the north frames, which are 164x164. Smaller
## frames are padded (AtlasTexture margin) to the largest frame size, anchored
## bottom-centre, so every frame shares one canvas and ground line. Feet sit
## about 24 px above the canvas bottom, so on a centred AnimatedSprite2D use
## offset = Vector2(0, -60) to put the feet at the node origin.

const SOURCE_DIR := "res://assets/characters/mage/mage-hero-128/"
const OUTPUT_PATH := "res://scenes/mage/sprite_frames/mage.tres"
const FPS := 12.0

## Pack direction folder suffixes (clockwise from south).
const DIRECTIONS: Array[String] = [
	"south", "south-east", "east", "north-east",
	"north", "north-west", "west", "south-west",
]
const ACTIONS: Array[String] = ["idle", "walk"]
## Dash animation: every DASH_FRAME_STEP-th walk frame, played once at DASH_FPS
## (about 0.15 s, the dash burst).
const DASH_FRAME_STEP := 2
const DASH_FPS := 40.0


func _init() -> void:
	quit(_build())


func _build() -> int:
	var rebuild := OS.get_cmdline_user_args().has("--rebuild")
	if not rebuild and ResourceLoader.exists(OUTPUT_PATH):
		var existing := load(OUTPUT_PATH) as SpriteFrames
		if existing == null:
			push_error("Failed to load %s" % OUTPUT_PATH)
			return 1
		if not add_dash_animations(existing):
			return 1
		return _save(existing)

	# Load every frame first so the shared canvas size is known.
	var sources := {}  # anim name -> Array[Texture2D]
	var canvas := Vector2i.ZERO
	for action in ACTIONS:
		for dir in DIRECTIONS:
			var folder := SOURCE_DIR + "%s_%s/" % [action, dir]
			var files := Array(DirAccess.get_files_at(folder)).filter(
				func(f: String) -> bool: return f.ends_with(".png"))
			files.sort()
			if files.is_empty():
				push_error("No frames in %s" % folder)
				return 1
			var textures: Array[Texture2D] = []
			for f: String in files:
				var tex := load(folder + f) as Texture2D
				if tex == null:
					push_error("Failed to load %s" % (folder + f))
					return 1
				canvas = canvas.max(Vector2i(tex.get_size()))
				textures.append(tex)
			sources["%s_%s" % [action, dir.replace("-", "_")]] = textures

	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for anim: String in sources:
		frames.add_animation(anim)
		frames.set_animation_speed(anim, FPS)
		frames.set_animation_loop(anim, true)
		for tex: Texture2D in sources[anim]:
			frames.add_frame(anim, _pad_bottom_centre(tex, canvas))
	if not add_dash_animations(frames):
		return 1
	return _save(frames)


## (Re)creates "dash_<direction>" in `frames` from its "walk_<direction>"
## frames (the same textures, no copies). False if a walk animation is missing.
static func add_dash_animations(frames: SpriteFrames) -> bool:
	for dir in DIRECTIONS:
		var walk := StringName("walk_" + dir.replace("-", "_"))
		var dash := StringName("dash_" + dir.replace("-", "_"))
		if not frames.has_animation(walk) or frames.get_frame_count(walk) == 0:
			push_error("Missing animation %s" % walk)
			return false
		if frames.has_animation(dash):
			frames.remove_animation(dash)
		frames.add_animation(dash)
		frames.set_animation_speed(dash, DASH_FPS)
		frames.set_animation_loop(dash, false)
		for i in range(0, frames.get_frame_count(walk), DASH_FRAME_STEP):
			frames.add_frame(dash, frames.get_frame_texture(walk, i))
	return true


func _save(frames: SpriteFrames) -> int:
	DirAccess.make_dir_recursive_absolute(OUTPUT_PATH.get_base_dir())
	var own_uid := ResourceLoader.get_resource_uid(OUTPUT_PATH)
	var err := ResourceSaver.save(frames, OUTPUT_PATH)
	# A --script save writes no uids: keep the file's own and the textures'.
	if err == OK and own_uid != ResourceUID.INVALID_ID:
		err = ResourceSaver.set_uid(OUTPUT_PATH, own_uid)
	if err == OK:
		err = _add_ext_resource_uids(OUTPUT_PATH)
	if err != OK:
		push_error("Failed to save %s (error %d)" % [OUTPUT_PATH, err])
		return 1
	print("Saved %s with %d animations" % [OUTPUT_PATH, frames.get_animation_names().size()])
	return 0


## Returns tex unchanged if it already fills the canvas, otherwise an
## AtlasTexture padded to the canvas with its bottom edge and centre aligned.
static func _pad_bottom_centre(tex: Texture2D, canvas: Vector2i) -> Texture2D:
	var size := Vector2i(tex.get_size())
	if size == canvas:
		return tex
	var pad := canvas - size
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(Vector2.ZERO, size)
	atlas.margin = Rect2(pad.x * 0.5, pad.y, pad.x, pad.y)
	return atlas


## Adds `uid="uid://..."` (from each file's .import) to the ext_resource lines
## of the text resource at `path` that have none, as the editor writes them.
static func _add_ext_resource_uids(path: String) -> Error:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return ERR_FILE_CANT_READ
	var regex := RegEx.create_from_string("\\[ext_resource type=\"(\\w+)\" path=\"([^\"]+)\"")
	var lines := text.split("\n")
	for i in lines.size():
		var found := regex.search(lines[i])
		if found == null:
			continue
		var uid := ResourceLoader.get_resource_uid(found.get_string(2))
		if uid != ResourceUID.INVALID_ID:
			lines[i] = lines[i].replace(found.get_string(0), "[ext_resource type=\"%s\" uid=\"%s\" path=\"%s\"" % [
					found.get_string(1), ResourceUID.id_to_text(uid), found.get_string(2)])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("\n".join(lines))
	return OK
