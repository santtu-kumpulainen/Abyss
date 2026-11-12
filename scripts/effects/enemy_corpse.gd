class_name EnemyCorpse
extends Node2D
## Detached death visual of an enemy (Issue #51 Stage 4). The gameplay Enemy is
## freed at the moment of death; this copy of its sprite (frames, scale,
## offset, mirroring and self_modulate tint) plays the one-shot death
## animation, holds the last frame for HOLD_TIME s, fades out over FADE_TIME s
## and frees itself. It has no collision, no groups other than "enemy_corpses"
## and no gameplay interaction, so it never delays room clear or rewards.
## MAX_LIFETIME is a safety net in case the animation never finishes.

const GROUP := &"enemy_corpses"
const HOLD_TIME := 0.25
const FADE_TIME := 0.35
const MAX_LIFETIME := 4.0

## The animation played (e.g. &"death").
var animation: StringName
var _sprite: AnimatedSprite2D
var _age := 0.0
var _fading := false


## Spawns the corpse of `sprite` (the dying enemy's AnimatedSprite2D) under
## `parent`, playing `death_<facing>` or `death`. Returns null (nothing
## spawned) if the sprite has no such animation.
static func spawn(sprite: AnimatedSprite2D, parent: Node, facing: StringName = &"") -> EnemyCorpse:
	if sprite == null or parent == null or sprite.sprite_frames == null:
		return null
	var anim := death_animation(sprite.sprite_frames, facing)
	if anim == &"":
		return null
	var corpse := EnemyCorpse.new()
	corpse.animation = anim
	corpse.z_index = sprite.get_parent().z_index if sprite.get_parent() is CanvasItem else 0
	var copy := AnimatedSprite2D.new()
	copy.sprite_frames = sprite.sprite_frames
	copy.scale = sprite.scale
	copy.offset = sprite.offset
	copy.position = sprite.position
	copy.centered = sprite.centered
	copy.flip_h = sprite.flip_h
	copy.self_modulate = sprite.self_modulate
	copy.texture_filter = sprite.texture_filter
	corpse.add_child(copy)
	corpse._sprite = copy
	parent.add_child(corpse)
	corpse.global_position = (sprite.get_parent() as Node2D).global_position
	copy.animation_finished.connect(corpse._on_animation_finished)
	copy.play(anim)
	return corpse


## The death animation of `frames` for `facing` (&"" if there is none).
static func death_animation(frames: SpriteFrames, facing: StringName = &"") -> StringName:
	if frames == null:
		return &""
	var directional := StringName("death_%s" % facing)
	if facing != &"" and frames.has_animation(directional):
		return directional
	return &"death" if frames.has_animation(&"death") else &""


## The animated copy of the enemy sprite.
func sprite() -> AnimatedSprite2D:
	return _sprite


func _ready() -> void:
	add_to_group(GROUP)


func _process(delta: float) -> void:
	_age += delta
	if _age >= MAX_LIFETIME:
		queue_free()


func _on_animation_finished() -> void:
	if _fading:
		return
	_fading = true
	var tween := create_tween()
	tween.tween_interval(HOLD_TIME)
	tween.tween_property(self, ^"modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(queue_free)
