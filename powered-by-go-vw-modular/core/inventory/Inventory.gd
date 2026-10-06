class_name Inventory
extends Node

## Player facade over reusable slot storage. Legacy getters are read-only views.
signal changed
const HOTBAR_SIZE := 10
const CAPACITY := 34
const EMPTY_ITEM_ID := ""
const EQUIPMENT_SLOTS := ["head", "body", "legs", "feet", "offhand"]

var selected_slot := 0
var container: SlotContainer
var equipment: SlotContainer
var cursor: SlotContainer
var crafting_grid: SlotContainer
var crafting_width := 2
var crafting_height := 2
var cursor_origin := -1
var cursor_equipment := false
var recovery: Array[Dictionary] = []
var reward_receipts: Dictionary = {}
var network_adapter: Node

func is_remote_inventory() -> bool:
	return is_instance_valid(network_adapter) and not bool(network_adapter.call("authority"))

func network_request(action: String, arguments: Dictionary = {}) -> Dictionary:
	return network_adapter.call("inventory_request", get_parent(), action, arguments)
var _suppress_changed := false
var migrated_legacy := false

var items: Array[Dictionary]:
	get:
		_ensure_storage()
		var result: Array[Dictionary] = []
		for stack in container.snapshot():
			if not stack.is_empty():
				result.append(stack)
		return result
	set(value):
		load_snapshot({"items": value})

var hotbar: Array[String]:
	get:
		_ensure_storage()
		var result: Array[String] = []
		for i in range(HOTBAR_SIZE):
			result.append(str(container.stack_at(i).get("id", "")))
		return result

func _ready() -> void:
	_ensure_storage()
	_emit_changed()

func _ensure_storage() -> void:
	if container != null:
		return
	container = SlotContainer.new(GameAPI.content, CAPACITY)
	equipment = SlotContainer.new(GameAPI.content, EQUIPMENT_SLOTS.size())
	cursor = SlotContainer.new(GameAPI.content, 1)
	crafting_grid = SlotContainer.new(GameAPI.content, 4)
	container.changed.connect(_emit_changed)
	equipment.changed.connect(_emit_changed)
	cursor.changed.connect(_emit_changed)
	crafting_grid.changed.connect(_emit_changed)
	for i in range(EQUIPMENT_SLOTS.size()):
		equipment.set_filter(i, _accept_equipment.bind(str(EQUIPMENT_SLOTS[i])))

func _accept_equipment(stack: Dictionary, slot_name: String) -> bool:
	var definition := GameAPI.content.get_item(str(stack.get("id", "")))
	var props: Dictionary = definition.get("properties", {})
	return slot_name in props.get("equipment_slots", []) and int(stack.get("count", 0)) == 1

func _emit_changed() -> void:
	if not _suppress_changed:
		changed.emit()

func add_stack(stack: Dictionary, all_or_nothing: bool = false) -> Dictionary:
	if is_remote_inventory():
		return {"added": 0, "remainder": stack.duplicate(true)}
	_ensure_storage()
	if not stack.get("metadata", {}) is Dictionary:
		return {"added": 0, "remainder": stack.duplicate(true)}
	if GameAPI.item_instances != null and GameAPI.item_instances.durable(str(stack.get("id", ""))):
		var count := int(stack.get("count", 0))
		if count <= 0 or count > 4096 or (count > 1 and not str(stack.get("instance_id", "")).is_empty()):
			return {"added": 0, "remainder": stack.duplicate(true)}
		var records: Array[Dictionary] = []
		for i in range(count):
			records.append(GameAPI.item_instances.prepare(stack))
		var added := container.insert_batch(records, all_or_nothing)
		var remainder := stack.duplicate(true)
		remainder["count"] = count - added
		return {"added": added, "remainder": remainder if added < count else {}}
	return container.insert(stack, all_or_nothing)

func add_item(item_id: String, amount: int = 1) -> bool:
	return int(add_stack({"id": item_id, "count": amount}, true).added) == amount and amount > 0

func grant_item(item_id: String, amount: int = 1) -> void:
	if is_remote_inventory():
		return
	# Transitional reward path until world drops replace direct mining grants.
	# A full backpack must never discard a successful mining reward.
	if amount <= 0:
		return
	_suppress_changed = true
	var result := add_stack({"id": item_id, "count": amount})
	if not result.remainder.is_empty():
		recovery.append(result.remainder)
	_suppress_changed = false
	_emit_changed()

func recover_available() -> int:
	if is_remote_inventory():
		network_request("recover")
		return 0
	var added := 0
	for i in range(recovery.size() - 1, -1, -1):
		added += int(recover_stack(i).get("added", 0))
	return added

func remove_item(item_id: String, amount: int = 1) -> bool:
	if is_remote_inventory():
		return false # Only validated gameplay commands consume remote items.
	_ensure_storage()
	return container.remove(item_id, amount)

func get_item_count(item_id: String) -> int:
	_ensure_storage()
	return container.count(item_id)

func get_slot(index: int) -> Dictionary:
	_ensure_storage()
	return container.stack_at(index)

func get_selected_item_id() -> String:
	return str(get_slot(selected_slot).get("id", ""))

func set_selected_slot(index: int) -> void:
	if is_remote_inventory():
		network_request("select", {"index": index})
		return
	selected_slot = clampi(index, 0, HOTBAR_SIZE - 1)
	_emit_changed()

func assign_to_hotbar(item_id: String, slot: int) -> bool:
	_ensure_storage()
	if slot < 0 or slot >= HOTBAR_SIZE or item_id.is_empty():
		return false
	if str(get_slot(slot).get("id", "")) == item_id:
		return true
	for i in range(CAPACITY):
		if str(get_slot(i).get("id", "")) == item_id:
			return bool(container.transfer_to(container, i, slot).success)
	return false

func remove_selected_item() -> bool:
	_ensure_storage()
	return not container.take(selected_slot, 1).is_empty()

func move_stack(from: int, to: int, amount: int = 2147483647) -> Dictionary:
	if is_remote_inventory():
		return network_request("move", {"from": from, "to": to, "amount": amount})
	_ensure_storage()
	return container.transfer_to(container, from, to, amount)

func equip(from: int, equipment_slot: int) -> Dictionary:
	if is_remote_inventory():
		return network_request("equip", {"from": from, "to": equipment_slot})
	_ensure_storage()
	return container.transfer_to(equipment, from, equipment_slot, 1)

func unequip(equipment_slot: int, to: int) -> Dictionary:
	if is_remote_inventory():
		return network_request("unequip", {"from": equipment_slot, "to": to})
	_ensure_storage()
	return equipment.transfer_to(container, equipment_slot, to)

func can_exchange(ingredients: Dictionary, output: Dictionary) -> bool:
	_ensure_storage()
	return container.exchange(ingredients, output, false)

func craft_transaction(ingredients: Dictionary, output: Dictionary) -> bool:
	_ensure_storage()
	if GameAPI.item_instances != null and GameAPI.item_instances.durable(str(output.get("id", ""))):
		if int(output.get("count", 0)) != 1:
			return false
		output = GameAPI.item_instances.prepare(output)
	return container.exchange(ingredients, output)

func click_slot(index: int, right: bool = false, equipped: bool = false) -> void:
	if is_remote_inventory():
		network_request("click", {"index": index, "right": right, "equipped": equipped})
		return
	_ensure_storage()
	var source := equipment if equipped else container
	var held := cursor.stack_at(0)
	if held.is_empty():
		var stack := source.stack_at(index)
		if stack.is_empty():
			return
		var amount := ceili(float(stack.count) / 2.0) if right else int(stack.count)
		if bool(source.transfer_to(cursor, index, 0, amount).success):
			cursor_origin = index
			cursor_equipment = equipped
	else:
		cursor.transfer_to(source, 0, index, 1 if right else int(held.count))

func return_cursor() -> void:
	if is_remote_inventory():
		network_request("return_cursor")
		return
	_ensure_storage()
	_suppress_changed = true
	var original := equipment if cursor_equipment else container
	if cursor_origin >= 0:
		# Returning must not swap an unrelated stack out of its slot.
		var destination := original.stack_at(cursor_origin)
		if destination.is_empty() or cursor.compatible(destination, cursor.stack_at(0)):
			cursor.transfer_to(original, 0, cursor_origin)
	var held := cursor.stack_at(0)
	if not held.is_empty():
		var result := container.insert(held)
		cursor.take(0, int(result.added))
		held = cursor.take(0, 2147483647)
		if not held.is_empty():
			recovery.append(held)
	cursor_origin = -1
	_suppress_changed = false
	_emit_changed()

func collect_matching() -> void:
	if is_remote_inventory():
		network_request("collect")
		return
	_ensure_storage()
	var held := cursor.stack_at(0)
	if held.is_empty():
		return
	for i in range(CAPACITY):
		if cursor.compatible(held, container.stack_at(i)):
			container.transfer_to(cursor, i, 0)

func quick_transfer(index: int) -> void:
	if is_remote_inventory():
		network_request("quick_transfer", {"index": index})
		return
	_ensure_storage()
	var start := HOTBAR_SIZE if index < HOTBAR_SIZE else 0
	var end := CAPACITY if index < HOTBAR_SIZE else HOTBAR_SIZE
	for merging in [true, false]:
		for target in range(start, end):
			var stack := get_slot(index)
			if stack.is_empty():
				return
			var destination := get_slot(target)
			if (merging and container.compatible(stack, destination)) or (not merging and destination.is_empty()):
				container.transfer_to(container, index, target)

func organize_backpack() -> void:
	if is_remote_inventory():
		network_request("organize")
		return
	_ensure_storage()
	var trial := SlotContainer.new(GameAPI.content, CAPACITY - HOTBAR_SIZE)
	var stacks: Array[Dictionary] = []
	for i in range(HOTBAR_SIZE, CAPACITY):
		if not get_slot(i).is_empty():
			stacks.append(get_slot(i))
	stacks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	for stack in stacks:
		trial.insert(stack)
	var records := container.snapshot()
	for i in range(HOTBAR_SIZE, CAPACITY):
		records[i] = trial.stack_at(i - HOTBAR_SIZE)
	container.restore(records)

func recover_stack(index: int) -> Dictionary:
	_ensure_storage()
	if index < 0 or index >= recovery.size():
		return {"added": 0}
	_suppress_changed = true
	var result := container.insert(recovery[index])
	if result.remainder.is_empty():
		recovery.remove_at(index)
	else:
		recovery[index] = result.remainder
	_suppress_changed = false
	_emit_changed()
	return result

func get_snapshot() -> Dictionary:
	_ensure_storage()
	return {"version": 2, "hotbar_size": HOTBAR_SIZE, "slots": container.snapshot(), "equipment": equipment.snapshot(), "cursor": cursor.snapshot(), "crafting_grid": crafting_grid.snapshot(), "crafting_width":crafting_width,"crafting_height":crafting_height,
		"recovery": recovery.duplicate(true), "selected_slot": selected_slot, "reward_receipts": reward_receipts.duplicate(), "cursor_origin": cursor_origin, "cursor_equipment": cursor_equipment}

func load_snapshot(snapshot: Dictionary, preserve_cursor: bool = false) -> void:
	_ensure_storage()
	reward_receipts = snapshot.get("reward_receipts", {}).duplicate() if snapshot.get("reward_receipts", {}) is Dictionary else {}
	_suppress_changed = true
	recovery.clear()
	container.restore([])
	equipment.restore([])
	cursor.restore([])
	migrated_legacy = int(snapshot.get("version", 1)) < 2
	if not migrated_legacy:
		var records: Variant = snapshot.get("slots", [])
		if records is Array:
			# Version-2 saves without this field used an eight-slot hotbar.
			# Insert the new slots before the backpack, preserving all old stacks.
			var old_size := int(snapshot.get("hotbar_size", 8))
			if old_size == 8:
				records = records.duplicate(true)
				while records.size() < 8:
					records.append({})
				records.insert(8, {})
				records.insert(9, {})
			recovery.append_array(container.restore(records))
		records = snapshot.get("equipment", [])
		if records is Array:
			recovery.append_array(equipment.restore(records))
	else:
		var records: Variant = snapshot.get("items", [])
		if records is Array:
			for record in records:
				if not record is Dictionary or int(record.get("count", 0)) <= 0:
					continue
				var result := container.insert(record)
				if not result.remainder.is_empty():
					recovery.append(result.remainder)
		var old_hotbar: Variant = snapshot.get("hotbar", [])
		if old_hotbar is Array:
			# Move real stacks rather than copying old item-ID aliases.
			for i in range(mini(old_hotbar.size(), HOTBAR_SIZE)):
				assign_to_hotbar(str(old_hotbar[i]), i)
	var saved_recovery: Variant = snapshot.get("recovery", [])
	if saved_recovery is Array:
		for record in saved_recovery:
			if record is Dictionary:
				recovery.append(record.duplicate(true))
	var saved_cursor: Variant = snapshot.get("cursor", [])
	var saved_grid: Variant = snapshot.get("crafting_grid", [])
	crafting_width = 2
	crafting_height = 2
	if saved_grid is Array and preserve_cursor:
		var width := int(snapshot.get("crafting_width",2))
		var height := int(snapshot.get("crafting_height",2))
		if width >= 2 and height >= 2 and width * height == saved_grid.size():
			crafting_width = width
			crafting_height = height
	crafting_grid = SlotContainer.new(GameAPI.content, crafting_width * crafting_height)
	crafting_grid.changed.connect(_emit_changed)
	if saved_grid is Array:
		if preserve_cursor:
			recovery.append_array(crafting_grid.restore(saved_grid))
		else:
			for stack in saved_grid:
				if stack is Dictionary and not stack.is_empty():
					var inserted := container.insert(stack)
					if not inserted.remainder.is_empty():
						recovery.append(inserted.remainder)
	if saved_cursor is Array:
		recovery.append_array(cursor.restore(saved_cursor))
	if preserve_cursor:
		cursor_origin = int(snapshot.get("cursor_origin", -1))
		cursor_equipment = bool(snapshot.get("cursor_equipment", false))
	else:
		var held := cursor.take(0, 2147483647)
		if not held.is_empty():
			var inserted := container.insert(held)
			if not inserted.remainder.is_empty():
				recovery.append(inserted.remainder)
	selected_slot = clampi(int(snapshot.get("selected_slot", 0)), 0, HOTBAR_SIZE - 1)
	_upgrade_instances()
	_suppress_changed = false
	_emit_changed()

func _upgrade_instances() -> void:
	if GameAPI.item_instances == null:
		return
	var seen := {}
	for storage in [container, equipment, cursor, crafting_grid]:
		var records: Array[Dictionary] = storage.snapshot()
		var changed_records := false
		for index in range(records.size()):
			var stack := records[index]
			if stack.is_empty() or not GameAPI.item_instances.durable(str(stack.get("id", ""))):
				continue
			var id := str(stack.get("instance_id", ""))
			if seen.has(id):
				stack.erase("instance_id")
			var replacement := GameAPI.item_instances.prepare(stack)
			seen[str(replacement.instance_id)] = true
			if records[index] != replacement:
				changed_records = true
			records[index] = replacement
		if changed_records:
			recovery.append_array(storage.restore(records))
