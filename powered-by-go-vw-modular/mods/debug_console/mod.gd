extends GameMod
var _api: ModAPI
var _script: Script

func register(api: ModAPI) -> void:
	_api = api
	_script = api.load_asset("Console.gd")
	api.on(GameEvents.PLAYER_SPAWNED, _spawned)

func _spawned(event: Dictionary) -> Dictionary:
	var player := event.get("player") as Node
	if player != null and player.is_multiplayer_authority() and not player.has_node("DebugConsole"):
		var console := _script.new() as CanvasLayer
		console.name = "DebugConsole"
		player.add_child(console)
		console.setup(_api, player)
	return event
