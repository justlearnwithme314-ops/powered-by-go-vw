class_name Inventory
extends Node

## Local, gameplay-oriented inventory.
##
## Items are stored by stable logical IDs. Stacks respect each item's
## registered stack_size, while the inventory itself has no artificial slot
## capacity yet (so gameplay is never blocked by a UI-only limit).

signal changed

const HOTBAR_SIZE := 8
const EMPTY_ITEM_ID := ""

var items: Array[Dictionary] = []
var hotbar: Array[String] = []
var selected_slot: int = 0
var _suppress_changed := false


func _ready() -> void:
	_ensure_hotbar()
	changed.emit()


func _ensure_hotbar() -> void:
	while hotbar.size() < HOTBAR_SIZE:
		hotbar.append(EMPTY_ITEM_ID)

	while hotbar.size() > HOTBAR_SIZE:
		hotbar.pop_back()


func _stack_size(item_id: String) -> int:
	var item := GameAPI.content.get_item(item_id)
	return maxi(int(item.get("stack_size", 64)), 1)


func _emit_changed() -> void:
	if not _suppress_changed:
		changed.emit()


func add_item(item_id: String, amount: int = 1) -> bool:
	if item_id.is_empty() or not GameAPI.content.has_item(item_id):
		return false
	if amount <= 0:
		return false

	var remaining := amount
	var max_stack := _stack_size(item_id)

	# Fill existing partial stacks first.
	for stack in items:
		if remaining <= 0:
			break
		if str(stack.get("id", "")) != item_id:
			continue

		var count := maxi(int(stack.get("count", 0)), 0)
		if count >= max_stack:
			continue

		var add_count := mini(remaining, max_stack - count)
		stack["count"] = count + add_count
		remaining -= add_count

	# Create as many additional stacks as required.
	while remaining > 0:
		var add_count := mini(remaining, max_stack)
		items.append({
			"id": item_id,
			"count": add_count,
		})
		remaining -= add_count

	_ensure_hotbar()
	_emit_changed()
	return true


func remove_item(item_id: String, amount: int = 1) -> bool:
	if item_id.is_empty() or amount <= 0:
		return false
	if get_item_count(item_id) < amount:
		return false

	var remaining := amount
	for i in range(items.size() - 1, -1, -1):
		if remaining <= 0:
			break
		if str(items[i].get("id", "")) != item_id:
			continue

		var count := maxi(int(items[i].get("count", 0)), 0)
		var removed := mini(remaining, count)
		count -= removed
		remaining -= removed

		if count <= 0:
			items.remove_at(i)
		else:
			items[i]["count"] = count

	if get_item_count(item_id) <= 0:
		for slot in range(hotbar.size()):
			if hotbar[slot] == item_id:
				hotbar[slot] = EMPTY_ITEM_ID

	_emit_changed()
	return true


func get_item_count(item_id: String) -> int:
	if item_id.is_empty():
		return 0

	var total := 0
	for item in items:
		if str(item.get("id", "")) == item_id:
			total += maxi(int(item.get("count", 0)), 0)
	return total


func get_selected_item_id() -> String:
	_ensure_hotbar()
	if selected_slot < 0 or selected_slot >= hotbar.size():
		return EMPTY_ITEM_ID
	return hotbar[selected_slot]


func set_selected_slot(index: int) -> void:
	_ensure_hotbar()
	selected_slot = clampi(index, 0, HOTBAR_SIZE - 1)
	_emit_changed()


func assign_to_hotbar(item_id: String, slot: int) -> bool:
	_ensure_hotbar()
	if item_id.is_empty() or not GameAPI.content.has_item(item_id):
		return false
	if get_item_count(item_id) <= 0:
		return false
	if slot < 0 or slot >= hotbar.size():
		return false

	hotbar[slot] = item_id
	_emit_changed()
	return true


func remove_selected_item() -> bool:
	var item_id := get_selected_item_id()
	if item_id.is_empty():
		return false
	return remove_item(item_id, 1)


func get_snapshot() -> Dictionary:
	return {
		"items": items.duplicate(true),
		"hotbar": hotbar.duplicate(),
		"selected_slot": selected_slot,
	}


func load_snapshot(snapshot: Dictionary) -> void:
	_suppress_changed = true
	items.clear()
	hotbar.clear()

	var raw_items: Variant = snapshot.get("items", [])
	if raw_items is Array:
		for raw_item in raw_items:
			if not raw_item is Dictionary:
				continue
			var item := raw_item as Dictionary
			var item_id := str(item.get("id", ""))
			var count := int(item.get("count", 0))
			if item_id.is_empty() or count <= 0:
				continue
			if not GameAPI.content.has_item(item_id):
				continue
			add_item(item_id, count)

	var raw_hotbar: Variant = snapshot.get("hotbar", [])
	if raw_hotbar is Array:
		for raw_item_id in raw_hotbar:
			var item_id := str(raw_item_id)
			hotbar.append(item_id if get_item_count(item_id) > 0 and GameAPI.content.has_item(item_id) else EMPTY_ITEM_ID)

	_ensure_hotbar()
	selected_slot = clampi(int(snapshot.get("selected_slot", 0)), 0, HOTBAR_SIZE - 1)
	_suppress_changed = false
	changed.emit()
