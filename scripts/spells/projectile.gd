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

## Emitted once when the projectile damages a body (calls its take_damage()).
signal hit(body: Node)

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
	if spell.rotate_to_direction:
		_sprite.rotation = direction.angle() - deg_to_rad(spell.art_angle_degrees)


func _physics_process(delta: float) -> void:
	global_position += direction * spell.speed * delta
	_age += delta
	if _age >= spell.lifetime:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if _spent or body == source or _is_friendly(body):
		return
	_spent = true
	if body.has_method(&"take_damage"):
		body.take_damage(spell.damage)
		hit.emit(body)
	set_deferred(&"monitoring", false)
	queue_free()


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
