class_name Spell
extends Resource
## Data for one castable spell. Add a new spell by creating another Spell
## resource; a SpellCaster casts whichever Spell is assigned to it.

## Stable identifier, e.g. for future unlock/save data.
@export var id: StringName
@export var display_name: String

@export_group("Projectile")
## Scene to spawn; its root must be a Projectile (see scenes/spells/projectile.tscn).
@export var projectile_scene: PackedScene
## Projectile animation frames and the animation to play.
@export var frames: SpriteFrames
@export var animation: StringName = &"default"
## Scale applied to the projectile sprite (source art may be much larger than the game).
@export var visual_scale: float = 1.0
## Hit radius in pixels (world space).
@export var collision_radius: float = 8.0
## Rotate the sprite to the flight direction (for directional art like comets/arrows).
@export var rotate_to_direction: bool = false
## Direction the source art points, in degrees (0 = right, 180 = left).
@export var art_angle_degrees: float = 0.0

@export_group("Effects")
## Played at the caster when the spell is cast / where a projectile hits.
@export var cast_effect: EffectSheet
@export var impact_effect: EffectSheet

@export_group("Stats")
@export var damage: float = 10.0
## Pixels per second.
@export var speed: float = 300.0
## Seconds between casts.
@export var cooldown: float = 0.4
## Seconds before an unhit projectile is removed.
@export var lifetime: float = 1.5

@export_group("Bounces")
## Walls ("world" layer) the projectile bounces off before the next wall ends
## it (0 = it ends at the first wall, like every spell so far).
@export var max_bounces: int = 0
## Played where the projectile bounces off a wall (sized to its hit area).
@export var bounce_effect: EffectSheet
