extends Node3D

class FlatWorld extends VoxelWorldService:
	var cells = {}
	func is_loaded(_pos: Vector3i) -> bool: return true
	func get_block_id(pos: Vector3i) -> String: return str(cells.get(pos,"core:stone" if pos.y < 0 else "core:air"))
	func is_solid(pos: Vector3i) -> bool: return bool(content.get_block(get_block_id(pos)).get("solid",false))
	func set_block(pos: Vector3i, id: String) -> bool:
		cells[pos] = id
		return true

func _ready() -> void:
	var world = FlatWorld.new(GameAPI.content)
	var events = EventBus.new()
	var api = ModAPI.new(GameAPI.content,events,GameAPI.world_generation,world,WorldEditService.new(GameAPI.content,world,events),GameAPI.crafting,"survival:test","1","res://mods/basic_survival")
	api.saves = GameAPI.saves
	api.entities = EntityRegistry.new()
	api.entities.definitions = GameAPI.entities.definitions.duplicate(true)
	api.item_instances = GameAPI.item_instances
	api.stations = BlockEntityService.new(api.content,world)
	api.stations.register_kind("survival:chest",[],{"storage":27})
	api.stations.register_kind("survival:workbench",["workbench"],{})
	var path = "user://basic_survival_tests/"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(path)
	api.stations.activate(path+"/stations.json")
	api.inventory_commands = InventoryCommandService.new(api.stations,GameAPI.crafting)
	var player = CharacterBody3D.new()
	player.name = "1"
	player.add_to_group("player_character")
	add_child(player)
	var inventory = Inventory.new()
	inventory.name = "Inventory"
	player.add_child(inventory)
	api.stations.bind_inventory(inventory)
	var camera = Camera3D.new()
	camera.name = "Camera3D"
	player.add_child(camera)
	camera.position.y = 1
	var farm = load("res://mods/basic_survival/SurvivalRuntime.gd").new()
	add_child(farm)
	farm.setup(api)
	farm.save_path = path+"/farming.json"
	farm.set_process(false)
	world.cells[Vector3i.ZERO] = "core:dirt"
	inventory.add_item("frontier:wood_hoe",1)
	assert(farm.perform(player,Vector3i.ZERO,Vector3.FORWARD))
	assert(world.get_block_id(Vector3i.ZERO) == "survival:farmland")
	assert(GameAPI.item_instances.condition(inventory.get_slot(0)) == 63)
	inventory.add_item("survival:wheat_seeds",2)
	inventory.selected_slot = 1
	farm.cooldowns.clear()
	assert(farm.perform(player,Vector3i.ZERO,Vector3.FORWARD))
	assert(inventory.get_item_count("survival:wheat_seeds") == 1)
	for tick in range(7): farm.grow()
	assert(world.get_block_id(Vector3i.UP) == "survival:wheat_crop_7")
	var harvest = GameAPI.events.emit(GameEvents.BEFORE_BLOCK_BREAK,{"position":Vector3i.UP,"block_id":"survival:wheat_crop_7","drops":[],"cancelled":false})
	assert(harvest.drops == [{"item":"survival:wheat_seeds","count":2},{"item":"survival:wheat","count":3}])
	farm.save_state()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(farm.save_path))
	assert(saved.cells["0,1,0"] == "survival:wheat_crop_7")
	# Recipes use the new wood tags and the existing expandable grid service.
	world.cells[Vector3i(2,0,0)] = "survival:workbench"
	var grid = load("res://mods/shaped_crafting/GridCrafting.gd").new()
	grid.setup(api)
	grid.custom_patterns = GameAPI.crafting.grid_service.custom_patterns.duplicate(true)
	grid.command(player,inventory,"grid_resize",{})
	for index in [0,1,2,3,5,6,7,8]:
		put(inventory.crafting_grid,index,"survival:birch_planks" if index%2 else "survival:oak_planks")
	assert(grid.command(player,inventory,"grid_craft",{"recipe_id":"survival:chest"}).success)
	for index in [1,3,7]: put(inventory.crafting_grid,index,"core:stick")
	for index in [2,5,8]: put(inventory.crafting_grid,index,"survival:string")
	assert(grid.command(player,inventory,"grid_craft",{"recipe_id":"survival:bow"}).success)
	assert(inventory.get_item_count("survival:bow") == 1)
	var tree = load("res://mods/tree_props/mod.gd").new()
	var buffer = VoxelBuffer.new()
	buffer.create(24,24,24)
	var context = WorldGenContext.new(buffer,Vector3i.ZERO,0,53,WorldNoise.new(53),api.content.create_snapshot())
	tree._emit_tree(context,Vector3i(10,0,10),5)
	var log_id = context.get_block_id_local(Vector3i(10,1,10))
	assert("survival:tree_log" in api.content.get_block(log_id).tags)
	assert(context.get_block_id_local(Vector3i(11,5,10)) == log_id.replace("_log","_leaves"))
	world.cells[Vector3i(1,0,0)] = "survival:chest"
	var chest = api.stations.ensure(Vector3i(1,0,0))
	var storage = api.stations.container(chest,"storage")
	assert(storage.size() == 27)
	inventory.add_item("survival:wheat",3)
	storage.insert({"id":"survival:wheat","count":3})
	assert(api.stations.save())
	assert(api.stations.activate(path+"/stations.json"))
	api.stations.bind_inventory(inventory)
	assert(api.stations.container(chest,"storage").count("survival:wheat") == 3)
	var station_runtime = load("res://mods/crafting_progression/StationRuntime.gd").new()
	add_child(station_runtime)
	api.root_path = "res://mods/crafting_progression"
	station_runtime.setup(api)
	station_runtime.tick_furnace(chest,1)
	var ui = load("res://mods/crafting_progression/StationUI.gd").new()
	player.add_child(ui)
	ui.setup(player,chest,api)
	assert(ui._station_buttons.storage.size() == 27 and not ui._burn.visible)
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/chest-ui-preview.png")
	ui.close()
	# Actual physics ray verifies bow damage, ammo consumption and cooldown.
	var target = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3.ONE
	shape.shape = box
	target.add_child(shape)
	target.position = Vector3(0,1,-4)
	var receiver = DamageReceiver.new()
	receiver.name = "DamageReceiver"
	target.add_child(receiver)
	add_child(target)
	await get_tree().physics_frame
	inventory.add_item("survival:arrow",2)
	for i in range(Inventory.CAPACITY):
		if inventory.get_slot(i).get("id","") == "survival:bow": inventory.selected_slot = i
	assert(GameAPI.item_instances.maximum(inventory.get_slot(inventory.selected_slot)) == 384)
	farm.cooldowns.clear()
	assert(farm.perform(player,Vector3i.ZERO,Vector3.FORWARD))
	assert(receiver.health == 94 and inventory.get_item_count("survival:arrow") == 1)
	assert(GameAPI.item_instances.condition(inventory.get_slot(inventory.selected_slot)) == 383)
	assert(not farm.perform(player,Vector3i.ZERO,Vector3.FORWARD))
	var entity_runtime = load("res://mods/entity_framework/EntityRuntime.gd").new()
	add_child(entity_runtime)
	entity_runtime.setup(api)
	entity_runtime.spawning = false
	entity_runtime.set_physics_process(false)
	api.entities.runtime = entity_runtime
	for kind in ["pig","cow","sheep","chicken","zombie","skeleton","creeper","spider"]:
		var actor = entity_runtime.spawn("creatures:"+kind,Vector3(4,0,0))
		assert(actor != null and actor.visual.material.albedo_texture != null)
		actor.set_physics_process(false)
		actor.visual.animate("wander",1,0)
		assert(actor.visual.limbs.size() > 0)
	for id in api.content.get_item_ids():
		var icon = str(api.content.get_item(id).get("icon",""))
		if not icon.is_empty(): assert(ResourceLoader.exists(icon))
	print("Basic survival PASS: all eight mob visuals, hoe wear, planting/growth/harvest, saved crops, chest/UI persistence, physics bow damage/ammo/cooldown and asset references")
	api.entities.runtime = null
	entity_runtime.queue_free()
	station_runtime.queue_free()
	farm.queue_free()
	player.queue_free()
	target.queue_free()
	get_tree().quit()

func put(grid: SlotContainer, index: int, id: String) -> void:
	var source = SlotContainer.new(GameAPI.content,1)
	source.insert({"id":id,"count":1})
	assert(source.transfer_to(grid,0,index).success)
