extends Node

@export var player_scene: PackedScene
@export var spawn_height_above_ground: int = 6

@onready var players: Node = $Players
@onready var spawn_point: Node3D = $Players/SpawnPoint

var spawned_peer_ids: Array[int] = []
var world_noise := WorldNoise.new()

# Stores all block changes during the current running session.
# Example:
# "10,35,-2" : Block.AIR
var voxel_changes: Dictionary = {}


func _ready() -> void:
	if player_scene == null:
		push_error("[GameManager] Player Scene is not assigned.")
		return

	if multiplayer.is_server():
		print("[GameManager] Server ready.")

		var host_id := multiplayer.get_unique_id()
		_register_and_spawn_player(host_id)

		NetworkManager.player_connected.connect(_on_player_connected)

	else:
		print("[GameManager] Client scene loaded. Waiting before ready signal.")
		call_deferred("_notify_server_when_ready")


func _notify_server_when_ready() -> void:
	await get_tree().create_timer(0.25).timeout

	if multiplayer.has_multiplayer_peer():
		var my_id := multiplayer.get_unique_id()
		print("[GameManager] Client notifying server. My ID: ", my_id)
		_client_ready.rpc_id(1, my_id)


func _on_player_connected(peer_id: int) -> void:
	print("[GameManager] Peer connected: ", peer_id)
	# Do not spawn here.
	# Wait until the client loads Game.tscn and calls _client_ready.


@rpc("any_peer", "reliable")
func _client_ready(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	print("[GameManager] Client ready on server: ", peer_id)

	# Send all existing players to the new client.
	for existing_id in spawned_peer_ids:
		_spawn_player_remote.rpc_id(peer_id, existing_id)

	# Register the new player.
	if not spawned_peer_ids.has(peer_id):
		spawned_peer_ids.append(peer_id)

	# Spawn the new player on everyone, including the new client.
	_spawn_player_remote.rpc(peer_id)

	# Spawn the new player locally on the server too.
	_spawn_player_local(peer_id)

	# Send all previous voxel edits to the newly joined client.
	send_voxel_history.rpc_id(peer_id, voxel_changes)


func _register_and_spawn_player(peer_id: int) -> void:
	if not spawned_peer_ids.has(peer_id):
		spawned_peer_ids.append(peer_id)

	_spawn_player_local(peer_id)


@rpc("authority", "reliable")
func _spawn_player_remote(peer_id: int) -> void:
	_spawn_player_local(peer_id)


func _spawn_player_local(peer_id: int) -> void:
	var player_name := str(peer_id)

	if players.has_node(player_name):
		return

	print("[GameManager] Spawning player locally: ", peer_id)

	var player = player_scene.instantiate()

	player.name = player_name
	player.set_multiplayer_authority(peer_id)

	players.add_child(player)

	var spawn_position := get_safe_spawn_position()
	player.global_position = spawn_position

	print("[GameManager] Player ", peer_id, " spawned at: ", spawn_position)


func get_safe_spawn_position() -> Vector3:
	var spawn_x := int(round(spawn_point.global_position.x))
	var spawn_z := int(round(spawn_point.global_position.z))

	var surface_y := TerrainGenerator.get_surface_height(
		spawn_x,
		spawn_z,
		world_noise
	)

	var safe_y := surface_y + spawn_height_above_ground

	return Vector3(
		float(spawn_x) + 0.5,
		float(safe_y),
		float(spawn_z) + 0.5
	)


func voxel_pos_to_key(pos: Vector3i) -> String:
	return str(pos.x) + "," + str(pos.y) + "," + str(pos.z)


func key_to_voxel_pos(key: String) -> Vector3i:
	var parts := key.split(",")

	return Vector3i(
		parts[0].to_int(),
		parts[1].to_int(),
		parts[2].to_int()
	)


@rpc("any_peer", "reliable")
func request_voxel_change(pos: Vector3i, block_id: int) -> void:
	if not multiplayer.is_server():
		return

	# If this is placing a solid block, do not allow placing inside any player.
	# Destroying blocks uses Block.AIR, so destruction is allowed.
	if block_id != Block.AIR:
		if is_block_overlapping_any_player(pos):
			print("[GameManager] Rejected block placement inside player at: ", pos)
			return

	var key := voxel_pos_to_key(pos)

	voxel_changes[key] = block_id

	apply_voxel_change.rpc(pos, block_id)


@rpc("authority", "call_local", "reliable")
func apply_voxel_change(pos: Vector3i, block_id: int) -> void:
	if Global.active_terrain == null:
		push_warning("[GameManager] Cannot apply voxel change. Global.active_terrain is null.")
		return

	var tool := Global.active_terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	tool.set_voxel(pos, block_id)


@rpc("authority", "reliable")
func send_voxel_history(changes: Dictionary) -> void:
	print("[GameManager] Received voxel history. Changes: ", changes.size())

	await get_tree().create_timer(0.5).timeout

	for key in changes.keys():
		var pos := key_to_voxel_pos(key)
		var block_id: int = changes[key]

		apply_voxel_change(pos, block_id)


func is_block_overlapping_any_player(block_pos: Vector3i) -> bool:
	for child in players.get_children():
		if child is CharacterBody3D:
			if does_block_overlap_player(block_pos, child):
				return true

	return false


func does_block_overlap_player(block_pos: Vector3i, player: CharacterBody3D) -> bool:
	var block_center := Vector3(
		float(block_pos.x) + 0.5,
		float(block_pos.y) + 0.5,
		float(block_pos.z) + 0.5
	)

	var player_feet := player.global_position
	var player_head := player.global_position + Vector3(0.0, 1.8, 0.0)

	var horizontal_distance := Vector2(
		block_center.x - player.global_position.x,
		block_center.z - player.global_position.z
	).length()

	var overlaps_vertically := (
		block_center.y > player_feet.y - 0.2
		and block_center.y < player_head.y + 0.2
	)

	if horizontal_distance < 0.85 and overlaps_vertically:
		return true

	return false


@rpc("any_peer", "unreliable")
func request_player_sync(
	peer_id: int,
	pos: Vector3,
	rot_y: float,
	cam_rot_x: float
) -> void:
	if not multiplayer.is_server():
		return

	broadcast_player_sync.rpc(peer_id, pos, rot_y, cam_rot_x)


@rpc("authority", "call_local", "unreliable")
func broadcast_player_sync(
	peer_id: int,
	pos: Vector3,
	rot_y: float,
	cam_rot_x: float
) -> void:
	var player_name := str(peer_id)

	if not players.has_node(player_name):
		return

	var player := players.get_node(player_name)

	if player == null:
		return

	if player.is_multiplayer_authority():
		return

	player.global_position = pos
	player.rotation.y = rot_y

	var player_camera := player.get_node_or_null("Camera3D")

	if player_camera:
		player_camera.rotation.x = cam_rot_x
