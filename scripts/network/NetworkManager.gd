extends Node

const PORT := 7777
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var peer: ENetMultiplayerPeer

@onready var players_container: Node = get_parent().get_node("Players")
@onready var spawn_point: Node3D = get_parent().get_node("SpawnPoint")


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func start_server() -> void:
	print("")
	print("===== STARTING SERVER =====")

	peer = ENetMultiplayerPeer.new()

	var err := peer.create_server(PORT)
	if err != OK:
		push_error("Failed to start server. Error: %s" % err)
		return

	multiplayer.multiplayer_peer = peer
	var world = get_tree().get_first_node_in_group("world")
	if world:
		world.generate_world()

	print("Server started.")
	print("Listening on port %d" % PORT)
	print("Server peer id: %d" % multiplayer.get_unique_id())


func start_client(host: String) -> void:
	print("")
	print("===== STARTING CLIENT =====")

	peer = ENetMultiplayerPeer.new()

	var err := peer.create_client(host, PORT)
	if err != OK:
		push_error("Failed to connect.")
		return

	multiplayer.multiplayer_peer = peer

	print("Connecting to %s:%d..." % [host, PORT])


func _on_connected_to_server() -> void:
	print("")
	print("===== CONNECTED =====")
	print("My peer id: %d" % multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	print("")
	print("===== CONNECTION FAILED =====")


func _on_server_disconnected() -> void:
	print("")
	print("===== LOST CONNECTION TO SERVER =====")


func _on_peer_connected(id: int) -> void:
	print("")
	print("Peer connected: %d" % id)

	if !multiplayer.is_server():
		return

	_spawn_player(id)

	spawn_player_rpc.rpc(id)

	_sync_existing_players_to(id)

	var world = get_tree().get_first_node_in_group("world")
	if world:
		world.sync_world_to(id)


func _on_peer_disconnected(id: int) -> void:
	print("")
	print("Peer disconnected: %d" % id)

	if multiplayer.is_server():
		# Spawn the new player locally.
		_spawn_player(id)

		# Tell everyone about the new player.
		spawn_player_rpc.rpc(id)

		# Tell the new player about everyone already connected.
		_sync_existing_players_to(id)

		# Send the current world to the new player.
		var world = get_tree().get_first_node_in_group("world")
		if world != null:
			world.sync_world_to(id)

@rpc("authority", "reliable")
func spawn_player_rpc(peer_id: int) -> void:
	_spawn_player(peer_id)


@rpc("authority", "reliable")
func despawn_player_rpc(peer_id: int) -> void:
	_despawn_player(peer_id)


func _sync_existing_players_to(new_peer_id: int) -> void:
	for child in players_container.get_children():
		var existing_id := int(child.name)
		if existing_id == new_peer_id:
			continue
		spawn_player_rpc.rpc_id(new_peer_id, existing_id)


func _spawn_player(peer_id: int) -> void:
	var players := get_parent().get_node("Players")

	# Prevent duplicate players.
	if players.has_node(str(peer_id)):
		print("Player %d already exists." % peer_id)
		return

	print("Spawning player %d" % peer_id)

	var player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)

	player.global_position = Vector3(0, 0, 0)

	players.add_child(player)

	print("Player %d added." % peer_id)

	print("--- Current Players ---")
	for child in players.get_children():
		print("  ", child.name)
	print("-----------------------")

func _despawn_player(peer_id: int) -> void:
	if not players_container.has_node(str(peer_id)):
		return

	players_container.get_node(str(peer_id)).queue_free()
	print("Player %d removed." % peer_id)
