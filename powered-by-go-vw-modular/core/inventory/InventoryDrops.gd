extends Node3D

## Single-player world drop bridge. Inventory authority must be unified before
## shared pickups can safely consume remote players' inventories.
var records: Dictionary = {}
var visuals: Dictionary = {}
var save_path := ""
var elapsed := 0.0
var pickup_timer := 0.0
var dirty := false

func _ready() -> void:
	var config := GameAPI.saves.selected_config()
	if not config.is_empty():
		save_path = GameAPI.saves.root_path.path_join(str(config.save_name) + ".drops.json")
		_load_drops()

func _exit_tree() -> void:
	if dirty:
		_save_drops()

func drop_stack(inventory: Inventory, held: bool, index: int, amount: int) -> Dictionary:
	if inventory == null or save_path.is_empty():
		return {"success": false, "reason": "No active saved world."}
	var player := inventory.get_parent() as CharacterBody3D
	if player == null or not player.is_multiplayer_authority():
		return {"success": false, "reason": "Player unavailable."}
	var source: SlotContainer = inventory.cursor if held else inventory.container
	var stack := source.stack_at(index)
	if stack.is_empty() or amount <= 0:
		return {"success": false, "reason": "Empty slot."}
	if records.size() >= 512:
		return {"success": false, "reason": "Collect some nearby items before dropping more."}
	var position := player.global_position + Vector3.UP * 0.8
	var forward := -player.global_transform.basis.z
	var obstruction = GameAPI.world.raycast(position, forward, 1.8)
	position += forward * (0.3 if obstruction else 1.8)
	var ground = GameAPI.world.raycast(position + Vector3.UP, Vector3.DOWN, 8.0)
	if ground:
		position.y = float(ground.position.y) + 1.22
	stack["count"] = mini(int(stack.count), amount)
	var id := "%s_%s" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	var record := {"stack": stack, "position": [position.x, position.y, position.z], "available": elapsed + 1.25}
	# Save the accepted world record before consuming the source stack.
	records[id] = record
	if not _save_drops():
		records.erase(id)
		return {"success": false, "reason": "Could not save the dropped item; inventory unchanged."}
	source.take(index, int(stack.count))
	_make_visual(id)
	if get_parent().has_method("_save_local_player_state"):
		get_parent().call("_save_local_player_state")
	return {"success": true}

func pickup_nearest(player: CharacterBody3D, radius: float = 1.75) -> Dictionary:
	if player == null or not player.is_multiplayer_authority():
		return {"success": false, "reason": "Player unavailable."}
	var inventory := player.get_node_or_null("Inventory") as Inventory
	if inventory == null:
		return {"success": false, "reason": "Inventory unavailable."}
	var nearest_id := ""
	var nearest_distance := radius
	for id in records.keys():
		if not visuals.has(id):
			continue
		var record: Dictionary = records[id]
		if elapsed < float(record.get("available", 0)):
			continue
		var position: Array = record.get("position", [])
		if position.size() != 3:
			continue
		var distance := player.global_position.distance_to(Vector3(float(position[0]), float(position[1]), float(position[2])))
		if distance < nearest_distance:
			nearest_id = str(id)
			nearest_distance = distance
	if nearest_id.is_empty():
		return {"success": false, "reason": "No dropped item nearby."}
	var record: Dictionary = records[nearest_id]
	var result := inventory.add_stack(record.stack)
	if int(result.added) == 0:
		return {"success": false, "reason": "Inventory is full."}
	if result.remainder.is_empty():
		records.erase(nearest_id)
		var node: Node3D = visuals[nearest_id]
		visuals.erase(nearest_id)
		node.queue_free()
	else:
		record.stack = result.remainder
		records[nearest_id] = record
	dirty = true
	_save_drops()
	if get_parent().has_method("_save_local_player_state"):
		get_parent().call("_save_local_player_state")
	return {"success": true, "added": int(result.added)}

func _make_visual(id: String) -> void:
	if visuals.has(id):
		return
	var record: Dictionary = records[id]
	var stack: Dictionary = record.stack
	var node := Node3D.new()
	add_child(node)
	var p: Array = record.position
	node.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var definition := GameAPI.content.get_item(str(stack.get("id", "")))
	var block := str(definition.get("place_block", ""))
	if not block.is_empty():
		var mesh := MeshInstance3D.new()
		mesh.mesh = GameAPI.world.get_block_display_mesh(block)
		mesh.scale = Vector3.ONE * 0.22
		mesh.position = Vector3.ONE * -0.11
		node.add_child(mesh)
	else:
		var path := str(definition.get("icon", ""))
		if not path.is_empty() and ResourceLoader.exists(path):
			var sprite := Sprite3D.new()
			sprite.texture = load(path) as Texture2D
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sprite.pixel_size = 0.3 / maxf(sprite.texture.get_width(), sprite.texture.get_height())
			node.add_child(sprite)
		else:
			var mesh := MeshInstance3D.new()
			var cube := BoxMesh.new()
			cube.size = Vector3.ONE * 0.2
			mesh.mesh = cube
			node.add_child(mesh)
	var label := Label3D.new()
	label.text = str(stack.get("count", 1))
	label.position.y = 0.25
	label.pixel_size = 0.003
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.add_child(label)
	visuals[id] = node

func _process(delta: float) -> void:
	elapsed += delta
	pickup_timer += delta
	for id in visuals:
		var node: Node3D = visuals[id]
		node.rotation.y += delta
		var p: Array = records[id].position
		node.position.y = float(p[1]) + sin(elapsed * 2.5) * 0.035
	if pickup_timer < 0.2:
		return
	pickup_timer = 0.0
	for player in get_tree().get_nodes_in_group("player_character"):
		if not player.is_multiplayer_authority():
			continue
		var inv := player.get_node_or_null("Inventory") as Inventory
		if inv == null:
			continue
		for id in records.keys():
			var record: Dictionary = records[id]
			if elapsed < float(record.get("available", 0)) or not visuals.has(id):
				continue
			var node: Node3D = visuals[id]
			if node.global_position.distance_to(player.global_position + Vector3.UP * 0.6) > 1.25:
				continue
			if not GameAPI.content.has_item(str(record.stack.get("id", ""))):
				continue
			var result := inv.add_stack(record.stack)
			if int(result.added) == 0:
				continue
			if result.remainder.is_empty():
				records.erase(id)
				visuals.erase(id)
				node.queue_free()
			else:
				record.stack = result.remainder
				for child in node.get_children():
					if child is Label3D:
						child.text = str(record.stack.count)
			dirty = true
	if dirty:
		_save_drops()
		if get_parent().has_method("_save_local_player_state"):
			get_parent().call("_save_local_player_state")

func _save_drops() -> bool:
	if save_path.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 1, "drops": records}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	if FileAccess.file_exists(save_path) and DirAccess.copy_absolute(save_path, save_path + ".bak") != OK:
		return false
	if DirAccess.rename_absolute(save_path + ".tmp", save_path) != OK:
		return false
	dirty = false
	return true

func _load_drops() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary or int(data.get("version", 0)) != 1 or not data.get("drops", {}) is Dictionary:
		# Do not overwrite an unreadable drop save.
		save_path = ""
		return
	for id in data.drops:
		var record: Variant = data.drops[id]
		if not record is Dictionary or not record.get("stack", {}) is Dictionary or not record.get("position", []) is Array or record.position.size() != 3:
			continue
		record.available = 1.25
		records[str(id)] = record
		_make_visual(str(id))

func _networked() -> bool:
	return multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer
