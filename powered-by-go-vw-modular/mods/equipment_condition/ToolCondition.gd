extends Node

var _api: ModAPI
var _inventory: Inventory
var _interactor: VoxelInteractor

func setup(api: ModAPI) -> void:
	_api = api
	_inventory = get_parent().get_node_or_null("Inventory") as Inventory
	_interactor = get_parent().get_node_or_null("VoxelInteractor") as VoxelInteractor
	if _interactor != null:
		_interactor.block_feedback.connect(_feedback)

func _feedback(_block: String, _position: Vector3i, action: String) -> void:
	if action == "hit" and _inventory != null:
		_api.item_instances.spend(_inventory, _inventory.selected_slot)
