class_name RangedEnemy
extends Enemy
## Ranged enemy: keeps between `retreat_distance` and `attack_range` from its
## target and fires `projectile` toward it once per `attack_cooldown`.
## Projectile damage and speed are set here and override the Spell's values, so
## the shared Spell resource is never modified. The projectile's scene decides
## ownership (enemy_projectile.tscn damages the player side only).

## Fired by fire(); emitted with the spawned projectile.
signal fired(projectile: Projectile)

## Spell used for the projectile (scene, art, collision radius, lifetime).
@export var projectile: Spell
@export var projectile_damage: float = 8.0
## Pixels per second.
@export var projectile_speed: float = 200.0
## Backs away when the target is closer than this.
@export var retreat_distance: float = 140.0
## Spawn point offset from the feet (roughly the body centre).
@export var muzzle_offset := Vector2(0, -24)

var _spell: Spell


func _ready() -> void:
	super._ready()
	if projectile:
		_spell = projectile.duplicate() as Spell
		_spell.damage = projectile_damage
		_spell.speed = projectile_speed


func _physics_process(delta: float) -> void:
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	target = _find_target()
	velocity = Vector2.ZERO

	if target:
		var to_target := target.global_position - global_position
		var dist := to_target.length()
		facing = direction_name(to_target)
		if dist > attack_range:
			velocity = to_target.normalized() * speed
		elif dist < retreat_distance:
			velocity = -to_target.normalized() * speed
		if dist <= attack_range and _attack_cooldown_left <= 0.0:
			fire(target.global_position)

	move_and_slide()
	_play(&"walk" if velocity != Vector2.ZERO else &"idle")


## Fires one projectile toward a global position, ignoring range. Returns null
## while on cooldown, when unconfigured or when the target is on the muzzle.
func fire(at: Vector2) -> Projectile:
	if _spell == null or _spell.projectile_scene == null or _attack_cooldown_left > 0.0:
		return null
	var origin := global_position + muzzle_offset
	var dir := origin.direction_to(at)
	if dir == Vector2.ZERO:
		return null
	var shot := _spell.projectile_scene.instantiate() as Projectile
	if shot == null:
		push_error("RangedEnemy: projectile_scene root is not a Projectile")
		return null
	shot.setup(_spell, dir, self)
	var container: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	container.add_child(shot)
	shot.global_position = origin
	_attack_cooldown_left = attack_cooldown
	fired.emit(shot)
	return shot
