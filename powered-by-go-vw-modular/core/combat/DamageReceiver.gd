class_name DamageReceiver
extends Node

## Attach as a child named DamageReceiver to a hit collider.
## Entity mods may subclass receive_damage; health/death policy belongs to them.
signal damaged(amount: float, context: Dictionary)
signal depleted(context: Dictionary)
@export var health: float = 100.0

func receive_damage(amount: float, context: Dictionary) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	var applied: float = minf(health, amount)
	health -= applied
	damaged.emit(applied, context)
	if health <= 0.0:
		depleted.emit(context)

static func deliver(collider: Object, amount: float, context: Dictionary) -> bool:
	if not is_instance_valid(collider) or not collider is Node:
		return false
	var receiver: DamageReceiver = (collider as Node).get_node_or_null("DamageReceiver") as DamageReceiver
	if receiver == null:
		return false
	receiver.receive_damage(amount, context)
	return true
