class_name SpellCaster
extends Marker2D
## Casts the assigned Spell from this node's position. Changing `spell`
## (e.g. from a future upgrade/unlock) changes what is cast; no other code needs
## to change. The parent node is passed to projectiles as their source.

signal cast(projectile: Projectile)

@export var spell: Spell

var _cooldown_left := 0.0


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


func can_cast() -> bool:
	return spell != null and spell.projectile_scene != null and _cooldown_left <= 0.0


## Fires toward a global position. Returns the projectile, or null if on
## cooldown, unconfigured or the target is on top of the cast point.
func try_cast(target: Vector2) -> Projectile:
	var dir := global_position.direction_to(target)
	if not can_cast() or dir == Vector2.ZERO:
		return null
	var projectile := spell.projectile_scene.instantiate() as Projectile
	if projectile == null:
		push_error("Spell %s: projectile_scene root is not a Projectile" % spell.id)
		return null
	projectile.setup(spell, dir, get_parent())
	var container: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	container.add_child(projectile)
	projectile.global_position = global_position
	_cooldown_left = spell.cooldown
	cast.emit(projectile)
	return projectile
