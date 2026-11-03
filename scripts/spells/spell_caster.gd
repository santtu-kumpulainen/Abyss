class_name SpellCaster
extends Marker2D
## Casts the assigned Spell from this node's position. Changing `spell`
## (e.g. from a future upgrade/unlock) changes what is cast; no other code needs
## to change. The parent node is passed to projectiles as their source.
## Run modifiers (set_modifiers()) apply to a per-caster copy of `spell`, so the
## shared Spell resource is never modified.

signal cast(projectile: Projectile)

@export var spell: Spell:
	set(value):
		spell = value
		_rebuild_cast_spell()

## Multiplies the spell's damage (1.0 = unchanged).
var damage_multiplier := 1.0
## Multiplies the spell's cooldown (1.0 = unchanged, lower = faster).
var cooldown_multiplier := 1.0

var _cooldown_left := 0.0
## `spell` with the modifiers applied (`spell` itself when unmodified).
var _cast_spell: Spell


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


func can_cast() -> bool:
	return _cast_spell != null and _cast_spell.projectile_scene != null and _cooldown_left <= 0.0


func set_modifiers(p_damage_multiplier: float, p_cooldown_multiplier: float) -> void:
	damage_multiplier = maxf(p_damage_multiplier, 0.0)
	cooldown_multiplier = maxf(p_cooldown_multiplier, 0.0)
	_rebuild_cast_spell()


## The Spell actually cast (with modifiers applied).
func get_cast_spell() -> Spell:
	return _cast_spell


## Fires toward a global position. Returns the projectile, or null if on
## cooldown, unconfigured or the target is on top of the cast point.
func try_cast(target: Vector2) -> Projectile:
	var dir := global_position.direction_to(target)
	if not can_cast() or dir == Vector2.ZERO:
		return null
	var projectile := _cast_spell.projectile_scene.instantiate() as Projectile
	if projectile == null:
		push_error("Spell %s: projectile_scene root is not a Projectile" % spell.id)
		return null
	projectile.setup(_cast_spell, dir, get_parent())
	var container: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	container.add_child(projectile)
	projectile.global_position = global_position
	_cooldown_left = _cast_spell.cooldown
	cast.emit(projectile)
	return projectile


func _rebuild_cast_spell() -> void:
	if spell == null or (is_equal_approx(damage_multiplier, 1.0) and is_equal_approx(cooldown_multiplier, 1.0)):
		_cast_spell = spell
		return
	_cast_spell = spell.duplicate() as Spell
	_cast_spell.damage = spell.damage * damage_multiplier
	_cast_spell.cooldown = spell.cooldown * cooldown_multiplier
