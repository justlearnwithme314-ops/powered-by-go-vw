extends Node

const DEFAULT_PORT: int = 25565
const MAX_PLAYERS: int = 16

signal player_connected(id: int)
signal player_disconnected(id: int)

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error == OK:
		multiplayer.multiplayer_peer = peer
		print("[Network] Hosting server on port ", port)
	return error

func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	if error == OK:
		multiplayer.multiplayer_peer = peer
		print("[Network] Connecting to ", address, ":", port)
	return error

func _on_peer_connected(id: int) -> void:
	print("[Network] Peer connected: ", id)
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("[Network] Peer disconnected: ", id)
	player_disconnected.emit(id)
