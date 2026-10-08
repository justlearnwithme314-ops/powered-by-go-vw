extends Node


func _ready() -> void:
	var profile := WorldProfileService.new()
	var commands := InventoryCommandService.new(GameAPI.stations, GameAPI.crafting)
	commands.item_instances = GameAPI.item_instances
	commands.profile = profile
	var player := CharacterBody3D.new()
	var inventory := Inventory.new()
	inventory.name = "Inventory"
	player.add_child(inventory)
	add_child(player)

	profile.activate({"game_mode": "survival"})
	var rejected := commands.request(player, "creative_grant", {"item_id": "core:dirt", "count": 999})
	assert(not rejected.success and inventory.get_item_count("core:dirt") == 0)

	profile.activate({"game_mode": "creative"})
	var dirt := commands.request(player, "creative_grant", {"item_id": "core:dirt", "count": 1})
	assert(dirt.success and dirt.count == int(GameAPI.content.get_item("core:dirt").stack_size))
	assert(inventory.get_item_count("core:dirt") == int(GameAPI.content.get_item("core:dirt").stack_size))

	var durable_id := ""
	for item_id in GameAPI.content.get_item_ids():
		if GameAPI.item_instances.durable(item_id):
			durable_id = item_id
			break
	assert(not durable_id.is_empty(), "Fixture needs at least one durable registered item")
	var durable_grant := commands.request(player, "creative_grant", {"item_id": durable_id})
	assert(durable_grant.success and durable_grant.count == 1)
	var instance_stack := inventory.container.snapshot().filter(func(stack: Dictionary) -> bool: return str(stack.get("id", "")) == durable_id)
	assert(instance_stack.size() == 1 and not str(instance_stack[0].get("instance_id", "")).is_empty())

	inventory.container.restore([])
	assert(inventory.add_stack({"id": "core:dirt", "count": Inventory.CAPACITY * 64}, true).added == Inventory.CAPACITY * 64)
	var full_result := commands.request(player, "creative_grant", {"item_id": "core:stone"})
	assert(not full_result.success and full_result.reason == "Inventory is full")
	assert(inventory.get_item_count("core:stone") == 0)

	GameAPI.profile.activate({"game_mode": "creative"})
	player.add_to_group("player_character")
	player.set_process_unhandled_input(true)
	var catalog: Node = load("res://mods/creative_catalog/CreativeCatalog.gd").new()
	add_child(catalog)
	catalog.call("setup", GameAPI.base_mod_api)
	catalog.call("_open")
	assert(bool(catalog.get("panel").visible))
	assert(int(catalog.get("item_list").get_child_count()) == GameAPI.content.get_item_ids().size())
	catalog.call("_close")
	assert(not bool(catalog.get("panel").visible))
	catalog.queue_free()

	player.queue_free()
	print("Creative catalog smoke passed: survival rejection, fixed stack, unique instance, full inventory")
	get_tree().quit()
