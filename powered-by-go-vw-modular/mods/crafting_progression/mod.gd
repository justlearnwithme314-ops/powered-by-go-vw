extends GameMod

const BENCH := "survival:workbench"
const FURNACE := "survival:furnace"
const PLANKS := "survival:planks"
const CHARCOAL := "survival:charcoal"
var _api: ModAPI
var _runtime_script: Script
var _runtime: Node
var _active_world: Node

func register(api: ModAPI) -> void:
	_api = api
	_runtime_script = api.load_asset("StationRuntime.gd") as Script
	for entry in [[PLANKS, "Planks", "planks", "axe", 0.8], [BENCH, "Workbench", "workbench", "axe", 1.0], [FURNACE, "Furnace", "furnace", "pickaxe", 2.0]]:
		api.register_block({"id": entry[0], "display_name": entry[1], "model": api.load_asset("models/%s.tres" % entry[2]), "hardness": entry[4], "preferred_tool": entry[3], "tags": ["block", "station" if entry[0] != PLANKS else "wood"]})
		api.register_item({"id": entry[0], "display_name": entry[1], "stack_size": 64, "place_block": entry[0], "icon": api.asset("textures/%s.png" % entry[2]), "tags": ["block"]})
	api.register_item({"id": CHARCOAL, "display_name": "Charcoal", "stack_size": 64, "icon": api.asset("textures/charcoal.png"), "properties": {"fuel_seconds": 80.0}})
	api.register_recipe("survival:planks", PLANKS, 4, {"core:log": 1})
	api.register_recipe("survival:sticks", "core:stick", 4, {PLANKS: 2})
	api.register_recipe("survival:workbench", BENCH, 1, {PLANKS: 4})
	api.register_recipe("survival:furnace", FURNACE, 1, {"core:stone": 8}, {"station": "workbench"})
	api.register_recipe("survival:charcoal", CHARCOAL, 1, {"core:log": 1}, {"method": "smelt", "station": "furnace", "duration": 8.0})
	api.configure_item_properties("core:log", {"fuel_seconds": 16.0})
	api.configure_item_properties(PLANKS, {"fuel_seconds": 4.0})
	api.configure_item_properties("frontier:coal_lump", {"fuel_seconds": 80.0})
	for id in api.content.get_recipe_ids():
		var recipe := api.content.get_recipe(id)
		var output := api.content.get_item(str(recipe.output))
		var props: Dictionary = output.get("properties", {})
		if not str(props.get("tool_type", "")).is_empty() or str(recipe.output) == "core:pistol_ammo":
			api.configure_recipe(id, {"station": "workbench"})
		if str(id).ends_with("_ingot"):
			api.configure_recipe(id, {"station": "furnace", "method": "smelt", "duration": 8.0})
	api.stations.register_kind(BENCH, ["workbench"], {})
	api.stations.register_kind(FURNACE, ["furnace"], {"input": 4, "fuel": 1, "output": 1})
	api.on(GameEvents.WORLD_READY, _world_ready)
	api.on(GameEvents.WORLD_STOPPING, _world_stopping)
	api.on(GameEvents.AFTER_BLOCK_PLACE, _placed)
	api.on(GameEvents.BEFORE_BLOCK_BREAK, _before_break)
	api.on(GameEvents.AFTER_BLOCK_BREAK, _broken)
	api.on(GameEvents.ITEM_USE, _used, 150)

func _world_ready(event: Dictionary) -> Dictionary:
	var world: Node = event.get("world") as Node
	_active_world = world
	if world == null:
		return event
	var peer := world.multiplayer.multiplayer_peer
	var networked := peer != null and not peer is OfflineMultiplayerPeer
	if networked and not world.multiplayer.is_server():
		_api.stations.activate("")
		return event
	_api.stations.activate(_api.saves.root_path.path_join(_api.saves.active_world_id + (".stations.json" if networked else ".entities.json")))
	_start_runtime(world)
	return event

func _start_runtime(world: Node) -> void:
	if world == null or _runtime_script == null:
		return
	if is_instance_valid(_runtime):
		return
	_runtime = _runtime_script.new() as Node
	_runtime.name = "CraftingStations"
	world.add_child(_runtime)
	_runtime.call("setup", _api)

func _world_stopping(event: Dictionary) -> Dictionary:
	if not _api.stations.path.is_empty():
		_api.stations.save()
	_runtime = null
	_active_world = null
	_api.stations.activate("")
	return event

func _placed(event: Dictionary) -> Dictionary:
	if not _api.stations.path.is_empty() and _api.stations.kinds.has(str(event.get("block_id", ""))):
		_api.stations.ensure(event.position)
	return event

func _before_break(event: Dictionary) -> Dictionary:
	# A damaged/older station sidecar must not make its blocks indestructible.
	# Keep the original sidecar untouched when it is unreadable; normal writable
	# worlds still spill the station contents in _broken().
	return event

func _broken(event: Dictionary) -> Dictionary:
	var id := _api.stations.key(event.position)
	var inventory := (event.player as Node).get_node_or_null("Inventory") as Inventory if event.get("player") is Node else null
	if inventory != null:
		for stack in _api.stations.remove(id):
			var added := inventory.add_stack(stack)
			if not added.remainder.is_empty():
				inventory.recovery.append(added.remainder)
	return event

func _used(event: Dictionary) -> Dictionary:
	if bool(event.get("handled", false)):
		return event
	var hit: Variant = event.get("hit")
	if hit == null:
		return event
	var station_block := _api.world.get_block_id(hit.position)
	if not _api.stations.kinds.has(station_block):
		return event
	# Shift is also the sprint key; keep its place-through behavior for workbenches,
	# but don't make a chest impossible to open while sprinting.
	if Input.is_key_pressed(KEY_SHIFT) and station_block != "survival:chest":
		return event
	event.handled = true
	var player := event.player as Node3D
	var world: Node = _active_world
	var peer: MultiplayerPeer = world.multiplayer.multiplayer_peer if world != null else null
	var remote_client: bool = peer != null and not peer is OfflineMultiplayerPeer and not world.multiplayer.is_server()
	if _runtime == null and not remote_client:
		_start_runtime(world)
	if not _api.stations.writable:
		push_warning("[Stations] Cannot open this station because its save data failed validation. The original save is preserved.")
		return event
	if _runtime == null:
		push_warning("[Stations] Station UI is unavailable on a multiplayer client; open it on the host.")
		return event
	var id := _api.stations.ensure(hit.position)
	if id.is_empty():
		push_warning("[Stations] Could not create or find station data at %s." % hit.position)
		return event
	if not _api.stations.accessible(player, id):
		push_warning("[Stations] Station is out of reach or its block no longer matches its saved data.")
		return event
	if _api.world.get_block_id(hit.position) == BENCH:
		player.get_tree().call_group("inventory_ui", "set_open", true)
	else:
		_runtime.call("open_station", player, id)
	return event
