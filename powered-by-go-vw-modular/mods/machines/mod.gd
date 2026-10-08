extends GameMod

const INDUSTRY_FEATURE := "industry:machines"
var _api: ModAPI
var _runtime_script: Script


func register(api: ModAPI) -> void:
	_api = api
	_runtime_script = api.load_asset("MachineRuntime.gd") as Script
	api.on(GameEvents.WORLD_READY, _world_ready, -100)
	api.on(GameEvents.WORLD_STOPPING, _world_stopping, -100)


func _world_ready(event: Dictionary) -> Dictionary:
	var world: Node = event.get("world") as Node
	if world == null or _api.profile == null or not _api.profile.enabled(INDUSTRY_FEATURE):
		return event
	var peer := world.multiplayer.multiplayer_peer
	var networked := peer != null and not peer is OfflineMultiplayerPeer
	if networked and not world.multiplayer.is_server():
		return event
	var runtime := _runtime_script.new() as Node
	runtime.name = "MachineRuntime"
	world.add_child(runtime)
	runtime.call("setup", _api)
	return event


func _world_stopping(event: Dictionary) -> Dictionary:
	if _api != null and is_instance_valid(_api.stations) and _api.stations.dirty:
		_api.stations.save()
	return event
