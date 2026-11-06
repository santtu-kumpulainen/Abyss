class_name PixelEffect
extends Node2D
## Plays an EffectSheet once and frees itself. Spawn with PixelEffect.spawn().

var sheet: EffectSheet
var _sprite: Sprite2D
var _time := 0.0
var _fps := 60.0


## Spawns `sheet` under `parent` at `global_pos`. `duration` > 0 stretches the
## animation to that many seconds (telegraphs); `diameter` > 0 fits the 100 px
## cell to that world size. Returns null without a sheet or parent.
static func spawn(p_sheet: EffectSheet, parent: Node, global_pos: Vector2, duration: float = 0.0, diameter: float = 0.0) -> PixelEffect:
	if p_sheet == null or p_sheet.texture == null or parent == null:
		return null
	var effect := PixelEffect.new()
	effect.sheet = p_sheet
	effect._fps = p_sheet.frame_count / duration if duration > 0.0 else p_sheet.fps
	effect.z_index = 5
	parent.add_child(effect)
	effect.global_position = global_pos
	var sprite := Sprite2D.new()
	sprite.texture = p_sheet.texture
	sprite.hframes = p_sheet.columns
	sprite.vframes = maxi(int(p_sheet.texture.get_height() / 100.0), 1)
	sprite.frame = p_sheet.first_frame
	sprite.modulate = p_sheet.tint
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * (diameter / 100.0 if diameter > 0.0 else p_sheet.scale)
	effect.add_child(sprite)
	effect._sprite = sprite
	return effect


## Seconds the animation takes.
func total_time() -> float:
	return sheet.frame_count / maxf(_fps, 0.001)


func _process(delta: float) -> void:
	_time += delta
	var index := int(_time * _fps)
	if index >= sheet.frame_count:
		queue_free()
		return
	_sprite.frame = sheet.first_frame + index
