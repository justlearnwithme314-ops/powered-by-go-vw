class_name MachineRegistry
extends RefCounted

var content: ContentRegistry
var stations: BlockEntityService
var _definitions: Dictionary = {}


func _init(p_content: ContentRegistry, p_stations: BlockEntityService) -> void:
	content = p_content
	stations = p_stations


func register(definition: Dictionary) -> bool:
	var block_id := str(definition.get("block_id", ""))
	if block_id.is_empty() or not content.has_block(block_id) or _definitions.has(block_id) or stations.kinds.has(block_id):
		return false
	var capabilities: Variant = definition.get("capabilities", [])
	var slots: Variant = definition.get("slots", {})
	var method := str(definition.get("method", ""))
	var scale: Variant = definition.get("duration_scale", 1.0)
	var energy: Variant = definition.get("energy_per_second", 0.0)
	var feature := str(definition.get("feature", "industry:machines"))
	if not capabilities is Array or not slots is Dictionary or not _finite_number(scale) or float(scale) <= 0.0 or not _finite_number(energy) or float(energy) < 0.0 or feature.is_empty():
		return false
	if method.is_empty() and float(energy) <= 0.0:
		return false
	var normalized_slots: Dictionary = {}
	for name in slots:
		var count: Variant = slots[name]
		if str(name).is_empty() or not (count is int or count is float) or not _finite_number(count) or int(count) < 1 or int(count) > 64:
			return false
		normalized_slots[str(name)] = int(count)
	if not normalized_slots.has("input") or not normalized_slots.has("output"):
		return false
	var normalized := definition.duplicate(true)
	normalized["block_id"] = block_id
	normalized["capabilities"] = capabilities.duplicate()
	normalized["slots"] = normalized_slots
	normalized["method"] = method
	normalized["duration_scale"] = float(scale)
	normalized["energy_per_second"] = float(energy)
	normalized["feature"] = feature
	_definitions[block_id] = normalized
	stations.register_kind(block_id, normalized.capabilities, normalized.slots)
	return true


func definition(block_id: String) -> Dictionary:
	return _definitions.get(block_id, {}).duplicate(true)


func ids() -> Array[String]:
	var result: Array[String] = []
	for block_id in _definitions:
		result.append(str(block_id))
	result.sort()
	return result


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
