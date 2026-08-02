class_name Inventory
extends Node

const SLOT_COUNT := 4

var selected_slot := 0

var slots = []

func _ready():
	for i in SLOT_COUNT:
		slots.append({
			"id": 0,
			"count": 0
		})

func add_block(block_id: int) -> bool:
	if block_id == 0:
		return false

	# Increase existing stack
	for slot in slots:
		if slot.id == block_id:
			slot.count += 1
			return true

	# Put into first empty slot
	for slot in slots:
		if slot.id == 0:
			slot.id = block_id
			slot.count = 1
			return true

	return false

func remove_selected_block() -> bool:
	var slot = slots[selected_slot]

	if slot.id == 0:
		return false

	slot.count -= 1

	if slot.count <= 0:
		slot.id = 0
		slot.count = 0
		_compact()

	return true

func get_selected_block() -> int:
	return slots[selected_slot].id

func _compact():
	var new_slots = []

	for slot in slots:
		if slot.id != 0:
			new_slots.append(slot)

	while new_slots.size() < SLOT_COUNT:
		new_slots.append({
			"id": 0,
			"count": 0
		})

	slots = new_slots
