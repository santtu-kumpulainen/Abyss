extends SceneTree
## Builds a side-view SpriteFrames resource from a Tiny RPG Character Asset Pack
## character (horizontal strips of 100x100 frames: <Name>_Idle.png, <Name>_Walk.png...).
##
## Usage (run after the textures have been imported):
##   godot --headless --path . --script res://tools/build_tiny_rpg_sprite_frames.gd -- "<res:// strip folder>" "<Name>" <output_name>
##
## Output: res://scenes/enemies/sprite_frames/<output_name>.tres
## Animations: "idle", "walk" and the one-shot "death" (Issue #51, played by
## EnemyCorpse), facing right (Enemy.side_view mirrors them).

const OUTPUT_PATH := "res://scenes/enemies/sprite_frames/%s.tres"
const FRAME_SIZE := Vector2(100, 100)

## animation name -> [strip suffix, fps, loop]
const ACTIONS := {
	"idle": ["Idle", 8.0, true],
	"walk": ["Walk", 10.0, true],
	"death": ["Death", 8.0, false],
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("Usage: -- \"<strip folder>\" \"<Name>\" <output_name>")
		quit(1)
		return
	quit(_build(args[0], args[1], args[2]))


func _build(folder: String, character: String, output_name: String) -> int:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")

	for action: String in ACTIONS:
		var info: Array = ACTIONS[action]
		var path := "%s/%s_%s.png" % [folder.trim_suffix("/"), character, info[0]]
		var sheet := load(path) as Texture2D
		if sheet == null:
			push_error("Failed to load %s (is it imported?)" % path)
			return 1
		frames.add_animation(action)
		frames.set_animation_speed(action, info[1])
		frames.set_animation_loop(action, info[2])
		for i in int(sheet.get_width() / FRAME_SIZE.x):
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(Vector2(i * FRAME_SIZE.x, 0), FRAME_SIZE)
			frames.add_frame(action, atlas)

	var out := OUTPUT_PATH % output_name
	var err := ResourceSaver.save(frames, out)
	if err != OK:
		push_error("Failed to save %s (error %d)" % [out, err])
		return 1
	print("Saved %s with %d animations" % [out, frames.get_animation_names().size()])
	return 0
