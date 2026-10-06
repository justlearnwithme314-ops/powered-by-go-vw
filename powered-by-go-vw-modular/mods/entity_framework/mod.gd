extends GameMod

var _api: ModAPI
var _runtime: Script

func register(api: ModAPI) -> void:
	_api = api
	_runtime = api.load_asset("EntityRuntime.gd")
	api.on(GameEvents.WORLD_READY, _ready_world, -100)
	api.on(GameEvents.WORLD_STOPPING, _stopping, 200)
	api.on(GameEvents.PRIMARY_ACTION, _primary, 300)
	api.on(GameEvents.ITEM_USE, _used, 300)

func _ready_world(event: Dictionary) -> Dictionary:
	var world := event.get("world") as Node
	var node := _runtime.new() as Node3D
	node.name = "Entities"
	world.add_child(node)
	_api.entities.runtime = node
	node.call("setup", _api)
	return event

func _used(event: Dictionary) -> Dictionary:
	if bool(event.get("handled", false)) or not is_instance_valid(_api.entities.runtime):
		return event
	var player := event.get("player") as PlayerController
	if player == null:
		return event
	var camera := player.get_node("Camera3D") as Camera3D
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 3)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var entity := hit.get("collider") as Node
	if entity != null and entity.has_meta("entity_id") and bool(entity.definition.get("interactive", false)):
		event.handled = true
		_api.entities.runtime.call("submit_interaction", player, str(entity.get_meta("entity_id")))
	return event

func _stopping(event: Dictionary) -> Dictionary:
	if is_instance_valid(_api.entities.runtime):
		_api.entities.runtime.call("save_state")
	_api.entities.runtime = null
	return event

func _primary(event: Dictionary) -> Dictionary:
	if bool(event.get("handled", false)) or not is_instance_valid(_api.entities.runtime):
		return event
	var player := event.get("player") as PlayerController
	if player == null:
		return event
	var camera := player.get_node("Camera3D") as Camera3D
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 3.0)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var collider := hit.get("collider") as Node
	if collider != null and collider.has_meta("entity_id"):
		event.handled = true
		_api.entities.runtime.call("submit_attack", player, str(collider.get_meta("entity_id")))
	return event
