class_name EnergyService
extends RefCounted

const MAX_NETWORK_CELLS := 512
const DEFAULT_REBUILD_SLICE := 64
const DIRECTIONS: Array[Vector3i] = [
	Vector3i.RIGHT,
	Vector3i.LEFT,
	Vector3i.UP,
	Vector3i.DOWN,
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]
const OPPOSITE_FACE := [1, 0, 3, 2, 5, 4]

var content: ContentRegistry
var stations: BlockEntityService
var world: VoxelWorldService
var definitions: Dictionary = {}
var _membership: Dictionary = {}
var _networks: Dictionary = {}
var _jobs: Dictionary = {}


func _init(p_content: ContentRegistry, p_stations: BlockEntityService, p_world: VoxelWorldService) -> void:
	content = p_content
	stations = p_stations
	world = p_world


func register(definition: Dictionary) -> bool:
	var block_id := str(definition.get("block_id", ""))
	var role := str(definition.get("role", ""))
	var capacity: Variant = definition.get("capacity", 0)
	var transfer_limit: Variant = definition.get("transfer_limit", 0)
	var faces: Variant = definition.get("faces", [0, 1, 2, 3, 4, 5])
	if block_id.is_empty() or not content.has_block(block_id) or definitions.has(block_id):
		return false
	if role not in ["cable", "producer", "storage", "consumer"]:
		return false
	if not _integer_in_range(capacity, 0, 2147483647) or not _integer_in_range(transfer_limit, 1, 2147483647):
		return false
	if role != "cable" and int(capacity) <= 0:
		return false
	if not faces is Array or faces.is_empty():
		return false
	var normalized_faces: Array[int] = []
	for face in faces:
		if not _integer_in_range(face, 0, 5) or int(face) in normalized_faces:
			return false
		normalized_faces.append(int(face))
	normalized_faces.sort()
	var normalized := {
		"block_id": block_id,
		"role": role,
		"capacity": int(capacity),
		"transfer_limit": int(transfer_limit),
		"faces": normalized_faces,
	}
	definitions[block_id] = normalized
	if not stations.kinds.has(block_id):
		stations.register_kind(block_id, ["energy", role], {})
	_mark_dirty()
	return true


func definition(block_id: String) -> Dictionary:
	return definitions.get(block_id, {}).duplicate(true)


func ids() -> Array[String]:
	var result: Array[String] = []
	for block_id in definitions:
		result.append(str(block_id))
	result.sort()
	return result


func stored(cell: Variant) -> int:
	var record := _record_for(cell)
	if record.is_empty():
		return 0
	return clampi(int(record.get("state", {}).get("energy", {}).get("stored", 0)), 0, int(definition(str(record.block_id)).get("capacity", 0)))


func deposit(cell: Variant, amount: int) -> int:
	if amount <= 0:
		return 0
	var record := _record_for(cell)
	if record.is_empty():
		return 0
	var defn := definition(str(record.block_id))
	if defn.is_empty() or str(defn.role) == "cable":
		return 0
	var energy: Dictionary = record.get("state", {}).get("energy", {}).duplicate(true)
	var before := clampi(int(energy.get("stored", 0)), 0, int(defn.capacity))
	var accepted := mini(amount, int(defn.capacity) - before)
	if accepted <= 0:
		return 0
	energy["stored"] = before + accepted
	if not _commit_energy(str(record._station_id), record.state, energy):
		return 0
	return accepted


func consume(cell: Variant, amount: int) -> bool:
	if amount <= 0:
		return false
	var record := _record_for(cell)
	if record.is_empty():
		return false
	var defn := definition(str(record.block_id))
	if defn.is_empty() or str(defn.role) == "cable":
		return false
	var energy: Dictionary = record.get("state", {}).get("energy", {}).duplicate(true)
	var before := clampi(int(energy.get("stored", 0)), 0, int(defn.capacity))
	if before < amount:
		return false
	energy["stored"] = before - amount
	return _commit_energy(str(record._station_id), record.state, energy)


func network_for(cell: Variant) -> Dictionary:
	var position := _to_position(cell)
	if not world.is_ready() or not world.is_loaded(position):
		return {"status": "unloaded", "cells": [], "complete": false, "reason": "unloaded"}
	var origin_block := world.get_block_id(position)
	if not definitions.has(origin_block):
		return {"status": "disconnected", "cells": [], "complete": true, "reason": "unknown_port"}
	var origin := stations.ensure(position)
	if origin.is_empty():
		return {"status": "unavailable", "cells": [], "complete": false, "reason": "station_unavailable"}
	if _membership.has(origin):
		return _networks.get(str(_membership[origin]), {}).duplicate(true)
	if not _jobs.has(origin):
		_start_job(origin, position)
	return {"status": "rebuilding", "cells": [], "complete": false, "reason": "graph_rebuild_pending"}


func advance_rebuilds(budget: int = DEFAULT_REBUILD_SLICE) -> int:
	if budget <= 0 or _jobs.is_empty():
		return 0
	var keys: Array = _jobs.keys()
	keys.sort()
	var seed: String = str(keys[0])
	var job: Dictionary = _jobs[seed]
	var steps := mini(budget, job.queue.size())
	for _i in range(steps):
		var current_key: String = str(job.queue.pop_front())
		var pos: Vector3i = job.positions[current_key]
		job.cells.append(current_key)
		if job.cells.size() > MAX_NETWORK_CELLS:
			job.truncated = true
			break
		var current_def: Dictionary = definitions.get(str(job.block_ids[current_key]), {})
		for face in current_def.get("faces", []):
			var neighbor_pos: Vector3i = pos + DIRECTIONS[int(face)]
			if not world.is_loaded(neighbor_pos):
				job.unloaded = true
				continue
			var neighbor_block := world.get_block_id(neighbor_pos)
			if not definitions.has(neighbor_block):
				continue
			var neighbor_def: Dictionary = definitions[neighbor_block]
			var opposite: int = OPPOSITE_FACE[int(face)]
			if opposite not in neighbor_def.faces:
				continue
			if str(current_def.role) != "cable" and str(neighbor_def.role) != "cable":
				continue
			var neighbor_key := stations.key(neighbor_pos)
			if job.visited.has(neighbor_key):
				continue
			if job.visited.size() >= MAX_NETWORK_CELLS:
				job.truncated = true
				break
			job.visited[neighbor_key] = true
			job.positions[neighbor_key] = neighbor_pos
			job.block_ids[neighbor_key] = neighbor_block
			var station_id := stations.ensure(neighbor_pos)
			if station_id.is_empty():
				job.unloaded = true
				continue
			job.queue.append(neighbor_key)
	_jobs[seed] = job
	if job.truncated or job.queue.is_empty():
		_finish_job(seed)
	return steps


func mark_dirty() -> void:
	_mark_dirty()


## Call after terrain/region loading changes when the world adapter provides such a notification.
func notify_loaded_state_changed() -> void:
	_mark_dirty()


func reset() -> void:
	_membership.clear()
	_networks.clear()
	_jobs.clear()


func _start_job(seed: String, position: Vector3i) -> void:
	var block_id := world.get_block_id(position)
	_jobs[seed] = {
		"queue": [seed],
		"visited": {seed: true},
		"positions": {seed: position},
		"block_ids": {seed: block_id},
		"cells": [],
		"unloaded": false,
		"truncated": false,
	}


func _finish_job(seed: String) -> void:
	var job: Dictionary = _jobs.get(seed, {})
	if job.is_empty():
		return
	var cells: Array = job.cells.duplicate()
	cells.sort()
	var network_id: String = str(cells[0]) if not cells.is_empty() else seed
	var complete := not bool(job.unloaded) and not bool(job.truncated)
	var reason := "" if complete else ("cell_limit" if job.truncated else "unloaded")
	var devices: Array[String] = []
	for cell_key in cells:
		var role := str(definitions.get(str(job.block_ids[cell_key]), {}).get("role", ""))
		if role != "cable":
			devices.append(str(cell_key))
		_membership[str(cell_key)] = network_id
	var status := "ready" if complete else "incomplete"
	if complete and cells.size() == 1:
		status = "disconnected"
		reason = "no_cable_connection"
	var result := {
		"id": network_id,
		"status": status,
		"cells": cells,
		"devices": devices,
		"complete": complete,
		"size": cells.size(),
		"unloaded": bool(job.unloaded),
		"reason": reason,
	}
	_networks[network_id] = result
	# Map all traversed entries, including the cell that exceeded the cap.
	for cell_key in job.visited:
		_membership[str(cell_key)] = network_id
	_jobs.erase(seed)


func _record_for(cell: Variant) -> Dictionary:
	var position := _to_position(cell)
	if not world.is_loaded(position):
		return {}
	var block_id := world.get_block_id(position)
	var defn := definition(block_id)
	if defn.is_empty():
		return {}
	var id := stations.ensure(position)
	if id.is_empty():
		return {}
	var record := stations.record(id)
	record["_station_id"] = id
	return record


func _commit_energy(id: String, state: Dictionary, energy: Dictionary) -> bool:
	var merged := state.duplicate(true)
	merged["energy"] = energy.duplicate(true)
	var before := state.duplicate(true)
	stations.update_state(id, merged)
	if stations.save():
		return true
	stations.update_state(id, before)
	stations.mark_dirty()
	return false


func _to_position(cell: Variant) -> Vector3i:
	if cell is Vector3i:
		return cell
	if cell is String:
		var parts := str(cell).split(",", false)
		if parts.size() == 3:
			return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
	return Vector3i.ZERO


func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value) and int(value) >= minimum and int(value) <= maximum


func _mark_dirty() -> void:
	_membership.clear()
	_networks.clear()
	_jobs.clear()
