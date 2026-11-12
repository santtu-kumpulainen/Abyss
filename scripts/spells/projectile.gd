class_name Projectile
extends Area2D
## Straight-flying spell projectile configured by a Spell resource.
## Hits the first world body, damageable target or hurtbox it touches (calling
## take_damage() once if the body has it), then frees itself. Never hits its
## source or its own side. Ownership is set per scene with `hostile_to_player`:
## - false (projectile.tscn): player spell; layer "player_projectiles",
##   mask "world" + "enemies"; never hits player characters.
## - true (enemy_projectile.tscn): enemy attack; layer "enemy_projectiles",
##   mask "world" + "player"; never hits enemies.
## Bounces (Issue #51): a spell with `max_bounces` > 0 reflects off walls (the
## "world" layer, found by a ray along each tick's path) that many times; the
## next wall then ends it like any projectile. It still damages at most once.
## Every projectile is removed after `spell.lifetime`, and also when it leaves
## `bounds` (if set, e.g. its room's floor) by more than BOUNDS_MARGIN; a
## bouncing projectile that ends this way still plays its impact effect.

## Emitted once when the projectile damages a body (calls its take_damage()).
signal hit(body: Node)
## Emitted when it bounces off a wall, at the bounce point.
signal bounced(at: Vector2)

## Physics layer of walls, doors and obstacles (project layer 1, "world").
const WORLD_MASK := 1
## How far outside `bounds` the projectile may get before it is removed.
const BOUNDS_MARGIN := 48.0

## Which side this projectile damages (see above).
@export var hostile_to_player := false

var spell: Spell
var direction := Vector2.RIGHT
## The node that cast this projectile; always ignored.
var source: Node

var _age := 0.0
var _spent := false

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _shape: CollisionShape2D = $CollisionShape2D


## Multiplies the spell's damage for this projectile only (Twin Cast: 0.7); the
## shared Spell resource is never changed.
var damage_factor := 1.0
## If > 0 and the victim has a `health` (Health), the hit deals this fraction of
## the victim's CURRENT max HP instead of the spell's damage (boss bolts); no
## other damage multiplier is applied to such a hit.
var max_hp_fraction := 0.0
## Global area the projectile must stay in (empty = no limit). Set before or
## after adding it to the tree.
var bounds := Rect2()

var _bounces_left := 0


## Call before adding the projectile to the tree.
func setup(p_spell: Spell, p_direction: Vector2, p_source: Node) -> void:
	spell = p_spell
	direction = p_direction.normalized()
	source = p_source


func _ready() -> void:
	if spell == null:
		push_warning("Projectile spawned without a Spell")
		queue_free()
		return
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	if spell.frames:
		_sprite.sprite_frames = spell.frames
		_sprite.play(spell.animation)
	_sprite.scale = Vector2.ONE * spell.visual_scale
	var circle := CircleShape2D.new()
	circle.radius = spell.collision_radius
	_shape.shape = circle
	_bounces_left = maxi(spell.max_bounces, 0)
	_face_direction()


## Wall bounces left before the next wall ends the projectile.
func bounces_left() -> int:
	return _bounces_left


func _physics_process(delta: float) -> void:
	var step := direction * spell.speed * delta
	if _bounces_left > 0:
		step = _bounce_step(step)
	global_position += step
	_age += delta
	if _age >= spell.lifetime or _outside_bounds():
		_expire()


## This tick's movement, or zero after reflecting off a wall on the way: the
## projectile is put back just off the wall, facing the reflected direction.
func _bounce_step(step: Vector2) -> Vector2:
	var to := global_position + step + direction * spell.collision_radius
	var query := PhysicsRayQueryParameters2D.create(global_position, to, WORLD_MASK)
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return step
	var normal: Vector2 = result["normal"]
	if normal == Vector2.ZERO:
		return step
	_bounce(normal, result["position"])
	global_position = (result["position"] as Vector2) + normal * (spell.collision_radius + 1.0)
	return Vector2.ZERO


func _bounce(normal: Vector2, at: Vector2) -> void:
	direction = direction.bounce(normal).normalized()
	_bounces_left -= 1
	_face_direction()
	if spell.bounce_effect:
		PixelEffect.spawn(spell.bounce_effect, get_parent(), at, 0.0, spell.collision_radius * 4.0)
	bounced.emit(at)


func _face_direction() -> void:
	if spell.rotate_to_direction:
		_sprite.rotation = direction.angle() - deg_to_rad(spell.art_angle_degrees)


## Lifetime / bounds end. Bouncing spells burst visibly instead of vanishing.
func _expire() -> void:
	if _spent:
		return
	_spent = true
	if spell.max_bounces > 0 and spell.impact_effect:
		PixelEffect.spawn(spell.impact_effect, get_parent(), global_position)
	set_deferred(&"monitoring", false)
	queue_free()


func _outside_bounds() -> bool:
	return bounds.has_area() and not bounds.grow(BOUNDS_MARGIN).has_point(global_position)


func _on_body_entered(body: Node) -> void:
	if _spent or body == source or _is_friendly(body):
		return
	if _bounces_left > 0 and not body.has_method(&"take_damage"):
		# A wall the path ray missed (e.g. a corner graze): bounce straight back.
		_bounce(-direction, global_position)
		return
	_spent = true
	if spell.impact_effect:
		PixelEffect.spawn(spell.impact_effect, get_parent(), global_position)
	if body.has_method(&"take_damage"):
		body.take_damage(_damage_for(body))
		HitFeedback.knock(body, direction)
		hit.emit(body)
	set_deferred(&"monitoring", false)
	queue_free()


func _damage_for(body: Node) -> float:
	if max_hp_fraction > 0.0:
		var victim_health = body.get(&"health")
		if victim_health is Health:
			return (victim_health as Health).max_health * max_hp_fraction
	return spell.damage * damage_factor


## Hurtbox areas (e.g. an enemy's body-sized Area2D) count as hits on their parent.
func _on_area_entered(area: Area2D) -> void:
	_on_body_entered(area.get_parent())


func _is_friendly(body: Node) -> bool:
	if hostile_to_player:
		return body is Enemy or body.is_in_group(&"enemies")
	return _is_player_character(body)


## Safety net on top of the collision mask: the Swordsman still uses the
## default "world" layer, so player characters are also excluded here.
static func _is_player_character(body: Node) -> bool:
	return body is Player or body is Mage or body.is_in_group(&"player")
