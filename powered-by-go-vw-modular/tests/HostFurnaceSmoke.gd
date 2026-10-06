extends Node

func _ready() -> void:
	GameAPI.saves.root_path = "user://host_furnace_tests/%d" % Time.get_ticks_usec()
	var created := GameAPI.saves.create_world("Host furnace", "53", {"api_version":1,"mods":GameAPI.mods.get_signature(),"content":GameAPI.content.get_content_signature()})
	assert(created.success and GameAPI.saves.select_world(created.save_name).valid)
	assert(NetworkManager.host_game(34000 + int(Time.get_ticks_msec() % 10000)) == OK)
	var game := load("res://scenes/main/Game.tscn").instantiate() as Node3D
	add_child(game)
	for frame in range(12):
		await get_tree().process_frame
	var player := game.get_node("Players/1") as PlayerController
	player.set_physics_process(false)
	var runtime := GameAPI.entities.runtime.get_parent().get_node("CraftingStations")
	assert(runtime != null and GameAPI.stations.path.ends_with(".stations.json"))
	runtime.set_process(false)
	var ground = null
	for frame in range(600):
		ground = GameAPI.world.raycast(player.global_position, Vector3.DOWN,60)
		if ground != null:
			break
		await get_tree().physics_frame
	assert(ground != null)
	var pos := Vector3i(ground.position) + Vector3i.UP
	assert(GameAPI.world.set_block(pos, "survival:furnace"))
	player.global_position = Vector3(pos) + Vector3(2,0,0)
	var id := GameAPI.stations.ensure(pos)
	assert(not id.is_empty())
	runtime.open_station(player,id)
	assert(runtime._ui != null)
	var inventory := player.get_node("Inventory") as Inventory
	inventory.add_item("frontier:iron_lump",1)
	inventory.add_item("core:log",1)
	for item in ["frontier:iron_lump", "core:log"]:
		var index := -1
		for slot in range(Inventory.CAPACITY):
			if str(inventory.get_slot(slot).get("id","")) == item:
				index = slot
		var name := "fuel" if item == "core:log" else "input"
		var target := GameAPI.stations.container(id,name)
		assert(GameAPI.inventory_commands.request(player,"station_transfer",{"station":id,"container":name,"station_revision":target.revision,"into":true,"from":index,"to":0,"amount":1}).success)
	runtime.tick_furnace(id,8.0)
	assert(GameAPI.stations.container(id,"output").count("frontier:iron_ingot") == 1)
	assert(GameAPI.stations.save())
	assert(FileAccess.file_exists(GameAPI.stations.path))
	runtime._ui.close()
	game.free()
	NetworkManager.disconnect_game()
	print("Host furnace PASS: production host mode, station UI, inventory transfers, iron smelting and persistence")
	get_tree().quit()
