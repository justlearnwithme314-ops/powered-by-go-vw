extends GameMod

const CABLE_ID := "industry:cable"
var _api: ModAPI
var _runtime_script: Script
var _runtime: Node


func register(api: ModAPI) -> void:
	_api = api
	_runtime_script = api.load_asset("EnergyRuntime.gd") as Script
	var cable_model := VoxelBlockyModelCube.new()
	var cable_material := StandardMaterial3D.new()
	cable_material.albedo_color = Color(0.72, 0.36, 0.16)
	cable_material.roughness = 1.0
	cable_model.set_material_override(0, cable_material)
	api.register_block({
		"id": CABLE_ID,
		"display_name": "Copper Cable",
		"model": cable_model,
		"hardness": 1.2,
		"preferred_tool": "pickaxe",
		"tags": ["block", "energy", "cable"],
	})
	api.register_recipe("industry:cable", CABLE_ID, 4, {"frontier:copper_ingot": 1, "core:stick": 1}, {"station": "workbench"})
	api.energy.register({
		"block_id": CABLE_ID,
		"role": "cable",
		"capacity": 0,
		"transfer_limit": 100,
		"faces": [0, 1, 2, 3, 4, 5],
	})
	api.on(GameEvents.WORLD_READY, _world_ready, -50)
	api.on(GameEvents.WORLD_STOPPING, _world_stopping, 100)
	api.on(GameEvents.AFTER_BLOCK_PLACE, _placed)
	api.on(GameEvents.AFTER_BLOCK_BREAK, _broken)


func _world_ready(event: Dictionary) -> Dictionary:
	var world_node := event.get("world") as Node
	if world_node == null:
		return event
	var peer := world_node.multiplayer.multiplayer_peer
	if peer != null and not peer is OfflineMultiplayerPeer and not world_node.multiplayer.is_server():
		return event
	_api.energy.notify_loaded_state_changed()
	_runtime = _runtime_script.new() as Node
	_runtime.name = "EnergyRuntime"
	world_node.add_child(_runtime)
	_runtime.call("setup", _api)
	return event


func _world_stopping(event: Dictionary) -> Dictionary:
	if is_instance_valid(_runtime):
		_runtime.queue_free()
	_runtime = null
	_api.energy.reset()
	return event


func _placed(event: Dictionary) -> Dictionary:
	var block_id := str(event.get("block_id", ""))
	if _api.energy.definitions.has(block_id):
		var pos: Variant = event.get("position")
		if pos is Vector3i:
			_api.stations.ensure(pos)
	if _api.energy.definitions.has(block_id):
		_api.energy.mark_dirty()
	return event


func _broken(event: Dictionary) -> Dictionary:
	var block_id := str(event.get("block_id", ""))
	if _api.energy.definitions.has(block_id):
		var pos: Variant = event.get("position")
		if pos is Vector3i:
			_api.stations.remove(_api.stations.key(pos))
		_api.energy.mark_dirty()
	return event
