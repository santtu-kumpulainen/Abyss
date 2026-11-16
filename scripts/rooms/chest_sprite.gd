class_name ChestSprite
extends Sprite2D
## One chest from the Oubliette chest sheet (assets/environment/oubliette_chests,
## CC0). The sheet is a static grid of CELL_PITCH px cells with an opaque grey
## background and light separators and no opening frames, so this sprite cuts
## `cell` out with an AtlasTexture and a small shader discards the background
## colours (the original files stay untouched). `opened` dims the chest, since
## the pack has no open-lid sprite.

const SHEET := preload("res://assets/environment/oubliette_chests/chests.PNG")
## Grid pitch of the sheet (22 px cell + 1 px separator).
const CELL_PITCH := 23
const CELL_SIZE := 22
## Sheet cells used by the game (column, row).
const LOOT_CELL := Vector2i(0, 0)
const TREASURE_CELL := Vector2i(2, 1)
const OPENED_TINT := Color(0.5, 0.46, 0.44)

const _KEY_SHADER := """
shader_type canvas_item;
// Sheet background (215 grey), separators (235 grey) and the white border.
const vec3 KEYS[3] = vec3[](vec3(0.8431), vec3(0.9216), vec3(1.0));
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	for (int i = 0; i < 3; i++) {
		if (distance(t.rgb, KEYS[i]) < 0.012) {
			discard;
		}
	}
	if (t.a < 0.01) {
		discard;
	}
}
"""

static var _shader: Shader

## Sheet cell (column, row) to show.
@export var cell := LOOT_CELL:
	set(value):
		cell = value
		_apply_cell()

## Dims the chest to show it was emptied.
@export var opened := false:
	set(value):
		opened = value
		modulate = OPENED_TINT if opened else Color.WHITE


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2(3.0, 3.0)
	# The chest art sits low in its cell: lift it so its base rests on the origin.
	offset = Vector2(0.0, -9.0)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = _KEY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	material = mat
	_apply_cell()


## Pixel rectangle of sheet cell `c` (inside its separators).
static func region_of(c: Vector2i) -> Rect2:
	return Rect2(c.x * CELL_PITCH + 1, c.y * CELL_PITCH + 1, CELL_SIZE, CELL_SIZE)


func _apply_cell() -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = SHEET
	atlas.region = region_of(cell)
	texture = atlas
