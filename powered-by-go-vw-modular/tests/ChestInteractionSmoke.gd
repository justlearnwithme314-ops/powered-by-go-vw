extends Node3D

# Integration test: real VoxelTerrain targeting, station UI transfers,
# persistence, and chest destruction. Uses an isolated test save.
class EmptyGenerator extends VoxelGeneratorScript:
	var air_voxel := 0
	func _get_used_channels_mask() -> int:
		return 1 << VoxelBuffer.CHANNEL_TYPE
	func _generate_block(buffer: VoxelBuffer, _origin: Vector3i, _lod: int) -> void:
		buffer.fill(air_voxel, VoxelBuffer.CHANNEL_TYPE)

func _ready() -> void:
	var content := GameAPI.content
	var chest_model: VoxelBlockyModelMesh = content.get_block("survival:chest").model
	assert(not chest_model.collision_aabbs.is_empty(), "Chest needs a targeting/collision box")
	assert(chest_model.mesh.get_aabb().size.y == 14.0 / 16.0)
	var terrain := VoxelTerrain.new()
	var mesher := VoxelMesherBlocky.new()
	mesher.library = content.build_voxel_library()
	terrain.mesher = mesher
	var generator := EmptyGenerator.new()
	generator.air_voxel = content.get_voxel_id(ContentRegistry.AIR_ID)
	terrain.generator = generator
	add_child(terrain)
	var viewer := VoxelViewer.new()
	viewer.view_distance = 32
	viewer.position = Vector3(2,2,2)
	add_child(viewer)
	var world := VoxelWorldService.new(content)
	world.attach(terrain)
	var pos := Vector3i(2,2,2)
	for frame in range(600):
		if world.is_loaded(pos): break
		await get_tree().process_frame
	assert(world.is_loaded(pos), "Test terrain must load")
	var events := EventBus.new()
	var edits := WorldEditService.new(content,world,events)
	var stations := BlockEntityService.new(content,world)
	stations.register_kind("survival:chest",[],{"storage":27})
	var save_path := "user://chest_tests/%d.entities.json" % Time.get_ticks_usec()
	assert(stations.activate(save_path))
	var crafting := CraftingService.new(content,events)
	crafting.stations = stations
	var commands := InventoryCommandService.new(stations,crafting)
	var api := ModAPI.new(content,events,GameAPI.world_generation,world,edits,crafting)
	api.stations = stations
	api.inventory_commands = commands
	api.root_path = "res://mods/crafting_progression"
	var station_mod: Object = (load("res://mods/crafting_progression/mod.gd") as Script).new()
	station_mod.set("_api",api)
	station_mod.set("_active_world",self)
	station_mod.set("_runtime_script",load("res://mods/crafting_progression/StationRuntime.gd"))
	events.subscribe(GameEvents.AFTER_BLOCK_PLACE,Callable(station_mod,"_placed"))
	events.subscribe(GameEvents.AFTER_BLOCK_BREAK,Callable(station_mod,"_broken"))
	events.subscribe(GameEvents.BEFORE_BLOCK_BREAK,Callable(station_mod,"_before_break"))
	var player := CharacterBody3D.new()
	var inventory := Inventory.new()
	inventory.name = "Inventory"
	player.add_child(inventory)
	add_child(player)
	player.position = Vector3(2.5,2,-1)
	stations.bind_inventory(inventory)
	assert(inventory.add_item("core:dirt",8))
	assert(edits.place_block(player,pos,"survival:chest").success)
	var hit: Variant = world.raycast(Vector3(2.5,2.5,-1),Vector3.BACK,8)
	assert(hit != null and hit.position == pos, "A real targeting ray must hit the chest")
	# The ordinary menu can run a local player as an ENet host. Its own
	# inventory must work without a remote-ownership marker.
	var host_peer := ENetMultiplayerPeer.new()
	host_peer.set_bind_ip("127.0.0.1")
	var host_error := ERR_CANT_CREATE
	for offset in range(10):
		host_error = host_peer.create_server(42000 + int(Time.get_ticks_usec() % 1000) + offset,1)
		if host_error == OK: break
	assert(host_error == OK, "Isolated test host must start")
	var host_api := SceneMultiplayer.new()
	host_api.multiplayer_peer = host_peer
	get_tree().set_multiplayer(host_api,get_path())
	assert(player.multiplayer.is_server() and player.is_multiplayer_authority())
	assert(not bool(player.get_meta("inventory_authority",false)))
	var used: Dictionary = station_mod.call("_used",{"player":player,"hit":hit,"handled":false})
	assert(used.handled)
	var runtime: Node = station_mod.get("_runtime")
	assert(is_instance_valid(runtime), "Local station runtime must initialize on demand")
	var ui: Node = runtime.get("_ui")
	assert(is_instance_valid(ui) and get_tree().get_nodes_in_group("station_ui").has(ui))
	var id := stations.key(pos)
	var storage := stations.container(id,"storage")
	assert(storage != null and storage.size() == 27)
	# Use the GUI handlers, not a direct storage insert.
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	ui.call("_select",0)
	ui.call("_station_clicked",mouse,"storage",0)
	assert(storage.count("core:dirt") == 8 and inventory.get_item_count("core:dirt") == 0, "GUI deposits a stack")
	ui.call("_station_clicked",mouse,"storage",0)
	assert(storage.count("core:dirt") == 0 and inventory.get_item_count("core:dirt") == 8, "GUI retrieves a stack")
	ui.call("_select",0)
	mouse.button_index = MOUSE_BUTTON_RIGHT
	ui.call("_station_clicked",mouse,"storage",0)
	assert(storage.count("core:dirt") == 1 and inventory.get_item_count("core:dirt") == 7, "GUI deposits one item")
	ui.call("close")
	assert(stations.save())
	assert(stations.activate(save_path))
	stations.bind_inventory(inventory)
	assert(stations.container(id,"storage").count("core:dirt") == 1, "Chest contents survive reload")
	var broken := edits.break_block(player,pos)
	assert(broken.success and world.get_block_id(pos) == ContentRegistry.AIR_ID, "Chest is destructible")
	assert(stations.record(id).is_empty() and inventory.get_item_count("core:dirt") == 8, "Breaking returns chest contents once")
	assert(broken.drops == [{"item":"survival:chest","count":1}])
	if "--capture" in OS.get_cmdline_user_args():
		await render_preview(chest_model)
	stations.activate("")
	host_peer.close()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	print("[ChestIntegration] PASS: real raycast, open GUI, stack/one-item transfers, reload, break and contents recovery")
	get_tree().quit()

func render_preview(model: VoxelBlockyModelMesh) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256,256)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var mesh := MeshInstance3D.new()
	mesh.mesh = model.mesh
	mesh.material_override = model.get_material_override(0)
	viewport.add_child(mesh)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-35,0)
	light.light_energy = 1.4
	viewport.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.5
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.45
	viewport.add_child(camera)
	camera.position = Vector3(-1.5,1.4,-2)
	camera.look_at(Vector3(0.5,0.4375,0.5))
	for frame in range(5): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	assert(image.save_png("res://tests/chest-preview.png") == OK)
