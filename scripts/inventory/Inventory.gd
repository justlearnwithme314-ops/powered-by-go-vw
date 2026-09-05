class_name Inventory
extends Node


signal changed


# ============================================================
# CONSTANTS
# ============================================================

const HOTBAR_SIZE: int = 4
const EMPTY_ITEM_ID: int = -1


# ============================================================
# FULL INVENTORY
# ============================================================
#
# The inventory stores generic item IDs.
#
# Example:
#
# Wood:
# {
#     "id": Block.LOG,
#     "count": 10
# }
#
# Stick:
# {
#     "id": 1000,
#     "count": 4
# }
#
# The inventory does NOT care whether an ID is a block,
# tool, resource, etc.
# ============================================================

var items: Array[Dictionary] = []


# ============================================================
# HOTBAR
# ============================================================

var hotbar: Array[int] = []

var selected_slot: int = 0


# ============================================================
# INITIALIZATION
# ============================================================

func _init() -> void:
	_initialize_hotbar()


func _ready() -> void:
	changed.emit()


func _initialize_hotbar() -> void:
	hotbar.clear()

	for i in range(HOTBAR_SIZE):
		hotbar.append(EMPTY_ITEM_ID)


func ensure_initialized() -> void:
	if hotbar.size() != HOTBAR_SIZE:
		_initialize_hotbar()


# ============================================================
# ADD ITEM
# ============================================================

func add_item(item_id: int, amount: int = 1) -> bool:
	ensure_initialized()

	if item_id == EMPTY_ITEM_ID:
		return false

	if amount <= 0:
		return false

	# Try to find an existing stack.
	for i in range(items.size()):
		var item: Dictionary = items[i]

		var existing_id: int = int(
			item.get("id", EMPTY_ITEM_ID)
		)

		if existing_id == item_id:
			var current_count: int = int(
				item.get("count", 0)
			)

			items[i]["count"] = current_count + amount

			changed.emit()
			return true

	# No existing stack. Create a new one.
	var new_item: Dictionary = {
		"id": item_id,
		"count": amount
	}

	items.append(new_item)

	changed.emit()

	return true


# ============================================================
# ADD ONE BLOCK
# ============================================================
#
# Kept for compatibility with your existing game code.
#
# Blocks are simply stored as item IDs.
# ============================================================

func add_block(block_id: int) -> bool:
	return add_item(block_id, 1)


# ============================================================
# GET ITEM COUNT
# ============================================================

func get_item_count(item_id: int) -> int:
	for i in range(items.size()):
		var item: Dictionary = items[i]

		var existing_id: int = int(
			item.get("id", EMPTY_ITEM_ID)
		)

		if existing_id == item_id:
			return int(
				item.get("count", 0)
			)

	return 0


# ============================================================
# REMOVE ITEM
# ============================================================

func remove_item(item_id: int, amount: int = 1) -> bool:
	ensure_initialized()

	if item_id == EMPTY_ITEM_ID:
		return false

	if amount <= 0:
		return false

	# Do we have enough?
	if get_item_count(item_id) < amount:
		return false

	# Find the stack.
	for i in range(items.size()):
		var item: Dictionary = items[i]

		var existing_id: int = int(
			item.get("id", EMPTY_ITEM_ID)
		)

		if existing_id == item_id:
			var current_count: int = int(
				item.get("count", 0)
			)

			var new_count: int = current_count - amount

			if new_count <= 0:
				_remove_item_stack(item_id)
			else:
				items[i]["count"] = new_count

			changed.emit()

			return true

	return false


# ============================================================
# REMOVE COMPLETE ITEM STACK
# ============================================================

func _remove_item_stack(item_id: int) -> void:
	for i in range(items.size()):
		var item: Dictionary = items[i]

		var existing_id: int = int(
			item.get("id", EMPTY_ITEM_ID)
		)

		if existing_id == item_id:
			items.remove_at(i)
			break

	# Remove the item from the hotbar as well.
	for i in range(hotbar.size()):
		if hotbar[i] == item_id:
			hotbar[i] = EMPTY_ITEM_ID


# ============================================================
# ASSIGN ITEM TO HOTBAR
# ============================================================

func assign_to_hotbar(
	item_id: int,
	hotbar_index: int
) -> bool:
	ensure_initialized()

	if item_id == EMPTY_ITEM_ID:
		return false

	if hotbar_index < 0 or hotbar_index >= HOTBAR_SIZE:
		return false

	# The item must exist in the inventory.
	if get_item_count(item_id) <= 0:
		return false

	hotbar[hotbar_index] = item_id

	changed.emit()

	return true


# ============================================================
# GET SELECTED ITEM ID
# ============================================================

func get_selected_item_id() -> int:
	ensure_initialized()

	if selected_slot < 0 or selected_slot >= HOTBAR_SIZE:
		return EMPTY_ITEM_ID

	return hotbar[selected_slot]


# ============================================================
# OLD COMPATIBILITY FUNCTION
# ============================================================
#
# Your PlayerController may already use:
#
# inventory.get_selected_block()
#
# We keep it so your existing code doesn't immediately break.
#
# It now returns ANY item ID.
# ============================================================

func get_selected_block() -> int:
	return get_selected_item_id()


# ============================================================
# SELECT HOTBAR SLOT
# ============================================================

func set_selected_slot(index: int) -> void:
	selected_slot = wrapi(
		index,
		0,
		HOTBAR_SIZE
	)

	changed.emit()


# ============================================================
# REMOVE ONE FROM SELECTED HOTBAR SLOT
# ============================================================

func remove_selected_item() -> bool:
	ensure_initialized()

	if selected_slot < 0 or selected_slot >= HOTBAR_SIZE:
		return false

	var item_id: int = hotbar[selected_slot]

	if item_id == EMPTY_ITEM_ID:
		return false

	return remove_item(item_id, 1)


# ============================================================
# OLD COMPATIBILITY FUNCTION
# ============================================================

func remove_selected_block() -> bool:
	return remove_selected_item()
