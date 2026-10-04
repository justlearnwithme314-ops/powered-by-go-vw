extends Node

const DEFAULT_PORT := 25565
const MAX_PLAYERS := 16
const protocol_version := "govw3"

signal player_connected(id: int)
signal player_disconnected(id: int)
signal connection_succeeded
signal connection_failed

var connection_established := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)


func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS)
	if error == OK:
		connection_established = true
		multiplayer.multiplayer_peer = peer
		print("[Network] Hosting on port %d." % port)
	return error


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error == OK:
		connection_established = false
		multiplayer.multiplayer_peer = peer
		print("[Network] Connecting to %s:%d." % [address, port])
	return error


func disconnect_game() -> void:
	connection_established = false
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


func _on_connected_to_server() -> void:
	connection_established = true
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	connection_established = false
	connection_failed.emit()


func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if id == 1 and not multiplayer.is_server():
		connection_established = false
	player_disconnected.emit(id)
