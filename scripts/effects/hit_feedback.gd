class_name HitFeedback
extends RefCounted
## Shared hit feedback (Issue #51 Stage 3).
##
## knock(): asks a damaged body to take knockback along `direction` (bodies
## without apply_knockback(), e.g. test dummies, are ignored). Call it right
## after the body's take_damage(); the body decides whether it may move
## (Mage: not while dashing or dash-invulnerable; Enemy: can_be_knocked_back()).
##
## flash(): a short colour flash on a sprite through its own ShaderMaterial
## (hit_flash.gdshader), so modulate / self_modulate stay free for telegraph,
## champion, phase and slow tints. With `pop` != 1 the sprite also pops to
## `base_scale` x pop and eases back to `base_scale`. A new flash kills the
## running one first and always restarts from `base_scale`, so overlapping hits
## never leave the sprite scaled or tinted. A sprite that already has another
## material is left alone (no flash).

const SHADER := preload("res://scenes/effects/hit_flash.gdshader")
const TWEEN_META := &"hit_feedback_tween"


## Knockback for `victim` along `direction` (no-op if it has no apply_knockback()).
static func knock(victim: Object, direction: Vector2) -> void:
	if victim != null and is_instance_valid(victim) and victim.has_method(&"apply_knockback"):
		victim.call(&"apply_knockback", direction)


## Flashes `sprite` towards `color` by `strength` (0..1), fading over
## `duration` s; with `pop` != 1 and a `base_scale`, also pops its scale.
## Returns the tween (null if the sprite has a foreign material).
static func flash(sprite: CanvasItem, color: Color, strength: float, duration: float,
		base_scale := Vector2.ZERO, pop := 1.0) -> Tween:
	if sprite == null or not sprite.is_inside_tree():
		return null
	var mat := sprite.material as ShaderMaterial
	if mat == null or mat.shader != SHADER:
		if sprite.material != null:
			return null
		mat = ShaderMaterial.new()
		mat.shader = SHADER
		sprite.material = mat
	var old: Variant = sprite.get_meta(TWEEN_META) if sprite.has_meta(TWEEN_META) else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	mat.set_shader_parameter(&"flash_color", color)
	mat.set_shader_parameter(&"flash_amount", strength)
	var tween := sprite.create_tween().set_parallel()
	tween.tween_method(func(v: float) -> void: mat.set_shader_parameter(&"flash_amount", v), strength, 0.0, duration)
	var node := sprite as Node2D
	if node and pop != 1.0 and base_scale != Vector2.ZERO:
		node.scale = base_scale * pop
		tween.tween_property(node, ^"scale", base_scale, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	sprite.set_meta(TWEEN_META, tween)
	return tween


## Current flash amount of `sprite` (0 when it never flashed).
static func flash_amount(sprite: CanvasItem) -> float:
	if sprite == null:
		return 0.0
	var mat := sprite.material as ShaderMaterial
	if mat == null or mat.shader != SHADER:
		return 0.0
	return float(mat.get_shader_parameter(&"flash_amount"))


## True while a flash (or pop) of `sprite` is still running.
static func is_flashing(sprite: CanvasItem) -> bool:
	if sprite == null:
		return false
	var tween: Variant = sprite.get_meta(TWEEN_META) if sprite.has_meta(TWEEN_META) else null
	return tween is Tween and (tween as Tween).is_valid() and (tween as Tween).is_running()
