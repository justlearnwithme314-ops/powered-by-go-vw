extends "CreatureNetworkSmoke.gd"

class FarmWorld extends VoxelWorldService:
	var cells = {}
	func is_loaded(_pos: Vector3i) -> bool: return true
	func get_block_id(pos: Vector3i) -> String: return str(cells.get(pos,"core:stone" if pos.y < 0 else "core:air"))
	func is_solid(pos: Vector3i) -> bool: return bool(content.get_block(get_block_id(pos)).get("solid",false))
	func set_block(pos: Vector3i, id: String) -> bool:
		cells[pos] = id
		return true

func farming(runtime: Node3D) -> Node:
	runtime.api.entities.runtime = runtime
	var world = FarmWorld.new(GameAPI.content)
	runtime.api.world = world
	runtime.api.stations.world = world
	var farm = load("res://mods/basic_survival/SurvivalRuntime.gd").new()
	farm.name = "BasicSurvival"
	runtime.get_parent().add_child(farm)
	farm.setup(runtime.api)
	farm.set_process(false)
	return farm

func run() -> void:
	var server_peer = ENetMultiplayerPeer.new()
	var port = 42000+int(Time.get_ticks_msec()%10000)
	assert(server_peer.create_server(port,4) == OK)
	var host = branch("CreatureHost",server_peer)
	var host_runtime = runtime_for(host)
	var host_farm = farming(host_runtime)
	var client_peer = ENetMultiplayerPeer.new()
	assert(client_peer.create_client("127.0.0.1",port) == OK)
	var client = branch("CreatureClient",client_peer)
	var client_runtime = runtime_for(client)
	var client_farm = farming(client_runtime)
	for i in range(100):
		if client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED: break
		await get_tree().process_frame
	await packets()
	var peer = client_peer.get_unique_id()
	var server_player = player_for(host,host_runtime,peer)
	var client_player = player_for(client,client_runtime,peer)
	client_runtime.join_world.rpc_id(1,"b".repeat(64))
	await packets()
	var inventory = server_player.get_node("Inventory") as Inventory
	inventory.add_item("survival:bow",1)
	inventory.add_item("survival:arrow",2)
	inventory.selected_slot = 0
	var skeleton = host_runtime.spawn("creatures:skeleton",Vector3(0,0.05,-2))
	skeleton.set_physics_process(false)
	await get_tree().physics_frame
	client_farm.request_use.rpc_id(1,Vector3i.ZERO,Vector3(0,-0.15,-1).normalized())
	await packets()
	assert(skeleton.receiver.health == 14 and inventory.get_item_count("survival:arrow") == 1)
	assert((client_player.get_node("Inventory") as Inventory).get_item_count("survival:arrow") == 1)
	client_farm.request_use.rpc_id(1,Vector3i.ZERO,Vector3.FORWARD)
	await packets()
	assert(inventory.get_item_count("survival:arrow") == 1)
	inventory.add_item("frontier:wood_hoe",1)
	inventory.selected_slot = 2
	host_farm.cooldowns.clear()
	host_runtime.api.world.cells[Vector3i.ZERO] = "core:dirt"
	client_farm.request_use.rpc_id(1,Vector3i.ZERO,Vector3.FORWARD)
	await packets()
	assert(host_runtime.api.world.get_block_id(Vector3i.ZERO) == "survival:farmland")
	assert(client_runtime.api.world.get_block_id(Vector3i.ZERO) == "survival:farmland")
	inventory.add_item("survival:wheat_seeds",1)
	inventory.selected_slot = 3
	host_farm.cooldowns.clear()
	client_farm.request_use.rpc_id(1,Vector3i.ZERO,Vector3.FORWARD)
	await packets()
	assert(inventory.get_item_count("survival:wheat_seeds") == 0)
	assert(client_runtime.api.world.get_block_id(Vector3i.UP) == "survival:wheat_crop_0")
	host_farm.grow()
	await packets()
	assert(client_runtime.api.world.get_block_id(Vector3i.UP) == "survival:wheat_crop_1")
	client_runtime.api.world.cells.clear()
	client_farm.request_sync.rpc_id(1)
	await packets()
	client_farm._process(0)
	assert(client_runtime.api.world.get_block_id(Vector3i.UP) == "survival:wheat_crop_1")
	print("Basic survival network PASS: authenticated bow/ammo/rate limit and hoe/seed/growth replication")
	get_tree().root.get_node("CreatureClient").free()
	get_tree().root.get_node("CreatureHost").free()
	get_tree().quit()
