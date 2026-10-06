extends Node

func _ready() -> void:
	var old_root := GameAPI.saves.root_path
	var old_legacy := GameAPI.saves.legacy_state_path
	GameAPI.saves.root_path = "user://progression_world_tests/%d" % Time.get_ticks_usec()
	GameAPI.saves.legacy_state_path = GameAPI.saves.root_path.path_join("legacy.json")
	var created := GameAPI.saves.create_world("Progression fixture", "53", {"api_version": 1, "mods": GameAPI.mods.get_signature(), "content": GameAPI.content.get_content_signature()})
	assert(created.success)
	assert(GameAPI.saves.select_world(str(created.save_name)).valid)
	var game: Node3D = load("res://scenes/main/Game.tscn").instantiate()
	add_child(game)
	for frame in range(12):
		await get_tree().process_frame
	var player := game.get_node("Players/1") as PlayerController
	player.set_physics_process(false)
	var inventory := player.get_node("Inventory") as Inventory
	var survival := player.get_node("DamageReceiver") as DamageReceiver
	survival.set_physics_process(false)
	player.get_node("FrontierVitals").set_physics_process(false)
	assert(inventory.items.is_empty() and GameAPI.stations.inventory == inventory)
	assert(GameAPI.stations.path.begins_with(GameAPI.saves.root_path))
	assert(player.has_node("ToolCondition"))
	for id in ["survival:workbench", "survival:furnace", "survival:planks"]:
		assert(GameAPI.world.get_block_display_mesh(id) != null)
	assert(inventory.add_item("core:log", 8))
	assert(GameAPI.inventory_commands.request(player, "craft", {"recipe_id": "survival:planks"}).success)
	assert(GameAPI.inventory_commands.request(player, "craft", {"recipe_id": "survival:workbench"}).success)
	var bench_pos := Vector3i((player.global_position + Vector3(2, 0, 0)).floor())
	var ground_sample := Vector3i((player.global_position + Vector3.DOWN * 12.0).floor())
	for frame in range(600):
		if GameAPI.world.get_block_id(ground_sample) != "core:air":
			break
		await get_tree().physics_frame
	assert(GameAPI.world.set_block(bench_pos, "survival:workbench"))
	GameAPI.events.emit(GameEvents.AFTER_BLOCK_PLACE, {"player": player, "position": bench_pos, "block_id": "survival:workbench"})
	assert("workbench" in GameAPI.stations.capabilities(player))
	assert(inventory.add_item("core:stick", 3))
	assert(inventory.add_item("survival:planks",3))
	assert(GameAPI.inventory_commands.request(player, "craft", {"recipe_id": "frontier:wood_pickaxe"}).success)
	assert(inventory.assign_to_hotbar("frontier:wood_pickaxe", 0))
	var tool_id := str(inventory.get_slot(0).instance_id)
	GameAPI.item_instances.spend(inventory, 0, 7)
	survival._spawn_protection = 0.0
	survival.receive_damage(4.0, {"damage_type": "fall"})
	player.get_node("FrontierVitals").hunger = 7.0
	assert(survival.health == 16.0)
	game._save_local_player_state()
	var station_path := GameAPI.stations.path
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(station_path))
	assert(parsed.inventory == JSON.parse_string(JSON.stringify(inventory.get_snapshot())))
	assert(parsed.player_data["survival:player_survival"].health == 16.0)
	game.free()
	await get_tree().process_frame
	assert(GameAPI.stations.path.is_empty())
	game = load("res://scenes/main/Game.tscn").instantiate()
	add_child(game)
	for frame in range(12):
		await get_tree().process_frame
	player = game.get_node("Players/1") as PlayerController
	player.set_physics_process(false)
	survival = player.get_node("DamageReceiver") as DamageReceiver
	survival.set_physics_process(false)
	player.get_node("FrontierVitals").set_physics_process(false)
	inventory = player.get_node("Inventory") as Inventory
	assert(survival.health == 16.0)
	assert(inventory.get_slot(0).instance_id == tool_id and GameAPI.item_instances.condition(inventory.get_slot(0)) == 57)
	print("Reloaded hunger: ", player.get_node("FrontierVitals").hunger)
	assert(absf(float(player.get_node("FrontierVitals").hunger) - 7.0) < 0.1)
	assert(not GameAPI.stations.record(GameAPI.stations.key(bench_pos)).is_empty())
	game.free()
	var other := GameAPI.saves.create_world("Other hunger fixture", "54", {"api_version":1,"mods":GameAPI.mods.get_signature(),"content":GameAPI.content.get_content_signature()})
	assert(GameAPI.saves.select_world(str(other.save_name)).valid)
	game = load("res://scenes/main/Game.tscn").instantiate()
	add_child(game)
	for frame in range(12):
		await get_tree().process_frame
	player = game.get_node("Players/1") as PlayerController
	assert(player.get_node("FrontierVitals").hunger > 17.9, "New worlds must not inherit hunger")
	game.free()
	GameAPI.saves.clear_selection()
	GameAPI.saves.root_path = old_root
	GameAPI.saves.legacy_state_path = old_legacy
	print("Progression world PASS: production world lifecycle, native station meshes, empty spawn, hand/bench crafting, shared snapshot, tool identity/condition and health across reload")
	get_tree().quit()
