extends Node

const MAX_CELLS_PER_SYNC := 256
const LEGACY_SUFFIX := ".farming.json"
const EDITS_SUFFIX := ".edits.json"

var api: ModAPI
var changes: Dictionary = {}
var pending: Dictionary = {}
var save_path := ""
var writable := true
var _is_authority := true
var _sync_requested := false


func setup(context: ModAPI) -> void:
	api = context
	_is_authority = authority()
	var world_id := str(api.saves.active_world_id)
	if world_id.is_empty():
		writable = false
		push_error("[TerrainChanges] No active world ID; terrain history is read-only.")
		return
	save_path = api.saves.root_path.path_join(world_id + EDITS_SUFFIX)
	var legacy_path := api.saves.root_path.path_join(world_id + LEGACY_SUFFIX)
	if FileAccess.file_exists(save_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if not _valid_payload(parsed):
			writable = false
			push_error("[TerrainChanges] Invalid edit history; original file preserved: " + save_path)
			return
		changes = _normalize_cells(parsed.cells)
	elif FileAccess.file_exists(legacy_path):
		var legacy: Variant = JSON.parse_string(FileAccess.get_file_as_string(legacy_path))
		if not _valid_payload(legacy):
			writable = false
			push_error("[TerrainChanges] Invalid legacy farming history; original file preserved: " + legacy_path)
			return
		changes = _normalize_cells(legacy.cells)
		if authority():
			save_state()
	api.on(GameEvents.AFTER_BLOCK_BREAK, _broken, -400)
	api.on(GameEvents.AFTER_BLOCK_PLACE, _placed, -400)
	api.on(GameEvents.PLAYER_SPAWNED, _joined, -300)


func authority() -> bool:
	if not is_inside_tree():
		return _is_authority
	var peer := multiplayer.multiplayer_peer
	return peer == null or peer is OfflineMultiplayerPeer or multiplayer.is_server()


func networked() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer


func key(pos: Vector3i) -> String:
	return "%d,%d,%d" % [pos.x, pos.y, pos.z]


func position(id: String) -> Vector3i:
	var parts := id.split(",", false)
	if parts.size() != 3:
		return Vector3i.ZERO
	return Vector3i(parts[0].to_int(), parts[1].to_int(), parts[2].to_int())


func change(pos: Vector3i, block_id: String) -> bool:
	if not authority() or not writable or not api.world.is_loaded(pos):
		return false
	if block_id != ContentRegistry.AIR_ID and not api.content.has_block(block_id):
		return false
	if not api.world.set_block(pos, block_id):
		return false
	changes[key(pos)] = block_id
	if networked():
		apply_cell.rpc(pos, block_id)
	return true


@rpc("authority", "reliable")
func apply_cell(pos: Vector3i, block_id: String) -> void:
	if block_id != ContentRegistry.AIR_ID and not api.content.has_block(block_id):
		return
	var cell_key := key(pos)
	if not api.world.is_loaded(pos) or not api.world.set_block(pos, block_id):
		pending[cell_key] = block_id
	else:
		pending.erase(cell_key)


@rpc("any_peer", "reliable")
func request_sync() -> void:
	if not authority() or not networked():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer > 1 and peer in multiplayer.get_peers():
		_send_sync(peer)


func _send_sync(peer: int) -> void:
	var keys: Array = changes.keys()
	keys.sort()
	var batch: Dictionary = {}
	for cell_key in keys:
		batch[str(cell_key)] = changes[cell_key]
		if batch.size() >= MAX_CELLS_PER_SYNC:
			sync_cells.rpc_id(peer, batch)
			batch = {}
	if not batch.is_empty() or keys.is_empty():
		sync_cells.rpc_id(peer, batch)


@rpc("authority", "reliable")
func sync_cells(cells: Dictionary) -> void:
	for cell_key in cells:
		var id := str(cell_key)
		var block_id := str(cells[cell_key])
		if not _valid_cell_key(id) or (block_id != ContentRegistry.AIR_ID and not api.content.has_block(block_id)):
			continue
		pending[id] = block_id


func _joined(event: Dictionary) -> Dictionary:
	if authority() and networked() and event.get("player") is Node:
		var peer := (event.player as Node).get_multiplayer_authority()
		if peer != 1 and peer in multiplayer.get_peers():
			_send_sync(peer)
	return event


func _process(_delta: float) -> void:
	if api == null:
		return
	if not authority() and not _sync_requested and networked() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_sync_requested = true
		request_sync.rpc_id(1)
	for cell_key in pending.keys():
		var pos := position(str(cell_key))
		var block_id := str(pending[cell_key])
		if api.world.is_loaded(pos) and api.world.set_block(pos, block_id):
			pending.erase(cell_key)


func _broken(event: Dictionary) -> Dictionary:
	if authority():
		var pos: Variant = event.get("position")
		if pos is Vector3i and changes.has(key(pos)):
			changes[key(pos)] = ContentRegistry.AIR_ID
	return event


func _placed(event: Dictionary) -> Dictionary:
	if authority():
		var pos: Variant = event.get("position")
		if pos is Vector3i and changes.has(key(pos)):
			changes[key(pos)] = str(event.get("block_id", ContentRegistry.AIR_ID))
	return event


func save_state() -> bool:
	if not authority() or not writable or save_path.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var temp_path := save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "cells": changes}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	if FileAccess.file_exists(save_path) and DirAccess.copy_absolute(save_path, save_path + ".bak") != OK:
		return false
	if DirAccess.rename_absolute(temp_path, save_path) != OK:
		return false
	return true


func _valid_payload(value: Variant) -> bool:
	if not value is Dictionary or int(value.get("version", 0)) != 1 or not value.get("cells", null) is Dictionary:
		return false
	for cell_key in value.cells:
		if not _valid_cell_key(str(cell_key)) or not value.cells[cell_key] is String:
			return false
	return true


func _normalize_cells(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for cell_key in value:
		result[str(cell_key)] = str(value[cell_key])
	return result


func _valid_cell_key(cell_key: String) -> bool:
	var parts := cell_key.split(",", false)
	if parts.size() != 3:
		return false
	for part in parts:
		if not str(part).is_valid_int():
			return false
	return true


func _exit_tree() -> void:
	if api != null:
		save_state()
		api.off(GameEvents.AFTER_BLOCK_BREAK, _broken)
		api.off(GameEvents.AFTER_BLOCK_PLACE, _placed)
		api.off(GameEvents.PLAYER_SPAWNED, _joined)
