class_name PlayerActionsMod
extends GameMod

var _api: ModAPI
var _movement_script: Script
var _pistol_script: Script

func register(api: ModAPI) -> void:
	_api = api
	_movement_script = api.load_asset("scripts/PlayerMovement.gd") as Script
	_pistol_script = api.load_asset("scripts/PistolActions.gd") as Script
	api.on(GameEvents.PLAYER_SPAWNED, _spawned)
	api.on(GameEvents.PLAYER_DESPAWNED, _despawned)

func _spawned(event: Dictionary) -> Dictionary:
	var player: PlayerController = event.get("player") as PlayerController
	if player == null or not player.is_multiplayer_authority() or player.has_node("PlayerActions"):
		return event
	var root: Node = Node.new()
	root.name = "PlayerActions"
	player.add_child(root)
	var movement: Node = _movement_script.new() as Node
	root.add_child(movement)
	movement.call("setup", player, _api)
	var pistol: Node = _pistol_script.new() as Node
	root.add_child(pistol)
	pistol.call("setup", player, _api)
	return event

func _despawned(event: Dictionary) -> Dictionary:
	var player: Node = event.get("player") as Node
	if is_instance_valid(player):
		var root: Node = player.get_node_or_null("PlayerActions")
		if root != null:
			root.queue_free()
	return event
