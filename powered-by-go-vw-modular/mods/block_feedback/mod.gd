extends GameMod

var _api: ModAPI
var _feedback_script: Script

func register(api: ModAPI) -> void:
	_api = api
	_feedback_script = api.load_asset("BlockFeedback.gd") as Script
	api.on(GameEvents.PLAYER_SPAWNED, _spawned)

func _spawned(event: Dictionary) -> Dictionary:
	var player: Node = event.get("player") as Node
	if player == null or not player.is_multiplayer_authority() or player.has_node("BlockFeedback"):
		return event
	var interactor := player.get_node_or_null("VoxelInteractor") as VoxelInteractor
	if interactor == null:
		return event
	var feedback: Node3D = _feedback_script.new() as Node3D
	feedback.name = "BlockFeedback"
	player.add_child(feedback)
	feedback.call("setup", interactor, _api)
	return event
