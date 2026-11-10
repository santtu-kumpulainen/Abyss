class_name PixelEffect
extends Node2D
## Plays an EffectSheet and frees itself: once, or (EffectSheet.loop) until
## stop(). Spawn with PixelEffect.spawn() or EffectLibrary.spawn().

var sheet: EffectSheet
var _sprite: Sprite2D
var _time := 0.0
var _fps := 60.0
var _stopping := false


## Spawns `sheet` under `parent` at `global_pos`. `duration` > 0 stretches one
## pass of the animation to that many seconds (telegraphs); `diameter` > 0 fits
## one cell's width to that world size. Returns null without a sheet or parent.
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
	# Frames are cut by region, so padded sheets (cells not filling the texture) work too.
	sprite.region_enabled = true
	sprite.region_rect = p_sheet.frame_rect(p_sheet.first_frame)
	sprite.modulate = p_sheet.tint
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2.ONE * (diameter / float(p_sheet.frame_size.x) if diameter > 0.0 else p_sheet.scale)
	effect.add_child(sprite)
	effect._sprite = sprite
	return effect


## Seconds one pass of the animation takes.
func total_time() -> float:
	return sheet.frame_count / maxf(_fps, 0.001)


## Ends the effect: fades it out over `fade` seconds (0 = at once), then frees it.
## Safe to call more than once.
func stop(fade: float = 0.0) -> void:
	if _stopping or is_queued_for_deletion():
		return
	_stopping = true
	if fade <= 0.0:
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(self, ^"modulate:a", 0.0, fade)
	tween.tween_callback(queue_free)


## The sprite showing the frames (for callers that scale or tint it).
func sprite() -> Sprite2D:
	return _sprite


func _process(delta: float) -> void:
	_time += delta
	var index := int(_time * _fps)
	if index >= sheet.frame_count:
		if not sheet.loop:
			queue_free()
			return
		index %= sheet.frame_count
	_sprite.region_rect = sheet.frame_rect(sheet.first_frame + index)


## Index of the sheet cell currently shown.
func current_frame() -> int:
	var index := int(_time * _fps)
	return sheet.first_frame + (index % sheet.frame_count if sheet.loop else mini(index, sheet.frame_count - 1))
