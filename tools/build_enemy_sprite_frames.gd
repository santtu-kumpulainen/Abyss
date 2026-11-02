extends SceneTree
## Builds a SpriteFrames resource from a Craftpix enemy pack's PNG sequences
## (assets/characters/enemies/<Character>/PNG/PNG Sequences/<View> - <Action>/).
##
## Usage (run after the textures have been imported):
##   godot --headless --path . --script res://tools/build_enemy_sprite_frames.gd -- "Giant Goblin" giant_goblin
##
## Output: res://scenes/enemies/sprite_frames/<output_name>.tres
## Animations: "<action>_<direction>" with down/left/right/up, e.g. "walk_left".
## Only the folders listed in ACTIONS are used; keep other folders excluded
## from import with .gdignore.

const SOURCE_DIR := "res://assets/characters/enemies/%s/PNG/PNG Sequences/"
const OUTPUT_PATH := "res://scenes/enemies/sprite_frames/%s.tres"

## direction -> pack view name
const DIRECTIONS := {"down": "Front", "left": "Left", "right": "Right", "up": "Back"}

## animation name -> [pack action name, fps, loop]
const ACTIONS := {
	"idle": ["Idle", 16.0, true],
	"walk": ["Walking", 24.0, true],
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: -- \"<Character folder>\" <output_name>")
		quit(1)
		return
	quit(_build(args[0], args[1]))


func _build(character: String, output_name: String) -> int:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")

	for action: String in ACTIONS:
		var info: Array = ACTIONS[action]
		for dir: String in DIRECTIONS:
			var folder_name := "%s - %s" % [DIRECTIONS[dir], info[0]]
			var folder := SOURCE_DIR % character + folder_name + "/"
			var files := Array(DirAccess.get_files_at(folder)).filter(
				func(f: String) -> bool: return f.ends_with(".png"))
			files.sort()
			if files.is_empty():
				push_error("No frames in %s" % folder)
				return 1
			var anim := StringName("%s_%s" % [action, dir])
			frames.add_animation(anim)
			frames.set_animation_speed(anim, info[1])
			frames.set_animation_loop(anim, info[2])
			for f: String in files:
				var tex := load(folder + f) as Texture2D
				if tex == null:
					push_error("Failed to load %s (is it imported?)" % (folder + f))
					return 1
				frames.add_frame(anim, tex)

	var out := OUTPUT_PATH % output_name
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := ResourceSaver.save(frames, out)
	if err != OK:
		push_error("Failed to save %s (error %d)" % [out, err])
		return 1
	print("Saved %s with %d animations" % [out, frames.get_animation_names().size()])
	return 0
