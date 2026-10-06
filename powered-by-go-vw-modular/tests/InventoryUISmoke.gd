extends Node3D

func _ready() -> void:
	var player := CharacterBody3D.new()
	player.name = "UIFixturePlayer"
	player.add_to_group("player_character")
	var inventory := Inventory.new()
	inventory.name = "Inventory"
	player.add_child(inventory)
	add_child(player)
	inventory.add_item("core:dirt", 64)
	inventory.add_item("core:stone", 30)
	var ui: CanvasLayer = load("res://scenes/inventoryui/inventory.tscn").instantiate()
	add_child(ui)
	ui._bind_player(player)
	ui.set_open(true)
	assert(ui.grid_slots.size() == 34 and ui.equipment_slots.size() == 5)
	for key in [KEY_9, KEY_0]:
		ui.hovered_slot = ui.grid_slots[0]
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = true
		ui._input(event)
		var index := 9 if key == KEY_0 else 8
		assert(inventory.get_slot(index).id == "core:dirt")
		ui.hovered_slot = ui.grid_slots[index]
		event.keycode = KEY_1
		ui._input(event)
		assert(inventory.get_slot(0).id == "core:dirt")
	ui.hovered_slot = null
	# Right click halves a stack; right click places exactly one.
	ui.slot_clicked(0, false, true, false, false)
	assert(inventory.get_slot(0).count == 32 and inventory.cursor.stack_at(0).count == 32)
	ui.slot_clicked(10, false, true, false, false)
	assert(inventory.get_slot(10).count == 1 and inventory.cursor.stack_at(0).count == 31)
	ui.slot_clicked(11, false, false, false, false)
	assert(inventory.get_slot(11).count == 31 and inventory.cursor.stack_at(0).is_empty())
	# Native drag data commits to the actual target slot.
	ui.slot_clicked(1, false, false, false, false)
	var data: Variant = ui.grid_slots[1]._get_drag_data(Vector2.ZERO)
	assert(ui.grid_slots[12]._can_drop_data(Vector2.ZERO, data))
	ui.grid_slots[12]._drop_data(Vector2.ZERO, data)
	assert(inventory.get_slot(12).count == 30 and inventory.get_slot(1).is_empty())
	# Double click gathers only compatible stacks, capped at stack size.
	ui.slot_clicked(11, false, false, false, true)
	assert(inventory.cursor.stack_at(0).count == 64)
	assert(inventory.get_item_count("core:dirt") == 0)
	ui.slot_clicked(10, false, false, false, false)
	assert(inventory.get_slot(10).count == 64)
	ui.slot_clicked(12, false, false, true, false)
	assert(inventory.get_slot(12).is_empty())
	assert(inventory.get_slot(0).id == "core:stone")
	# A held stack survives saving and closing, and invalid equipment rejects it.
	ui.slot_clicked(10, false, false, false, false)
	ui.slot_clicked(0, true, false, false, false)
	assert(inventory.equipment.stack_at(0).is_empty())
	assert(inventory.cursor.stack_at(0).count == 64)
	var restored := Inventory.new()
	restored.load_snapshot(inventory.get_snapshot())
	assert(restored.get_item_count("core:dirt") == 64)
	restored.free()
	ui.set_open(false)
	assert(inventory.cursor.stack_at(0).is_empty() and inventory.get_item_count("core:dirt") == 64)
	# Group compatible backpack stacks without disturbing hotbar.
	inventory.container.transfer_to(inventory.container, 10, 11, 20)
	var bar := inventory.get_slot(0)
	inventory.organize_backpack()
	assert(inventory.get_slot(0) == bar)
	assert(inventory.get_slot(10).count == 64 and inventory.get_slot(11).is_empty())
	var drops: Node3D = load("res://core/inventory/InventoryDrops.gd").new()
	drops.name = "InventoryDrops"
	add_child(drops)
	drops.set_process(false)
	drops.save_path = "user://inventory_ui_tests/%s.drops.json" % Time.get_ticks_usec()
	assert(drops.drop_stack(inventory, false, 10, 7).success)
	assert(inventory.get_item_count("core:dirt") == 57 and drops.records.size() == 1)
	var record: Dictionary = drops.records.values()[0]
	assert(record.stack.count == 7)
	# Walk to the world pickup, after its delay.
	player.position = Vector3(record.position[0], record.position[1] - 0.6, record.position[2])
	drops._process(2.0)
	assert(drops.records.is_empty() and inventory.get_item_count("core:dirt") == 64)
	assert(JSON.parse_string(FileAccess.get_file_as_string(drops.save_path)).drops.is_empty())
	# Failed native drag restores the cursor instead of deleting it.
	ui.set_open(true)
	ui.slot_clicked(10, false, false, false, false)
	ui.grid_slots[10]._get_drag_data(Vector2.ZERO)
	ui.grid_slots[10]._notification(Control.NOTIFICATION_DRAG_END)
	assert(inventory.cursor.stack_at(0).is_empty())
	assert(inventory.get_item_count("core:dirt") == 64)
	# Grid clicks use the same held stack and display only matching outputs.
	inventory.add_item("survival:planks", 4)
	var plank_slot := -1
	for i in range(Inventory.CAPACITY):
		if inventory.get_slot(i).get("id", "") == "survival:planks":
			plank_slot = i
	ui.slot_clicked(plank_slot, false, false, false, false)
	for i in range(4):
		ui.grid_clicked(i, true)
	assert(inventory.cursor.stack_at(0).is_empty())
	assert(ui.arrangement_slots.size() == 4)
	assert(ui.craft_list.item_count > 0)
	var bench_recipe := -1
	for i in range(ui.craft_list.item_count):
		if ui.craft_list.get_item_metadata(i) == "survival:workbench":
			bench_recipe = i
	assert(bench_recipe >= 0)
	print("Inventory UI PASS: split/place, drag, gather, quick transfer, close/save safety, grouping, world drop and pickup")
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://tests/inventory-ui-preview.png")
	ui.set_open(false)
	assert(inventory.get_item_count("survival:planks") == 4)
	ui.queue_free()
	drops.queue_free()
	player.queue_free()
	get_tree().quit()
