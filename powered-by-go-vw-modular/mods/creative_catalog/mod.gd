extends GameMod

var _api: ModAPI
var _runtime_script: Script
var _runtime: Node


func register(api: ModAPI) -> void:
	_api = api
	_runtime_script = api.load_asset("CreativeCatalog.gd")
	api.on(GameEvents.WORLD_READY, _world_ready, -100)
	api.on(GameEvents.WORLD_STOPPING, _world_stopping, 200)
	if not InputMap.has_action("creative_catalog"):
		InputMap.add_action("creative_catalog")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F6
		InputMap.action_add_event("creative_catalog", key)


func _world_ready(event: Dictionary) -> Dictionary:
	var world := event.get("world") as Node
	if world == null or _runtime_script == null:
		return event
	_runtime = _runtime_script.new()
	_runtime.name = "CreativeCatalog"
	world.add_child(_runtime)
	_runtime.call("setup", _api)
	return event


func _world_stopping(event: Dictionary) -> Dictionary:
	if is_instance_valid(_runtime):
		_runtime.queue_free()
	_runtime = null
	return event


func _exit_tree() -> void:
	if _api != null:
		_api.off(GameEvents.WORLD_READY, _world_ready)
		_api.off(GameEvents.WORLD_STOPPING, _world_stopping)
