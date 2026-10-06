extends GameMod

var _api: ModAPI
var _survival_script: Script

func register(api: ModAPI) -> void:
	_api = api
	_survival_script = api.load_asset("PlayerSurvival.gd") as Script
	for tier in ["iron", "diamond"]:
		var material := "frontier:iron_ingot" if tier == "iron" else "frontier:diamond"
		var strength := 1.0 if tier == "iron" else 1.3
		for entry in [["helmet", "head", 2, 5], ["chestplate", "body", 6, 8], ["leggings", "legs", 5, 7], ["boots", "feet", 2, 4]]:
			var id := "survival:%s_%s" % [tier, entry[0]]
			api.register_item({"id": id, "display_name": "%s %s" % [tier.capitalize(), str(entry[0]).capitalize()], "stack_size": 1, "tags": ["armor"], "icon": api.asset("icons/%s_%s.png" % [tier, entry[0]]), "properties": {"equipment_slots": [entry[1]], "armor": float(entry[2]) * strength, "max_durability": 240 if tier == "iron" else 600, "repair_material": material, "repair_station": "workbench"}})
			api.register_recipe(id, id, 1, {material: int(entry[3])}, {"station": "workbench"})
	api.register_item({"id": "survival:bandage", "display_name": "Bandage", "stack_size": 16, "icon": api.asset("icons/bandage.png"), "properties": {"healing": 6.0}})
	api.register_recipe("survival:bandage", "survival:bandage", 1, {"core:leaves": 3})
	for id in api.content.items:
		var props: Dictionary = api.content.get_item(str(id)).get("properties", {})
		var kind := str(props.get("tool_type", ""))
		if not kind.is_empty():
			api.configure_item_properties(str(id), {"melee_damage": 4.0 + int(props.get("mining_level", 0)) if kind == "sword" else 2.0})
	api.on(GameEvents.PLAYER_SPAWNED, _spawned)
	api.on(GameEvents.WORLD_STOPPING, _stopping, 400)
	api.on(GameEvents.PRIMARY_ACTION, _primary, 200)
	api.on(GameEvents.ITEM_USE, _used, 200)

func _stopping(event: Dictionary) -> Dictionary:
	for player in Engine.get_main_loop().get_nodes_in_group("player_character"):
		var survival: Node = player.get_node_or_null("DamageReceiver")
		if player.is_multiplayer_authority() and survival != null and survival.has_method("_persist"):
			survival.call("_persist")
	return event

func _spawned(event: Dictionary) -> Dictionary:
	var player := event.get("player") as PlayerController
	if player == null or not player.is_multiplayer_authority() or player.has_node("DamageReceiver"):
		return event
	var peer := player.multiplayer.multiplayer_peer
	if peer != null and not peer is OfflineMultiplayerPeer:
		return event
	var component: Node = _survival_script.new() as Node
	component.name = "DamageReceiver"
	player.add_child(component)
	component.call("setup", _api)
	return event

func _primary(event: Dictionary) -> Dictionary:
	if bool(event.get("handled", false)):
		return event
	var player := event.get("player") as PlayerController
	if player == null or not player.has_node("DamageReceiver") or bool(player.get_meta("gameplay_disabled", false)):
		return event
	var inventory := player.get_node("Inventory") as Inventory
	var camera := player.get_node("Camera3D") as Camera3D
	var direction := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + direction * 3.0)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.get("collider") is Node:
		return event
	var collider := hit.collider as Node
	var receiver := collider.get_node_or_null("DamageReceiver") as DamageReceiver
	if receiver == null:
		return event
	event.handled = true
	var stack := inventory.get_slot(inventory.selected_slot)
	if not _api.item_instances.usable(stack) or receiver.health <= 0.0:
		return event
	var amount := float(_api.item_instances.stats(stack).get("melee_damage", 1.0))
	var before := receiver.health
	DamageReceiver.deliver(collider, amount, {"source": player, "damage_type": "physical", "position": hit.position, "direction": direction})
	if receiver.health < before:
		_api.item_instances.spend(inventory, inventory.selected_slot)
		if collider is CharacterBody3D:
			(collider as CharacterBody3D).velocity += direction * 3.0 + Vector3.UP
		elif collider is RigidBody3D:
			(collider as RigidBody3D).apply_central_impulse(direction * 3.0)
	return event

func _used(event: Dictionary) -> Dictionary:
	if bool(event.get("handled", false)):
		return event
	if str(event.get("item_id", "")) != "survival:bandage":
		return event
	var player: Node = event.get("player") as Node
	var receiver := player.get_node_or_null("DamageReceiver") if player != null else null
	if receiver != null and receiver.has_method("try_bandage"):
		receiver.call("try_bandage")
		event.handled = true
	return event
