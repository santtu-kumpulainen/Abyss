extends SceneTree
## Builds a SpriteFrames resource from the Mage Hero 128 per-frame PNGs.
##
## Usage (run after the textures have been imported):
##   godot --headless --path . --script res://tools/build_mage_sprite_frames.gd
##
## Output: res://scenes/mage/sprite_frames/mage.tres
## Animations: "<action>_<direction>", e.g. "idle_south", "walk_north_east".
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


func _init() -> void:
	quit(_build())


func _build() -> int:
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

	DirAccess.make_dir_recursive_absolute(OUTPUT_PATH.get_base_dir())
	var err := ResourceSaver.save(frames, OUTPUT_PATH)
	if err != OK:
		push_error("Failed to save %s (error %d)" % [OUTPUT_PATH, err])
		return 1
	print("Saved %s with %d animations, canvas %s" % [OUTPUT_PATH, frames.get_animation_names().size(), canvas])
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
