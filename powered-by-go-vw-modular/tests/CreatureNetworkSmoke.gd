extends Node

const RUNTIME = preload("res://mods/entity_framework/EntityRuntime.gd")
const FIXTURE = preload("res://tests/CreatureSmoke.gd")

class Session extends Node3D:
	var persisted: Dictionary = {}
	var destination := ""
	var fail_save := false
	func _save_local_player_state() -> bool:
		if fail_save:
			return false
		for player in $Players.get_children():
			if player.is_multiplayer_authority():
				persisted = player.get_node("Inventory").get_snapshot()
		var file := FileAccess.open(destination, FileAccess.WRITE)
		if file == null:
			return false
		file.store_string(JSON.stringify(persisted))
		file.close()
		return true
	func get_safe_spawn_position() -> Vector3:
		return Vector3(0, 0, 2)

func branch(label: String, peer: ENetMultiplayerPeer) -> Session:
	var root := Node.new()
	root.name = label
	get_tree().root.add_child(root)
	var network := SceneMultiplayer.new()
	get_tree().set_multiplayer(network, root.get_path())
	network.multiplayer_peer = peer
	var game := Session.new()
	game.name = "Game"
	game.destination = "user://creature_network_%s_%d.json" % [label, Time.get_ticks_usec()]
	var players := Node.new()
	players.name = "Players"
	game.add_child(players)
	var viewport := SubViewport.new()
	viewport.name = "Viewport"
	viewport.own_world_3d = true
	root.add_child(viewport)
	viewport.add_child(game)
	return game

func runtime_for(game: Session) -> Node3D:
	var world := Node3D.new()
	world.name = "World"
	game.add_child(world)
	var runtime := RUNTIME.new()
	runtime.name = "Entities"
	world.add_child(runtime)
	var api := ModAPI.new(GameAPI.content, EventBus.new(), GameAPI.world_generation, FIXTURE.FlatWorld.new(GameAPI.content), GameAPI.edits, GameAPI.crafting, "entities:fixture", "1", "res://mods/entity_framework")
	api.saves = WorldSaveService.new("user://creature_network_%d" % Time.get_ticks_usec())
	api.saves.active_world_id = "fixture"
	api.entities = EntityRegistry.new()
	api.entities.definitions = GameAPI.entities.definitions.duplicate(true)
	api.item_instances = GameAPI.item_instances
	api.stations = BlockEntityService.new(api.content, api.world)
	runtime.setup(api)
	runtime.spawning = false
	runtime.set_physics_process(false)
	return runtime

func player_for(game: Session, runtime: Node3D, id: int) -> PlayerController:
	var player := load("res://scenes/player/Player.tscn").instantiate() as PlayerController
	player.name = str(id)
	player.set_multiplayer_authority(id)
	game.get_node("Players").add_child(player)
	player.global_position = Vector3(0, 0.05, 2)
	player.set_physics_process(false)
	player.get_node("VoxelInteractor").set_physics_process(false)
	runtime.api.events.emit(GameEvents.PLAYER_SPAWNED, {"player": player, "peer_id": id})
	return player

func _ready() -> void:
	call_deferred("run")

func packets() -> void:
	await get_tree().create_timer(0.15).timeout

func run() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	var port := 32000 + int(Time.get_ticks_msec() % 10000)
	assert(server_peer.create_server(port, 4) == OK)
	var host := branch("CreatureHost", server_peer)
	var host_runtime := runtime_for(host)
	var client_peer := ENetMultiplayerPeer.new()
	assert(client_peer.create_client("127.0.0.1", port) == OK)
	var client := branch("CreatureClient", client_peer)
	var client_runtime := runtime_for(client)
	for i in range(100):
		if client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
		await get_tree().process_frame
	await packets()
	var peer_id := client_peer.get_unique_id()
	var server_player := player_for(host, host_runtime, peer_id)
	var client_player := player_for(client, client_runtime, peer_id)
	client_runtime.join_world.rpc_id(1, "a".repeat(64))
	await packets()
	assert(client_runtime._joined and host_runtime._peer_keys.has(peer_id))
	# Authority callbacks are resolved from sender, not a caller's nominated player.
	var skeleton := host_runtime.spawn("creatures:skeleton", Vector3(0, 0.05, 0)) as Node3D
	skeleton.set_physics_process(false)
	host_runtime.snapshot.rpc(1, host_runtime.snapshot_data())
	await packets()
	assert(client_runtime.actors.has(skeleton.entity_id))
	var replica: Node3D = client_runtime.actors[skeleton.entity_id]
	assert(replica.replicated and replica.receiver.health == 20)
	client_runtime.snapshot(0, {"entities": {}, "loot": {}})
	assert(client_runtime.actors.has(skeleton.entity_id), "Stale packets must not delete current entities")
	await get_tree().physics_frame
	await get_tree().physics_frame
	client_runtime.request_attack.rpc_id(1, skeleton.entity_id)
	await packets()
	assert(skeleton.receiver.health == 19, "Only server equipment/fist stats may apply")
	client_runtime.request_attack.rpc_id(1, skeleton.entity_id)
	await packets()
	assert(skeleton.receiver.health == 19, "Attack rate limit")
	var server_health := server_player.get_node("DamageReceiver") as DamageReceiver
	var client_health := client_player.get_node("DamageReceiver") as DamageReceiver
	server_health.protection = 0
	host_runtime.damage_player(server_player, 3, skeleton)
	await packets()
	assert(server_health.health == 17 and client_health.health == 17)
	client_health.receive_damage(1000, {})
	assert(client_health.health == 17, "Client must not simulate server damage")
	server_health.cooldown = 0
	host_runtime.damage_player(server_player, 100, skeleton)
	await packets()
	assert(server_health.dead and client_health.dead and client_player.get_meta("gameplay_disabled"))
	client_health.request_respawn.rpc_id(1)
	await packets()
	assert(server_health.health == 20 and not server_health.dead and not client_health.dead)
	# Death, loot reservation and the outbox are persisted before delivery.
	var pig := host_runtime.spawn("creatures:pig", Vector3(0, 0.05, 2)) as Node3D
	pig.set_physics_process(false)
	pig.receiver.receive_damage(20, {})
	var loot_id: String = host_runtime.loot.keys()[0]
	assert(host_runtime.reserve_loot(server_player, loot_id))
	assert(host_runtime.offers.has(loot_id) and not host_runtime.loot.has(loot_id))
	var stack: Dictionary = host_runtime.profiles[host_runtime._peer_keys[peer_id]].duplicate(true)
	client.fail_save = true
	host_runtime.reward.rpc_id(peer_id, loot_id, stack)
	await packets()
	var inventory := client_player.get_node("Inventory") as Inventory
	assert(inventory.get_item_count("creatures:raw_meat") == 0 and not inventory.reward_receipts.has(loot_id))
	assert(host_runtime.offers.has(loot_id))
	client.fail_save = false
	host_runtime.reward.rpc_id(peer_id, loot_id, stack)
	await packets()
	assert(inventory.get_item_count("creatures:raw_meat") == 2 and inventory.reward_receipts.has(loot_id))
	assert(not host_runtime.offers.has(loot_id))
	host_runtime.reward.rpc_id(peer_id, loot_id, stack)
	await packets()
	assert(inventory.get_item_count("creatures:raw_meat") == 2)
	var saved := JSON.parse_string(FileAccess.get_file_as_string(client.destination)) as Dictionary
	assert(saved.reward_receipts.has(loot_id))
	# Inventory moves are server operations; cursor ownership is mirrored intact.
	inventory.click_slot(0, true)
	await packets()
	var server_inventory := server_player.get_node("Inventory") as Inventory
	assert(inventory.cursor.stack_at(0).count == 1 and server_inventory.cursor.stack_at(0).count == 1)
	inventory.click_slot(3)
	await packets()
	assert(inventory.get_slot(3).count == 1 and server_inventory.get_slot(3).count == 1)
	assert(int(inventory.add_stack({"id": "frontier:diamond_sword", "count": 1}).added) == 0, "Clients cannot grant equipment")
	assert(server_inventory.add_item("frontier:wood_pickaxe", 1))
	assert(host_runtime.save_inventory(server_player))
	await packets()
	server_inventory.set_selected_slot(1)
	assert(host_runtime.save_inventory(server_player))
	await packets()
	assert(inventory.get_selected_item_id() == "frontier:wood_pickaxe")
	var condition: float = GameAPI.item_instances.condition(server_inventory.get_slot(1))
	host_runtime._attack_times.clear()
	client_runtime.request_attack.rpc_id(1, skeleton.entity_id)
	await packets()
	assert(skeleton.receiver.health == 17 and GameAPI.item_instances.condition(server_inventory.get_slot(1)) == condition - 1)
	assert(GameAPI.item_instances.condition(inventory.get_slot(1)) == condition - 1)
	var tool_id: String = server_inventory.get_slot(1).instance_id
	# Despawns are replicated without producing another death reward.
	var skeleton_id: String = skeleton.entity_id
	host_runtime._remove_actor(skeleton_id)
	host_runtime.snapshot.rpc(2, host_runtime.snapshot_data())
	await packets()
	assert(not client_runtime.actors.has(skeleton_id))
	# Reconnect with the same private credential; authoritative inventory survives.
	client_peer.close()
	get_tree().root.get_node("CreatureClient").free()
	server_player.free()
	await packets()
	var reconnect_peer := ENetMultiplayerPeer.new()
	assert(reconnect_peer.create_client("127.0.0.1", port) == OK)
	client = branch("CreatureClient", reconnect_peer)
	client_runtime = runtime_for(client)
	for i in range(100):
		if reconnect_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
		await get_tree().process_frame
	await packets()
	peer_id = reconnect_peer.get_unique_id()
	server_player = player_for(host, host_runtime, peer_id)
	client_player = player_for(client, client_runtime, peer_id)
	client_runtime.join_world.rpc_id(1, "a".repeat(64))
	await packets()
	inventory = client_player.get_node("Inventory") as Inventory
	assert(client_runtime._joined and inventory.get_slot(1).instance_id == tool_id)
	assert(GameAPI.item_instances.condition(inventory.get_slot(1)) == condition - 1)
	assert(inventory.get_item_count("creatures:raw_meat") == 2)
	assert(host_runtime.save_state())
	var persisted := JSON.parse_string(FileAccess.get_file_as_string(host_runtime.path)) as Dictionary
	assert(persisted.profiles["a".repeat(64).sha256_text()].slots[1].instance_id == tool_id)
	print("Creature network PASS: late snapshot/stale packets, server attack rate/stats, health/death/respawn, reward escrow, failed-save rollback, persisted receipts, duplicate delivery and despawn")
	get_tree().root.get_node("CreatureClient").free()
	get_tree().root.get_node("CreatureHost").free()
	get_tree().quit()
