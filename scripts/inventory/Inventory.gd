class_name Inventory
extends Node

signal changed

const SLOT_COUNT := 4

var selected_slot: int = 0
var slots: Array[Dictionary] = []


func _init() -> void:
	_initialize_slots()


func _ready() -> void:
	changed.emit()


func _initialize_slots() -> void:
	slots.clear()

	for i in range(SLOT_COUNT):
		slots.append({
			"id": Block.AIR,
			"count": 0
		})


func ensure_initialized() -> void:
	if slots.size() != SLOT_COUNT:
		_initialize_slots()


func add_block(block_id: int) -> bool:
	ensure_initialized()

	if block_id == Block.AIR:
		return false

	# Increase existing stack
	for slot in slots:
		if slot.id == block_id:
			slot.count += 1
			changed.emit()
			return true

	# Put into first empty slot
	for slot in slots:
		if slot.id == Block.AIR:
			slot.id = block_id
			slot.count = 1
			changed.emit()
			return true

	return false


func remove_selected_block() -> bool:
	ensure_initialized()

	if selected_slot < 0 or selected_slot >= SLOT_COUNT:
		return false

	var slot = slots[selected_slot]

	if slot.id == Block.AIR:
		return false

	slot.count -= 1

	if slot.count <= 0:
		slot.id = Block.AIR
		slot.count = 0
		_compact()

	changed.emit()
	return true


func get_selected_block() -> int:
	ensure_initialized()

	if selected_slot < 0 or selected_slot >= SLOT_COUNT:
		return Block.AIR

	return slots[selected_slot].id


func set_selected_slot(index: int) -> void:
	selected_slot = wrapi(index, 0, SLOT_COUNT)
	changed.emit()


func _compact() -> void:
	var new_slots: Array[Dictionary] = []

	for slot in slots:
		if slot.id != Block.AIR:
			new_slots.append(slot)

	while new_slots.size() < SLOT_COUNT:
		new_slots.append({
			"id": Block.AIR,
			"count": 0
		})

	slots = new_slots
