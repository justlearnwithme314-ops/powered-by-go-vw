extends Node3D

class FakeWorld extends VoxelWorldService:
	func get_block_id(pos: Vector3i) -> String:
		return "survival:workbench" if pos == Vector3i.UP else "core:stone"
	func raycast(_origin: Vector3, _direction: Vector3, _distance: float = 10.0):
		return {"position": Vector3i.ZERO, "previous_position": Vector3i.UP}

func _ready() -> void:
	var original_world := GameAPI.world
	var world := FakeWorld.new(GameAPI.content)
	GameAPI.world = world
	var player := CharacterBody3D.new()
	var inventory := Inventory.new()
	inventory.name = "Inventory"
	player.add_child(inventory)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	player.add_child(camera)
	var interactor := VoxelInteractor.new()
	interactor.name = "VoxelInteractor"
	player.add_child(interactor)
	add_child(player)
	interactor.set_physics_process(false)
	var instances := GameAPI.item_instances
	assert(inventory.add_item("frontier:wood_pickaxe", 2))
	var first := inventory.get_slot(0)
	var second := inventory.get_slot(1)
	assert(not str(first.instance_id).is_empty() and first.instance_id != second.instance_id)
	assert(instances.condition(first) == 64 and first.count == 1)
	assert(not inventory.add_item("frontier:wood_pickaxe", 100))
	assert(inventory.get_item_count("frontier:wood_pickaxe") == 2)
	assert(not inventory.move_stack(0, 1, 0).success)
	assert(inventory.move_stack(0, 2).success)
	assert(inventory.get_slot(2).instance_id == first.instance_id)
	inventory.set_selected_slot(2)
	var component: Node = load("res://mods/equipment_condition/ToolCondition.gd").new()
	player.add_child(component)
	component.setup(GameAPI.base_mod_api)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	interactor._handle_primary_action()
	assert(instances.condition(inventory.get_slot(2)) == 63)
	GameAPI.events.subscribe(GameEvents.BLOCK_HIT, _cancel)
	interactor.hit_cooldown = 0.0
	interactor._handle_primary_action()
	assert(instances.condition(inventory.get_slot(2)) == 63)
	GameAPI.events.unsubscribe(GameEvents.BLOCK_HIT, _cancel)
	# Bounded modifier stats preserve unknown metadata but ignore unknown modifiers.
	var modified := inventory.get_slot(2)
	modified.metadata["modifiers"] = ["survival:efficient", "survival:swift", "unavailable:future"]
	modified.metadata["custom_name"] = "Old faithful"
	assert(inventory.container.replace_instance(2, modified, str(modified.instance_id)))
	var effective := instances.stats(inventory.get_slot(2))
	var base: Dictionary = GameAPI.content.get_item("frontier:wood_pickaxe").properties
	assert(float(effective.break_power) > float(base.break_power))
	assert(float(effective.mining_interval) < float(base.mining_interval))
	# Zero condition retains the same object and stops mining.
	assert(instances.spend(inventory, 2, 100))
	var broken := inventory.get_slot(2)
	assert(broken.instance_id == first.instance_id and instances.condition(broken) == 0 and not instances.usable(broken))
	interactor.hit_cooldown = 0.0
	interactor._handle_primary_action()
	assert(not interactor.breaking_active and interactor.breaking_hits == 0)
	assert(interactor.mining_label.text.contains("Broken"))
	var entities := BlockEntityService.new(GameAPI.content, world)
	entities.register_kind("survival:workbench", ["workbench"], {})
	var commands := InventoryCommandService.new(entities, GameAPI.crafting)
	commands.item_instances = instances
	assert(not commands.request(player, "repair", {"index": 2}).success)
	entities.ensure(Vector3i.UP)
	assert(inventory.add_item("core:log", 3))
	var before := inventory.get_snapshot()
	assert(not commands.request(player, "repair", {"index": 2}).success)
	assert(inventory.get_snapshot() == before)
	assert(inventory.add_item("core:log", 1))
	assert(commands.request(player, "repair", {"index": 2}).success)
	var repaired := inventory.get_slot(2)
	assert(repaired.instance_id == first.instance_id and instances.condition(repaired) == 64)
	assert(repaired.metadata.modifiers == modified.metadata.modifiers and repaired.metadata.custom_name == "Old faithful")
	assert(inventory.get_item_count("core:log") == 0)
	# Reload and legacy migration retain counts and condition, with distinct IDs.
	var snapshot := inventory.get_snapshot()
	inventory.load_snapshot(JSON.parse_string(JSON.stringify(snapshot)))
	assert(inventory.get_snapshot() == snapshot)
	var legacy := Inventory.new()
	legacy.load_snapshot({"items": [{"id": "frontier:wood_pickaxe", "count": 2}]})
	assert(legacy.get_item_count("frontier:wood_pickaxe") == 2 and legacy.recovery.is_empty())
	assert(not str(legacy.get_slot(0).instance_id).is_empty())
	assert(legacy.recover_available() == 0)
	assert(legacy.get_slot(0).instance_id != legacy.get_slot(1).instance_id)
	legacy.free()
	instances.spend(inventory, 2, 20)
	var ui: CanvasLayer = load("res://scenes/inventoryui/inventory.tscn").instantiate()
	add_child(ui)
	ui._bind_player(player)
	ui.set_open(true)
	assert(ui.grid_slots[2].condition_bar.visible and ui.grid_slots[2].condition_bar.value == 44)
	assert(ui.repair_button.visible and ui.repair_button.text.contains("Wood"))
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://tests/equipment-condition-preview.png")
	ui.set_open(false)
	ui.queue_free()
	player.queue_free()
	GameAPI.world = original_world
	print("Equipment condition PASS: distinct IDs, atomic batch grants, accepted/cancelled wear, broken tools, modifiers, station/material repair, migration/reload and UI")
	get_tree().quit()

func _cancel(event: Dictionary) -> Dictionary:
	event.cancelled = true
	return event
