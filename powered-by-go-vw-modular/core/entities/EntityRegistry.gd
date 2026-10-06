class_name EntityRegistry
extends RefCounted

## Definitions are data; behavior and visuals are supplied by entity mods.
var definitions: Dictionary = {}
var runtime: Node

func register(definition: Dictionary) -> bool:
	var id := str(definition.get("id", ""))
	if not id.contains(":") or definitions.has(id) or not definition.get("visual") is Script:
		return false
	if not is_finite(float(definition.get("health", 0))) or float(definition.get("health", 0)) <= 0:
		return false
	definitions[id] = definition.duplicate(true)
	return true

func definition(id: String) -> Dictionary:
	return definitions.get(id, {}).duplicate(true)

func spawn(id: String, position: Vector3) -> Node3D:
	return runtime.call("spawn", id, position) as Node3D if is_instance_valid(runtime) else null

func spawn_loot(receipt: String, stack: Dictionary, position: Vector3) -> bool:
	return bool(runtime.call("spawn_loot", receipt, stack, position)) if is_instance_valid(runtime) else false
