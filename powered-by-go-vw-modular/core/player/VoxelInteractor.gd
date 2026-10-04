class_name VoxelInteractor
extends Node

## Player-side voxel interaction component.
## It knows about input and the selected item, but not about
## Zylann terrain implementation details beyond raycast results.

@export var reach_distance := 8.0
@export var fallback_break_power := 1.0

var inventory: Inventory
var player: CharacterBody3D
var camera: Camera3D

var breaking_position := Vector3i.ZERO
var breaking_block_id := ""
var breaking_item_id := ""
var breaking_hits := 0
var breaking_active := false
var pending_edits: Dictionary = {}


func _exit_tree() -> void:
	if GameAPI.session != null and GameAPI.session.edit_result.is_connected(_on_edit_result):
		GameAPI.session.edit_result.disconnect(_on_edit_result)


func _ready() -> void:
	player = get_parent() as CharacterBody3D
	if player == null:
		push_error("[VoxelInteractor] Parent must be CharacterBody3D.")
		return

	inventory = player.get_node_or_null("Inventory") as Inventory
	camera = player.get_node_or_null("Camera3D") as Camera3D

	if GameAPI.session != null and not GameAPI.session.edit_result.is_connected(_on_edit_result):
		GameAPI.session.edit_result.connect(_on_edit_result)


func _physics_process(_delta: float) -> void:
	if player == null or not player.is_multiplayer_authority():
		return


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.is_multiplayer_authority():
		return

	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_primary_action()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_secondary_action()
			get_viewport().set_input_as_handled()


func _handle_primary_action() -> void:
	# The pistol is a ranged tool: shooting is handled by core:player_actions,
	# so do not also break blocks with it.
	if inventory != null and inventory.get_selected_item_id() == "core:pistol":
		_reset_breaking()
		return

	var hit = _raycast()
	if not hit:
		return

	var block_id := GameAPI.world.get_block_id(hit.position)
	if block_id == ContentRegistry.AIR_ID:
		_reset_breaking()
		return

	var item_id := inventory.get_selected_item_id()
	var required_hits := GameAPI.content.get_break_hits(item_id, block_id)

	if (
		not breaking_active
		or breaking_position != hit.position
		or breaking_block_id != block_id
		or breaking_item_id != item_id
	):
		breaking_active = true
		breaking_position = hit.position
		breaking_block_id = block_id
		breaking_item_id = item_id
		breaking_hits = 0

	breaking_hits += 1
	_play_interaction_swing()

	var event_data := {
		"player": player,
		"position": hit.position,
		"block_id": block_id,
		"item_id": item_id,
		"hit_number": breaking_hits,
		"required_hits": required_hits,
		"cancelled": false,
	}
	GameAPI.events.emit(GameEvents.BLOCK_HIT, event_data)

	if breaking_hits < required_hits:
		return

	var result: Dictionary = GameAPI.session.submit_block_break(hit.position)
	if bool(result.get("pending", false)):
		pending_edits[int(result["request_id"])] = {
			"action": "break",
			"position": hit.position,
		}
		_reset_breaking()
		return

	if bool(result.get("success", false)):
		_add_drops(result.get("drops", []))

	_reset_breaking()


func _handle_secondary_action() -> void:
	_reset_breaking()

	if inventory == null:
		return

	var item_id: String = inventory.get_selected_item_id()
	var hit = _raycast()
	var use_event: Dictionary = GameAPI.events.emit(GameEvents.ITEM_USE, {
		"player": player,
		"item_id": item_id,
		"hit": hit,
		"handled": false,
	})
	if bool(use_event.get("handled", false)):
		return

	# Custom items may legitimately use right click without targeting a voxel.
	if not hit:
		return

	var block_id: String = GameAPI.content.get_placement_block(item_id)
	if block_id.is_empty():
		return

	var place_position: Vector3i = hit.previous_position

	if not _can_place_against_players(place_position):
		return

	var result: Dictionary = GameAPI.session.submit_block_place(
		place_position,
		item_id
	)
	if bool(result.get("pending", false)) or bool(result.get("success", false)):
		_play_interaction_swing()
	if bool(result.get("pending", false)):
		pending_edits[int(result["request_id"])] = {
			"action": "place",
			"item_id": item_id,
		}
	elif bool(result.get("success", false)):
		inventory.remove_item(item_id, 1)


func _play_interaction_swing() -> void:
	var visual: PlayerVisual = player.get_node_or_null("PlayerVisual") as PlayerVisual
	if visual != null:
		visual.play_interaction_swing()

func _raycast():
	if camera == null or GameAPI.world == null:
		return null

	return GameAPI.world.raycast(
		camera.global_position,
		-camera.global_transform.basis.z,
		reach_distance
	)


func _add_drops(drops: Array) -> void:
	for drop in drops:
		if not (drop is Dictionary):
			continue
		var item_id := str(drop.get("item", ""))
		var count := int(drop.get("count", 1))
		if not item_id.is_empty():
			inventory.add_item(item_id, count)


func _can_place_against_players(block_pos: Vector3i) -> bool:
	if GameAPI.session == null:
		return true
	return GameAPI.session.can_place_block(block_pos, player)


func _on_edit_result(
	request_id: int,
	action: String,
	result: Dictionary
) -> void:
	if not pending_edits.has(request_id):
		return

	var pending: Dictionary = pending_edits[request_id]
	pending_edits.erase(request_id)

	if not bool(result.get("success", false)):
		return

	if action == "break":
		_add_drops(result.get("drops", []))
	elif action == "place":
		inventory.remove_item(str(pending.get("item_id", "")), 1)


func _reset_breaking() -> void:
	breaking_active = false
	breaking_position = Vector3i.ZERO
	breaking_block_id = ""
	breaking_item_id = ""
	breaking_hits = 0
