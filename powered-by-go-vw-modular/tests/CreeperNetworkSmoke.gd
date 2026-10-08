extends "BasicSurvivalNetworkSmoke.gd"

func explosion_service(runtime: Node3D, farm: Node) -> Node3D:
	runtime.api.edits = WorldEditService.new(runtime.api.content,runtime.api.world,runtime.api.events)
	var service = load("res://mods/basic_survival/ExplosionRuntime.gd").new()
	service.name = "CreeperExplosions"
	runtime.get_parent().add_child(service)
	service.setup(runtime.api,farm)
	return service

func run() -> void:
	var server_peer = ENetMultiplayerPeer.new()
	var port = 44000+int(Time.get_ticks_msec()%10000)
	assert(server_peer.create_server(port,4) == OK)
	var host = branch("CreatureHost",server_peer)
	var host_runtime = runtime_for(host)
	var host_farm = farming(host_runtime)
	var host_blast = explosion_service(host_runtime,host_farm)
	var client_peer = ENetMultiplayerPeer.new()
	assert(client_peer.create_client("127.0.0.1",port) == OK)
	var client = branch("CreatureClient",client_peer)
	var client_runtime = runtime_for(client)
	var client_farm = farming(client_runtime)
	var client_blast = explosion_service(client_runtime,client_farm)
	for i in range(100):
		if client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED: break
		await get_tree().process_frame
	await packets()
	var peer = client_peer.get_unique_id()
	var server_player = player_for(host,host_runtime,peer)
	var client_player = player_for(client,client_runtime,peer)
	server_player.global_position = Vector3(0.5,0.05,2.5)
	client_player.global_position = server_player.global_position
	client_runtime.join_world.rpc_id(1,"c".repeat(64))
	await packets()
	server_player.get_node("DamageReceiver").protection = 0
	host_runtime.api.world.cells[Vector3i(1,0,0)] = "core:dirt"
	client_runtime.api.world.cells[Vector3i(1,0,0)] = "core:dirt"
	var creeper = host_runtime.spawn("creatures:box_creeper",Vector3(0.5,0.05,0.5))
	creeper.set_physics_process(false)
	host_runtime.snapshot.rpc(1,host_runtime.snapshot_data())
	await packets()
	assert(client_runtime.actors.has(creeper.entity_id))
	await get_tree().physics_frame
	var ability = creeper.abilities[0]
	ability.tick(creeper,0.5)
	host_runtime.snapshot.rpc(2,host_runtime.snapshot_data())
	await packets()
	assert(client_runtime.actors[creeper.entity_id].state == "fuse")
	# The fixture has no physics floor; stop pre-blast free-fall before measuring launch.
	client_player.set_physics_process(false)
	client_player.global_position = server_player.global_position
	client_player.velocity = Vector3.ZERO
	ability.tick(creeper,1.01)
	await packets()
	assert(creeper.dead and host_blast.effect_count == 1 and client_blast.effect_count == 1)
	assert(not client_runtime.actors[creeper.entity_id].visual.visible)
	assert(server_player.get_node("DamageReceiver").health<20)
	assert(client_player.get_node("DamageReceiver").health == server_player.get_node("DamageReceiver").health)
	assert(client_player.velocity.y>0 and client_player.velocity.z>0)
	assert(host_runtime.api.world.get_block_id(Vector3i(1,0,0)) == "core:air")
	assert(client_runtime.api.world.get_block_id(Vector3i(1,0,0)) == "core:air")
	client_runtime.api.world.cells.clear()
	client_farm.request_sync.rpc_id(1)
	await packets()
	client_farm._process(0)
	assert(client_runtime.api.world.get_block_id(Vector3i(0,-1,0)) == "core:air")
	assert(not client_blast.detonate(client_runtime.actors[creeper.entity_id]))
	print("Creeper network PASS: replicated fuse, one sound/effect per peer, server health, owner knockback, terrain destruction and late-join crater replay")
	get_tree().multiplayer_poll = false
	get_tree().root.get_node("CreatureClient").free()
	get_tree().root.get_node("CreatureHost").free()
	client_peer.close()
	server_peer.close()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()
