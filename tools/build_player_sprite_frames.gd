extends SceneTree
## Builds a SpriteFrames resource from the Craftpix Swordsman "With_shadow" sheets.
##
## Usage (run after the textures have been imported):
##   godot --headless --path . --script res://tools/build_player_sprite_frames.gd -- 1
##
## The trailing number is the player visual level (1, 2 or 3). Output:
##   res://scenes/player/sprite_frames/player_level_<N>.tres

const FRAME_SIZE := 64
const SOURCE_DIR := "res://assets/characters/player/level_%d/With_shadow/"
const OUTPUT_PATH := "res://scenes/player/sprite_frames/player_level_%d.tres"

## Sheet rows, top to bottom.
const DIRECTIONS: Array[String] = ["down", "left", "right", "up"]

## animation name -> [sheet name in the original filename, frame count, fps, loop]
const ACTIONS := {
	"idle": ["Idle", 12, 8.0, true],
	"walk": ["Walk", 6, 10.0, true],
	"run": ["Run", 8, 12.0, true],
	"attack": ["attack", 8, 14.0, false],
	"walk_attack": ["Walk_Attack", 6, 12.0, false],
	"run_attack": ["Run_Attack", 8, 14.0, false],
	"hurt": ["Hurt", 5, 10.0, false],
	"death": ["Death", 7, 10.0, false],
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var level := int(args[0]) if args.size() > 0 else 1
	quit(_build(level))


func _build(level: int) -> int:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")

	for action: String in ACTIONS:
		var info: Array = ACTIONS[action]
		var path := SOURCE_DIR % level + "Swordsman_lvl%d_%s_with_shadow.png" % [level, info[0]]
		var sheet := load(path) as Texture2D
		if sheet == null:
			push_error("Missing sprite sheet: %s" % path)
			return 1
		var frame_count: int = info[1]
		if sheet.get_width() != frame_count * FRAME_SIZE or sheet.get_height() != DIRECTIONS.size() * FRAME_SIZE:
			push_error("Unexpected sheet size %s for %s" % [sheet.get_size(), path])
			return 1

		for row in DIRECTIONS.size():
			var anim := StringName("%s_%s" % [action, DIRECTIONS[row]])
			frames.add_animation(anim)
			frames.set_animation_speed(anim, info[2])
			frames.set_animation_loop(anim, info[3])
			for i in frame_count:
				var atlas := AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = Rect2(i * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
				frames.add_frame(anim, atlas)

	var out := OUTPUT_PATH % level
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := ResourceSaver.save(frames, out)
	if err != OK:
		push_error("Failed to save %s (error %d)" % [out, err])
		return 1
	print("Saved %s with %d animations" % [out, frames.get_animation_names().size()])
	return 0
