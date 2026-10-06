extends GameMod

var _api: ModAPI
var _component_script: Script

func register(api: ModAPI) -> void:
	_api = api
	_component_script = api.load_asset("ToolCondition.gd") as Script
	var tiers := {"wood": [64, "core:log"], "stone": [128, "core:stone"], "bronze": [256, "frontier:bronze_ingot"], "steel": [512, "frontier:steel_ingot"], "mese": [768, "frontier:mese_crystal"], "diamond": [1024, "frontier:diamond"], "murexium": [1536, "frontier:murexium"]}
	for id in api.content.items:
		var props: Dictionary = api.content.get_item(str(id)).get("properties", {})
		if str(props.get("tool_type", "")).is_empty():
			continue
		var tier := str(id).get_slice(":", 1).get_slice("_", 0)
		if tiers.has(tier):
			api.configure_item_properties(str(id), {"max_durability": tiers[tier][0], "repair_material": tiers[tier][1], "repair_station": "workbench"})
	api.item_instances.register_modifier("survival:efficient", "break_power", 0.0, 1.25)
	api.item_instances.register_modifier("survival:swift", "mining_interval", 0.0, 0.85)
	api.item_instances.register_modifier("survival:reinforced", "max_durability", 0.0, 1.2)
	api.on(GameEvents.PLAYER_SPAWNED, _spawned)

func _spawned(event: Dictionary) -> Dictionary:
	var player: Node = event.get("player") as Node
	if player == null or not player.is_multiplayer_authority() or player.has_node("ToolCondition"):
		return event
	var peer := player.multiplayer.multiplayer_peer
	if peer != null and not peer is OfflineMultiplayerPeer:
		return event
	var component: Node = _component_script.new() as Node
	component.name = "ToolCondition"
	player.add_child(component)
	component.call("setup", _api)
	return event
