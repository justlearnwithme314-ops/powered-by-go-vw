class_name BlockEntityService
extends RefCounted

## World-scoped station storage, independent of chunk meshes and open panels.
signal changed
var content: ContentRegistry
var world: VoxelWorldService
var kinds: Dictionary = {}
var _records: Dictionary = {}
var _containers: Dictionary = {}
var _unknown: Array = []
var _saved_inventory: Dictionary = {}
var inventory: Inventory
var path := ""
var writable := true
var dirty := false
var revision := 0
var _player_data: Dictionary = {}

func _init(registry: ContentRegistry, world_service: VoxelWorldService) -> void:
	content = registry
	world = world_service

func register_kind(block_id: String, capabilities: Array, slots: Dictionary) -> void:
	kinds[block_id] = {"capabilities": capabilities.duplicate(), "slots": slots.duplicate()}

func key(position: Vector3i) -> String:
	return "%d,%d,%d" % [position.x, position.y, position.z]

func activate(save_path: String) -> bool:
	if is_instance_valid(inventory) and inventory.changed.is_connected(mark_dirty):
		inventory.changed.disconnect(mark_dirty)
	path = save_path
	_records.clear()
	_containers.clear()
	_unknown.clear()
	_saved_inventory.clear()
	_player_data.clear()
	inventory = null
	writable = true
	dirty = false
	if path.is_empty() or not FileAccess.file_exists(path):
		return true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1 or not parsed.get("entities", []) is Array or not parsed.get("inventory", {}) is Dictionary:
		writable = false
		push_error("[BlockEntities] Invalid/newer station save; original preserved: " + path)
		return false
	_saved_inventory = parsed.get("inventory", {}).duplicate(true)
	if not parsed.get("player_data", {}) is Dictionary:
		writable = false
		return false
	_player_data = parsed.get("player_data", {}).duplicate(true)
	if int(_saved_inventory.get("version", 1)) > 2 or (not _saved_inventory.is_empty() and int(_saved_inventory.get("version", 1)) == 2 and not _saved_inventory.get("slots", null) is Array):
		writable = false
		return false
	for value in parsed.get("entities", []):
		if not value is Dictionary or not kinds.has(str(value.get("block_id", ""))) or not value.get("position", []) is Array or value.position.size() != 3:
			_unknown.append(value)
			continue
		var pos := Vector3i(int(value.position[0]), int(value.position[1]), int(value.position[2]))
		if not value.get("state", {}) is Dictionary or not value.get("containers", {}) is Dictionary or not value.get("recovery", []) is Array:
			writable = false
			return false
		for name in value.get("containers", {}):
			if not value.containers[name] is Array:
				writable = false
				return false
		var id := key(pos)
		if _records.has(id):
			writable = false
			return false
		_create(pos, str(value.block_id), value)
	dirty = false
	return true

func bind_inventory(value: Inventory) -> void:
	if is_instance_valid(inventory) and inventory != value and inventory.changed.is_connected(mark_dirty):
		inventory.changed.disconnect(mark_dirty)
	inventory = value
	if not _saved_inventory.is_empty():
		inventory.load_snapshot(_saved_inventory)
		_saved_inventory.clear()
	if not inventory.changed.is_connected(mark_dirty):
		inventory.changed.connect(mark_dirty)

func has_saved_inventory() -> bool:
	return not _saved_inventory.is_empty()

func _create(pos: Vector3i, block_id: String, saved: Dictionary = {}) -> String:
	var id := key(pos)
	var record := saved.duplicate(true)
	record.merge({"position": [pos.x, pos.y, pos.z], "block_id": block_id, "state": saved.get("state", {}).duplicate(true), "recovery": saved.get("recovery", []).duplicate(true)}, true)
	var containers := {}
	for name in kinds[block_id].slots:
		var container := SlotContainer.new(content, int(kinds[block_id].slots[name]))
		var overflow := container.restore(saved.get("containers", {}).get(name, []))
		record.recovery.append_array(overflow)
		container.changed.connect(mark_dirty)
		containers[name] = container
	for name in saved.get("containers", {}):
		if not kinds[block_id].slots.has(name):
			for stack in saved.containers[name]:
				if stack is Dictionary and not stack.is_empty():
					record.recovery.append(stack.duplicate(true))
	_records[id] = record
	_containers[id] = containers
	mark_dirty()
	return id

func ensure(pos: Vector3i) -> String:
	var block_id := world.get_block_id(pos)
	if not kinds.has(block_id) or not writable:
		return ""
	var id := key(pos)
	if _records.has(id):
		return id if str(_records[id].block_id) == block_id else ""
	if _records.size() >= 4096:
		return ""
	return _create(pos, block_id)

func accessible(player: Node3D, id: String) -> bool:
	if player == null or not _records.has(id) or not writable:
		return false
	var values: Array = _records[id].position
	var pos := Vector3i(int(values[0]), int(values[1]), int(values[2]))
	return player.global_position.distance_to(Vector3(pos) + Vector3.ONE * 0.5) <= 6.0 and world.get_block_id(pos) == str(_records[id].block_id)

func capabilities(player: Node3D) -> Array[String]:
	var result: Array[String] = ["hand"]
	if not is_instance_valid(player):
		return result
	# Query actual terrain, including stations placed before records existed.
	var center := player.global_position + Vector3.UP * 0.5
	var cell := Vector3i(center.floor())
	for z in range(-3, 4):
		for x in range(-3, 4):
			for y in range(-3, 4):
				var pos := cell + Vector3i(x, y, z)
				if center.distance_squared_to(Vector3(pos) + Vector3.ONE * 0.5) > 9.0:
					continue
				var block_id := world.get_block_id(pos)
				if not kinds.has(block_id):
					continue
				for capability in kinds[block_id].capabilities:
					if str(capability) not in result:
						result.append(str(capability))
	return result

func ids() -> Array:
	return _records.keys()

func record(id: String) -> Dictionary:
	if not _records.has(id):
		return {}
	var result: Dictionary = _records[id].duplicate(true)
	result["containers"] = {}
	for name in _containers[id]:
		result.containers[name] = _containers[id][name].snapshot()
	return result

func container(id: String, name: String) -> SlotContainer:
	return _containers.get(id, {}).get(name) as SlotContainer

func update_state(id: String, state: Dictionary) -> void:
	if _records.has(id):
		_records[id].state = state.duplicate(true)
		mark_dirty()

func remove(id: String) -> Array[Dictionary]:
	var stacks: Array[Dictionary] = []
	if not _records.has(id):
		return stacks
	for name in _containers[id]:
		for stack in _containers[id][name].snapshot():
			if not stack.is_empty():
				stacks.append(stack)
	for stack in _records[id].recovery:
		if stack is Dictionary:
			stacks.append(stack)
	_records.erase(id)
	_containers.erase(id)
	mark_dirty()
	return stacks

func mark_dirty() -> void:
	dirty = true
	revision += 1
	changed.emit()

func player_data(owner_id: String) -> Dictionary:
	var value: Variant = _player_data.get(owner_id, {})
	return value.duplicate(true) if value is Dictionary else {}

func set_player_data(owner_id: String, data: Dictionary) -> void:
	_player_data[owner_id] = data.duplicate(true)
	mark_dirty()

func save() -> bool:
	if path.is_empty() or not writable:
		return false
	var entities: Array = _unknown.duplicate(true)
	for id in _records:
		entities.append(record(str(id)))
	var snapshot := inventory.get_snapshot() if is_instance_valid(inventory) else _saved_inventory
	var payload := {"version": 1, "entities": entities, "inventory": snapshot, "player_data": _player_data.duplicate(true)}
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	if FileAccess.file_exists(path) and DirAccess.copy_absolute(path, path + ".bak") != OK:
		return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		return false
	dirty = false
	return true
