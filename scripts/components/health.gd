class_name Health
extends Node
## Reusable hit points. Add as a child node and forward take_damage() to it.

signal damaged(amount: float, current: float)
signal died
## Emitted when max/current health changes other than by damage (e.g. level-up).
signal changed(current: float)

@export var max_health: float = 100.0

var current: float


func _ready() -> void:
	current = max_health


func take_damage(amount: float) -> void:
	if is_dead() or amount <= 0.0:
		return
	current = maxf(current - amount, 0.0)
	damaged.emit(amount, current)
	if is_dead():
		died.emit()


## Raises max_health by `amount` and restores `heal_amount` (capped at max).
## Does nothing once dead.
func increase_max_health(amount: float, heal_amount: float = 0.0) -> void:
	if is_dead():
		return
	max_health += maxf(amount, 0.0)
	current = minf(current + maxf(heal_amount, 0.0), max_health)
	changed.emit(current)


## Multiplies max_health by `multiplier`, keeping the current/max ratio
## (run modifiers applied at spawn/run start). Does nothing once dead.
func scale_max_health(multiplier: float) -> void:
	if is_dead() or multiplier <= 0.0:
		return
	var ratio := current / max_health if max_health > 0.0 else 1.0
	max_health *= multiplier
	current = max_health * ratio
	changed.emit(current)


func is_dead() -> bool:
	return current <= 0.0
