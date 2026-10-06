class_name ItemInstanceService
extends RefCounted

## Definition stats plus bounded, data-defined modifiers and individual condition.
var content: ContentRegistry
var modifiers: Dictionary = {}

func _init(registry: ContentRegistry) -> void:
	content = registry

func register_modifier(id: String, stat: String, add: float = 0.0, multiply: float = 1.0) -> void:
	if not id.contains(":") or not is_finite(add) or not is_finite(multiply):
		return
	modifiers[id] = {"stat": stat, "add": clampf(add, -1000.0, 1000.0), "multiply": clampf(multiply, 0.1, 10.0)}

func durable(item_id: String) -> bool:
	return int(content.get_item(item_id).get("properties", {}).get("max_durability", 0)) > 0

func stats(stack: Dictionary) -> Dictionary:
	var result: Dictionary = content.get_item(str(stack.get("id", ""))).get("properties", {}).duplicate(true)
	var adds := {}
	var multiples := {}
	var seen := {}
	var values: Variant = stack.get("metadata", {}).get("modifiers", [])
	if values is Array:
		for id in values.slice(0, 4):
			if not modifiers.has(str(id)) or seen.has(str(id)):
				continue
			seen[str(id)] = true
			var modifier: Dictionary = modifiers[str(id)]
			var stat := str(modifier.stat)
			adds[stat] = float(adds.get(stat, 0.0)) + float(modifier.add)
			multiples[stat] = float(multiples.get(stat, 1.0)) * float(modifier.multiply)
	for stat in adds:
		result[stat] = clampf((float(result.get(stat, 0.0)) + float(adds[stat])) * float(multiples[stat]), 0.0, 100000.0)
	return result

func maximum(stack: Dictionary) -> int:
	return maxi(int(stats(stack).get("max_durability", 0)), 0)

func condition(stack: Dictionary) -> int:
	var amount: Variant = stack.get("metadata", {}).get("condition", maximum(stack))
	if not (amount is int or amount is float) or not is_finite(float(amount)):
		return 0
	return clampi(int(amount), 0, maximum(stack))

func usable(stack: Dictionary) -> bool:
	return not durable(str(stack.get("id", ""))) or condition(stack) > 0

func prepare(stack: Dictionary) -> Dictionary:
	var result := stack.duplicate(true)
	if not durable(str(result.get("id", ""))):
		return result
	result["count"] = 1
	if str(result.get("instance_id", "")).is_empty():
		result["instance_id"] = Crypto.new().generate_random_bytes(16).hex_encode()
	var metadata: Dictionary = result.get("metadata", {}).duplicate(true)
	metadata["condition"] = condition(result)
	result["metadata"] = metadata
	return result

func spend(inventory: Inventory, index: int, amount: int = 1) -> bool:
	inventory._ensure_storage()
	return spend_container(inventory.container, index, amount)

func spend_container(storage: SlotContainer, index: int, amount: int = 1) -> bool:
	var stack := storage.stack_at(index)
	if amount <= 0 or not durable(str(stack.get("id", ""))) or not usable(stack):
		return false
	var replacement := prepare(stack)
	replacement.metadata.condition = maxi(condition(stack) - amount, 0)
	return storage.replace_instance(index, replacement, str(stack.get("instance_id", "")))

func repair_quote(stack: Dictionary) -> Dictionary:
	var props := stats(stack)
	var material := str(props.get("repair_material", ""))
	var missing := maximum(stack) - condition(stack)
	if missing <= 0 or material.is_empty():
		return {"allowed": false, "reason": "Select a damaged repairable tool"}
	var per_unit := maxi(ceili(maximum(stack) * 0.25), 1)
	return {"allowed": true, "material": material, "count": ceili(float(missing) / per_unit), "restore": missing}

func repair(inventory: Inventory, index: int) -> Dictionary:
	var stack := inventory.get_slot(index)
	var quote := repair_quote(stack)
	if not bool(quote.allowed):
		return {"success": false, "reason": quote.reason}
	var replacement := prepare(stack)
	replacement.metadata.condition = maximum(stack)
	if not inventory.container.repair_instance(index, str(stack.get("instance_id", "")), {str(quote.material): int(quote.count)}, replacement):
		return {"success": false, "reason": "Repair needs %s x%d" % [content.get_item_display_name(str(quote.material)), int(quote.count)]}
	return {"success": true, "instance_id": replacement.instance_id, "condition": maximum(replacement)}
