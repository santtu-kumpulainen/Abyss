class_name Health
extends Node
## Reusable hit points. Add as a child node and forward take_damage() to it.

signal damaged(amount: float, current: float)
signal died

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


func is_dead() -> bool:
	return current <= 0.0
