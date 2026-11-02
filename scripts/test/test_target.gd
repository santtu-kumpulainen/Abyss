extends StaticBody2D
## Minimal damageable target for testing attacks. Not an enemy system.
## Damage convention: any body with take_damage(amount: float) can be hit.

signal damaged(amount: float, health_left: float)

@export var max_health: float = 30.0

var health: float


func _ready() -> void:
	health = max_health


func take_damage(amount: float) -> void:
	if health <= 0.0:
		return
	health -= amount
	damaged.emit(amount, health)
	modulate = Color(1.0, 0.4, 0.4)
	create_tween().tween_property(self, ^"modulate", Color.WHITE, 0.15)
	if health <= 0.0:
		queue_free()
