extends Node

@export var player_scene: PackedScene
@export var spawn_height_above_ground: int = 6

@onready var players: Node = $Players
@onready var spawn_point: Marker3D = $Players/SpawnPoint

const PLAYER_STATE_PATH: String = "user://player_state.json"
const MAX_VOXEL_HISTORY: int = 50000
const SYNC_STATE: Script = preload("res://core/network/PlayerSyncState.gd")

var spawned_peer_ids: Array[int] = []
var voxel_changes: Dictionary = {}
var _voxel_change_order: Array[String] = []
var _next_request_id: int = 1
var _local_player: CharacterBody3D = null
var _state_path: String = ""
var _state_load_path: String = ""
var _inventory_dirty: bool = false
var _inventory_save_timer: float = 0.0

signal edit_result(request_id: int, action: String, result: Dictionary)


func _process(delta: float) -> void:
	if _inventory_dirty:
		_inventory_save_timer += delta
		if _inventory_save_timer >= 1.0:
			_save_local_player_state()
			_inventory_dirty = false
			_inventory_save_timer = 0.0


func _ready() -> void:
	var config: Dictionary = GameAPI.saves.selected_config()
	if config.is_empty():
		if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
			return # World redirects unselected local launches to the menu.
		_state_path = GameAPI.saves.legacy_state_path
		_state_load_path = _state_path
	else:
		var save_id: String = str(config.save_name)
		_state_path = GameAPI.saves.state_path(save_id)
		_state_load_path = GameAPI.saves.state_load_path(save_id)
	GameAPI.session = self
	GameAPI.events.emit(GameEvents.GAME_STARTED, {"game": self})

	if not NetworkManager.player_connected.is_connected(_on_player_connected):
		NetworkManager.player_connected.connect(_on_player_connected)

	if not NetworkManager.player_disconnected.is_connected(_on_player_disconnected):
		NetworkManager.player_disconnected.connect(_on_player_disconnected)

	if not multiplayer.has_multiplayer_peer():
		call_deferred("_spawn_local_player", 1)
	elif multiplayer.is_server():
		call_deferred("_spawn_local_player", multiplayer.get_unique_id())
	else:
		if NetworkManager.connection_established:
			call_deferred("notify_client_ready")
		elif not NetworkManager.connection_succeeded.is_connected(_on_connection_succeeded):
			NetworkManager.connection_succeeded.connect(_on_connection_succeeded)


func _exit_tree() -> void:
	_save_local_player_state()
	GameAPI.events.emit(GameEvents.GAME_STOPPING, {"game": self})

	if GameAPI.session == self:
		GameAPI.session = null


func _on_connection_succeeded() -> void:
	if is_inside_tree() and not multiplayer.is_server():
		call_deferred("notify_client_ready")


func _spawn_local_player(peer_id: int) -> void:
	if not spawned_peer_ids.has(peer_id):
		spawned_peer_ids.append(peer_id)

	_spawn_player_local(peer_id)


func _on_player_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		print("[GameManager] Peer connected: ", peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	spawned_peer_ids.erase(peer_id)

	var node: Node = players.get_node_or_null(str(peer_id))
	if node == null:
		return

	GameAPI.events.emit(GameEvents.PLAYER_DESPAWNED, {
		"player": node,
		"peer_id": peer_id,
	})

	if node == _local_player:
		_save_local_player_state()
		_local_player = null

	node.queue_free()


func notify_client_ready() -> void:
	if multiplayer.is_server():
		return

	if not multiplayer.has_multiplayer_peer():
		return

	if not NetworkManager.connection_established:
		return

	_client_ready.rpc_id(
		1,
		multiplayer.get_unique_id(),
		_get_content_signature()
	)


@rpc("any_peer", "reliable")
func _client_ready(peer_id: int, content_signature: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0:
		peer_id = sender_id

	var expected: String = _get_content_signature()
	if content_signature != expected:
		push_error(
			"[GameManager] Content mismatch for peer %d; disconnecting." % peer_id
		)

		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return

	var existing_ids: Array[int] = spawned_peer_ids.duplicate()

	if not spawned_peer_ids.has(peer_id):
		spawned_peer_ids.append(peer_id)

	# The server also owns a copy of every player node. Movement remains
	# client-authoritative, but the server keeps the latest transform for
	# edit distance and collision convenience.
	_spawn_player_local(peer_id)

	# Send existing players to the joining client.
	for existing_id: int in existing_ids:
		if existing_id != peer_id:
			_spawn_player_remote.rpc_id(peer_id, existing_id)

	# Tell all clients about the new player.
	_spawn_player_remote.rpc(peer_id)

	# Send the current session's bounded voxel delta history.
	_send_voxel_history.rpc_id(peer_id, voxel_changes)


func _spawn_player_local(peer_id: int) -> void:
	if player_scene == null:
		push_error("[GameManager] player_scene is not assigned.")
		return

	var player_name: String = str(peer_id)

	if players.has_node(player_name):
		var existing: CharacterBody3D = (
			players.get_node(player_name) as CharacterBody3D
		)

		if existing != null and existing.is_multiplayer_authority():
			_local_player = existing
		return

	var player: CharacterBody3D = (
		player_scene.instantiate() as CharacterBody3D
	)

	if player == null:
		push_error(
			"[GameManager] player_scene is not a CharacterBody3D scene."
		)
		return

	player.name = player_name
	player.set_multiplayer_authority(peer_id)
	players.add_child(player)
	player.global_position = get_safe_spawn_position()

	if player.is_multiplayer_authority():
		_local_player = player
		_load_local_player_state(player)

		var inventory: Inventory = (
			player.get_node_or_null("Inventory") as Inventory
		)

		if inventory != null:
			if not inventory.changed.is_connected(_on_local_inventory_changed):
				inventory.changed.connect(_on_local_inventory_changed)

	GameAPI.events.emit(GameEvents.PLAYER_SPAWNED, {
		"player": player,
		"peer_id": peer_id,
	})


@rpc("authority", "call_remote", "reliable")
func _spawn_player_remote(peer_id: int) -> void:
	_spawn_player_local(peer_id)


func get_safe_spawn_position() -> Vector3:
	var x: int = int(round(spawn_point.global_position.x))
	var z: int = int(round(spawn_point.global_position.z))
	var seed: int = 1337

	if GameAPI.world_generation != null:
		seed = GameAPI.world_generation.world_seed

	var height_noise: WorldNoise = WorldNoise.new(seed)
	var surface_y: int = (
		int(height_noise.terrain.get_noise_2d(x, z) * 24.0) + 32
	)

	return Vector3(
		x + 0.5,
		surface_y + spawn_height_above_ground,
		z + 0.5
	)


func _get_content_signature() -> String:
	return (
		NetworkManager.protocol_version
		+ "|"
		+ GameAPI.mods.get_signature()
		+ "|"
		+ GameAPI.content.get_content_signature()
	)


# ------------------------------------------------------------------
# Voxel edits
# ------------------------------------------------------------------

func submit_block_break(pos: Vector3i) -> Dictionary:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return _server_break(multiplayer.get_unique_id(), pos)

	var request_id: int = _allocate_request_id()

	_request_block_edit.rpc_id(
		1,
		request_id,
		"break",
		pos,
		""
	)

	return {
		"success": false,
		"pending": true,
		"request_id": request_id,
	}


func submit_block_place(pos: Vector3i, item_id: String) -> Dictionary:
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return _server_place(
			multiplayer.get_unique_id(),
			pos,
			item_id
		)

	var request_id: int = _allocate_request_id()

	_request_block_edit.rpc_id(
		1,
		request_id,
		"place",
		pos,
		item_id
	)

	return {
		"success": false,
		"pending": true,
		"request_id": request_id,
	}


func _allocate_request_id() -> int:
	var result: int = _next_request_id
	_next_request_id += 1

	if _next_request_id > 2147483000:
		_next_request_id = 1

	return result


@rpc("any_peer", "reliable")
func _request_block_edit(
	request_id: int,
	action: String,
	pos: Vector3i,
	item_id: String
) -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()
	var result: Dictionary = {
		"success": false,
		"reason": "unknown_action",
	}

	if action == "break":
		result = _server_break(peer_id, pos)
	elif action == "place":
		result = _server_place(peer_id, pos, item_id)

	_send_edit_result.rpc_id(
		peer_id,
		request_id,
		action,
		result
	)


@rpc("authority", "reliable")
func _send_edit_result(
	request_id: int,
	action: String,
	result: Dictionary
) -> void:
	edit_result.emit(request_id, action, result)


func _server_break(peer_id: int, pos: Vector3i) -> Dictionary:
	var player: CharacterBody3D = (
		players.get_node_or_null(str(peer_id)) as CharacterBody3D
	)

	if player == null:
		return {
			"success": false,
			"reason": "player_missing",
		}

	if not _within_edit_distance(player, pos):
		return {
			"success": false,
			"reason": "too_far",
		}

	var result: Dictionary = GameAPI.edits.break_block(
		player,
		pos
	)

	if not bool(result.get("success", false)):
		return result

	_record_voxel_change(
		pos,
		ContentRegistry.AIR_ID
	)

	_broadcast_block_change(
		pos,
		ContentRegistry.AIR_ID
	)

	return result


func _server_place(
	peer_id: int,
	pos: Vector3i,
	item_id: String
) -> Dictionary:
	var player: CharacterBody3D = (
		players.get_node_or_null(str(peer_id)) as CharacterBody3D
	)

	if player == null:
		return {
			"success": false,
			"reason": "player_missing",
		}

	if not GameAPI.content.has_item(item_id):
		return {
			"success": false,
			"reason": "unknown_item",
		}

	if not _within_edit_distance(player, pos):
		return {
			"success": false,
			"reason": "too_far",
		}

	if not can_place_block(pos, player):
		return {
			"success": false,
			"reason": "inside_player",
		}

	var result: Dictionary = GameAPI.edits.place_block(
		player,
		pos,
		item_id
	)

	if not bool(result.get("success", false)):
		return result

	var placed_block_id: String = str(result.get("block_id", ""))

	_record_voxel_change(
		pos,
		placed_block_id
	)

	_broadcast_block_change(
		pos,
		placed_block_id
	)

	return result


func _record_voxel_change(
	pos: Vector3i,
	block_id: String
) -> void:
	var key: String = _voxel_key(pos)

	if voxel_changes.has(key):
		_voxel_change_order.erase(key)

	_voxel_change_order.append(key)
	voxel_changes[key] = block_id

	while _voxel_change_order.size() > MAX_VOXEL_HISTORY:
		var old_value: Variant = _voxel_change_order.pop_front()
		var old_key: String = str(old_value)
		voxel_changes.erase(old_key)


func _broadcast_block_change(
	pos: Vector3i,
	block_id: String
) -> void:
	if (
		multiplayer.has_multiplayer_peer()
		and multiplayer.is_server()
	):
		_apply_voxel_change.rpc(pos, block_id)
	else:
		_apply_voxel_change(pos, block_id)


@rpc("authority", "call_local", "reliable")
func _apply_voxel_change(
	pos: Vector3i,
	block_id: String
) -> void:
	if GameAPI.world != null:
		GameAPI.world.set_block(pos, block_id)


@rpc("authority", "reliable")
func _send_voxel_history(changes: Dictionary) -> void:
	if GameAPI.world == null:
		return

	for key: String in changes:
		var pos: Vector3i = _voxel_from_key(key)
		var block_id: String = str(changes[key])
		GameAPI.world.set_block(pos, block_id)


func _voxel_key(pos: Vector3i) -> String:
	return "%d,%d,%d" % [
		pos.x,
		pos.y,
		pos.z,
	]


func _voxel_from_key(key: String) -> Vector3i:
	var parts: PackedStringArray = key.split(",")

	if parts.size() != 3:
		return Vector3i.ZERO

	return Vector3i(
		int(parts[0]),
		int(parts[1]),
		int(parts[2])
	)


# ------------------------------------------------------------------
# Player movement synchronization
# ------------------------------------------------------------------

func submit_player_sync(
	peer_id: int,
	position: Vector3,
	rotation_y: float,
	camera_rotation_x: float,
	held_item_id: String = "",
	state: Dictionary = {}
) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		_broadcast_player_sync(peer_id, position, rotation_y, camera_rotation_x, held_item_id, SYNC_STATE.sanitize(state))
	else:
		_request_player_sync.rpc_id(1, position, rotation_y, camera_rotation_x, held_item_id, state)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _request_player_sync(
	position: Vector3,
	rotation_y: float,
	camera_rotation_x: float,
	held_item_id: String,
	state: Dictionary
) -> void:
	if not multiplayer.is_server():
		return
	# Identity comes only from the authenticated RPC sender.
	var peer_id: int = multiplayer.get_remote_sender_id()
	if not spawned_peer_ids.has(peer_id):
		return
	if not position.is_finite() or not is_finite(rotation_y) or not is_finite(camera_rotation_x):
		return
	var clean: Dictionary = SYNC_STATE.sanitize(state)
	if clean.is_empty():
		return
	if not held_item_id.is_empty() and not GameAPI.content.has_item(held_item_id):
		held_item_id = ""
	_broadcast_player_sync(peer_id, position, wrapf(rotation_y, -PI, PI), clampf(camera_rotation_x, -PI * 0.5, PI * 0.5), held_item_id, clean)


func _broadcast_player_sync(
	peer_id: int,
	position: Vector3,
	rotation_y: float,
	camera_rotation_x: float,
	held_item_id: String,
	state: Dictionary
) -> void:
	_receive_player_sync.rpc(peer_id, position, rotation_y, camera_rotation_x, held_item_id, state)


@rpc("authority", "unreliable_ordered", "call_local", 1)
func _receive_player_sync(
	peer_id: int,
	position: Vector3,
	rotation_y: float,
	camera_rotation_x: float,
	held_item_id: String,
	state: Dictionary
) -> void:
	var player: PlayerController = players.get_node_or_null(str(peer_id)) as PlayerController
	if player != null and not player.is_multiplayer_authority():
		player.apply_remote_sync(position, rotation_y, camera_rotation_x, held_item_id, state)

func _within_edit_distance(
	player: Node3D,
	pos: Vector3i
) -> bool:
	var center: Vector3 = Vector3(pos) + Vector3.ONE * 0.5
	return player.global_position.distance_to(center) <= 10.0


func can_place_block(
	block_pos: Vector3i,
	ignored_player: Node = null
) -> bool:
	if GameAPI.world == null:
		return false

	var block: Dictionary = GameAPI.content.get_block(
		GameAPI.world.get_block_id(block_pos)
	)

	if (
		not block.is_empty()
		and bool(block.get("solid", false))
	):
		return false

	for child: Node in players.get_children():
		if child == ignored_player:
			continue

		if not child is CharacterBody3D:
			continue

		var character: CharacterBody3D = child as CharacterBody3D

		if _block_overlaps_player(block_pos, character):
			return false

	return true


func _block_overlaps_player(
	block_pos: Vector3i,
	player: CharacterBody3D
) -> bool:
	var center: Vector3 = Vector3(block_pos) + Vector3.ONE * 0.5
	var feet: Vector3 = player.global_position
	var head: Vector3 = feet + Vector3.UP * 1.8

	var horizontal: float = Vector2(
		center.x - feet.x,
		center.z - feet.z
	).length()

	return (
		horizontal < 0.85
		and center.y > feet.y - 0.2
		and center.y < head.y + 0.2
	)


# ------------------------------------------------------------------
# Local player persistence
# ------------------------------------------------------------------

func _on_local_inventory_changed() -> void:
	_inventory_dirty = true
	_inventory_save_timer = 0.0


func _load_local_player_state(player: CharacterBody3D) -> void:
	if not player.is_multiplayer_authority():
		return

	var inventory: Inventory = (
		player.get_node_or_null("Inventory") as Inventory
	)

	if inventory == null:
		return

	if _state_load_path.is_empty() or not FileAccess.file_exists(_state_load_path):
		return

	var file: FileAccess = FileAccess.open(
		_state_load_path,
		FileAccess.READ
	)

	if file == null:
		return

	var parsed: Variant = JSON.parse_string(
		file.get_as_text()
	)

	if parsed is Dictionary:
		inventory.load_snapshot(parsed)


func _save_local_player_state() -> void:
	if (
		_local_player == null
		or not is_instance_valid(_local_player)
	):
		return

	var inventory: Inventory = (
		_local_player.get_node_or_null("Inventory") as Inventory
	)

	if inventory == null:
		return

	if _state_path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_state_path.get_base_dir())
	var file: FileAccess = FileAccess.open(
		_state_path,
		FileAccess.WRITE
	)

	if file == null:
		push_warning(
			"[GameManager] Could not save local player state."
		)
		return

	file.store_string(
		JSON.stringify(
			inventory.get_snapshot(),
			"\t"
		)
	)
