class_name SlotContainer
extends RefCounted

## Generic fixed-slot storage. Mutations return exact quantities and never
## expose mutable records. Inventory, chests and station slots share this model.
signal changed

var content: ContentRegistry
var revision := 0
var _slots: Array[Dictionary] = []
var _filters: Dictionary = {}


func _init(registry: ContentRegistry, capacity: int = 32) -> void:
	content = registry
	for _i in range(maxi(capacity, 0)):
		_slots.append({})


func size() -> int:
	return _slots.size()


func stack_at(index: int) -> Dictionary:
	return _slots[index].duplicate(true) if index >= 0 and index < size() else {}


func snapshot() -> Array[Dictionary]:
	return _slots.duplicate(true)


func set_filter(index: int, predicate: Callable) -> void:
	if index >= 0 and index < size():
		_filters[index] = predicate


func accepts(index: int, stack: Dictionary) -> bool:
	if index < 0 or index >= size():
		return false
	return not _filters.has(index) or bool(_filters[index].call(stack))


func valid(stack: Dictionary) -> bool:
	return content.has_item(str(stack.get("id", ""))) and int(stack.get("count", 0)) > 0 and stack.get("metadata", {}) is Dictionary and (str(stack.get("instance_id", "")).is_empty() or int(stack.get("count", 0)) == 1)


func limit(stack: Dictionary) -> int:
	if not str(stack.get("instance_id", "")).is_empty():
		return 1
	return maxi(int(content.get_item(str(stack.get("id", ""))).get("stack_size", 64)), 1)


func compatible(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and not b.is_empty() and str(a.get("id", "")) == str(b.get("id", "")) and a.get("metadata", {}) == b.get("metadata", {}) and str(a.get("instance_id", "")) == str(b.get("instance_id", ""))


func count(item_id: String) -> int:
	var total := 0
	for stack in _slots:
		if str(stack.get("id", "")) == item_id:
			total += int(stack.get("count", 0))
	return total


func _commit() -> void:
	revision += 1
	changed.emit()


func insert(stack: Dictionary, all_or_nothing: bool = false) -> Dictionary:
	if not valid(stack):
		return {"added": 0, "remainder": stack.duplicate(true)}
	var candidate := snapshot()
	var remaining := int(stack.count)
	for merge in [true, false]:
		for i in range(size()):
			if remaining <= 0:
				break
			if not accepts(i, stack):
				continue
			var current: Dictionary = candidate[i]
			if merge and not compatible(current, stack):
				continue
			if not merge and not current.is_empty():
				continue
			var added := mini(remaining, limit(stack) - int(current.get("count", 0)))
			if added <= 0:
				continue
			if current.is_empty():
				current = stack.duplicate(true)
				current["count"] = 0
			current["count"] = int(current.count) + added
			candidate[i] = current
			remaining -= added
	if all_or_nothing and remaining > 0:
		return {"added": 0, "remainder": stack.duplicate(true)}
	var remainder := stack.duplicate(true) if remaining > 0 else {}
	if remaining > 0:
		remainder["count"] = remaining
	var added := int(stack.count) - remaining
	if added > 0:
		_slots = candidate
		_commit()
	return {"added": added, "remainder": remainder}


func take(index: int, amount: int) -> Dictionary:
	if index < 0 or index >= size() or amount <= 0 or _slots[index].is_empty():
		return {}
	var result := stack_at(index)
	result["count"] = mini(amount, int(result.count))
	_slots[index]["count"] = int(_slots[index].count) - int(result.count)
	if int(_slots[index].count) == 0:
		_slots[index] = {}
	_commit()
	return result


func remove(item_id: String, amount: int) -> bool:
	if amount <= 0 or count(item_id) < amount:
		return false
	var remaining := amount
	# Consume backpack before hotbar to keep the held stack stable.
	for i in range(size() - 1, -1, -1):
		if str(_slots[i].get("id", "")) != item_id:
			continue
		var removed := mini(remaining, int(_slots[i].count))
		_slots[i]["count"] = int(_slots[i].count) - removed
		remaining -= removed
		if int(_slots[i].count) == 0:
			_slots[i] = {}
		if remaining == 0:
			break
	_commit()
	return true


func transfer_to(target: SlotContainer, from: int, to: int, amount: int = 2147483647) -> Dictionary:
	if target == null or from < 0 or from >= size() or to < 0 or to >= target.size() or amount <= 0 or (target == self and from == to):
		return {"success": false, "moved": 0}
	var source := stack_at(from)
	var destination := target.stack_at(to)
	if source.is_empty() or not target.accepts(to, source):
		return {"success": false, "moved": 0}
	var quantity := mini(amount, int(source.count))
	if destination.is_empty() or compatible(source, destination):
		quantity = mini(quantity, target.limit(source) - int(destination.get("count", 0)))
		if quantity <= 0:
			return {"success": false, "moved": 0}
		if destination.is_empty():
			destination = source.duplicate(true)
			destination["count"] = 0
		destination["count"] = int(destination.count) + quantity
		source["count"] = int(source.count) - quantity
		_slots[from] = source if int(source.count) > 0 else {}
		target._slots[to] = destination
	else:
		if quantity != int(source.count) or not accepts(from, destination) or int(source.count) > target.limit(source) or int(destination.count) > limit(destination):
			return {"success": false, "moved": 0}
		_slots[from] = destination
		target._slots[to] = source
	# Both writes finish before either observer sees the transaction.
	revision += 1
	if target != self:
		target.revision += 1
	changed.emit()
	if target != self:
		target.changed.emit()
	return {"success": true, "moved": quantity}


func exchange(ingredients: Dictionary, output: Dictionary, commit: bool = true) -> bool:
	var trial := SlotContainer.new(content, size())
	trial._slots = snapshot()
	trial._filters = _filters.duplicate()
	for id in ingredients:
		var amount := int(ingredients[id])
		if amount > 0 and not trial.remove(str(id), amount):
			return false
	if not output.is_empty() and int(trial.insert(output, true).added) != int(output.get("count", 0)):
		return false
	if commit:
		_slots = trial.snapshot()
		_commit()
	return true


func restore(records: Array) -> Array[Dictionary]:
	var recovery: Array[Dictionary] = []
	for i in range(size()):
		_slots[i] = {}
	for i in range(records.size()):
		if not records[i] is Dictionary or records[i].is_empty():
			continue
		var stack: Dictionary = records[i].duplicate(true)
		if not valid(stack) or i >= size() or not accepts(i, stack):
			recovery.append(stack)
			continue
		var amount := int(stack.count)
		stack["count"] = mini(amount, limit(stack))
		_slots[i] = stack
		if amount > int(stack.count):
			var extra := stack.duplicate(true)
			extra["count"] = amount - int(stack.count)
			recovery.append(extra)
	_commit()
	return recovery

func exchange_to(target: SlotContainer, ingredients: Dictionary, output: Dictionary) -> bool:
	if target == null or target == self:
		return false
	var source_trial := SlotContainer.new(content, size())
	source_trial._slots = snapshot()
	var target_trial := SlotContainer.new(content, target.size())
	target_trial._slots = target.snapshot()
	target_trial._filters = target._filters.duplicate()
	for id in ingredients:
		if int(ingredients[id]) <= 0 or not source_trial.remove(str(id), int(ingredients[id])):
			return false
	if int(target_trial.insert(output, true).added) != int(output.get("count", 0)):
		return false
	_slots = source_trial.snapshot()
	target._slots = target_trial.snapshot()
	revision += 1
	target.revision += 1
	changed.emit()
	target.changed.emit()
	return true

func insert_batch(records: Array[Dictionary], all_or_nothing: bool = false) -> int:
	var trial := SlotContainer.new(content, size())
	trial._slots = snapshot()
	trial._filters = _filters.duplicate()
	var added := 0
	for stack in records:
		var result := trial.insert(stack, true)
		if int(result.added) != int(stack.get("count", 0)):
			if all_or_nothing:
				return 0
			break
		added += int(result.added)
	if added > 0:
		_slots = trial.snapshot()
		_commit()
	return added

func replace_instance(index: int, replacement: Dictionary, expected_id: String) -> bool:
	var existing := stack_at(index)
	if existing.is_empty() or not valid(replacement) or int(replacement.get("count", 0)) != 1 or str(existing.get("instance_id", "")) != expected_id or str(replacement.get("id", "")) != str(existing.id) or not accepts(index, replacement):
		return false
	if not expected_id.is_empty() and str(replacement.get("instance_id", "")) != expected_id:
		return false
	_slots[index] = replacement.duplicate(true)
	_commit()
	return true

func repair_instance(index: int, expected_id: String, ingredients: Dictionary, replacement: Dictionary) -> bool:
	var trial := SlotContainer.new(content, size())
	trial._slots = snapshot()
	trial._filters = _filters.duplicate()
	for id in ingredients:
		if not trial.remove(str(id), int(ingredients[id])):
			return false
	if not trial.replace_instance(index, replacement, expected_id):
		return false
	_slots = trial.snapshot()
	_commit()
	return true
