class_name VoxelInteractor
extends Node

## Player-side voxel interaction component.
## It knows about input and the selected item, but not about
## Zylann terrain implementation details beyond raycast results.

@export var reach_distance := 8.0
signal mining_progress(position: Vector3i, progress: float)
signal mining_cleared
signal block_feedback(block_id: String, position: Vector3i, action: String)

const PLACE_INTERVAL := 0.2
var place_cooldown := 0.0
var swing_cooldown := 0.0
var primary_held := false
var secondary_held := false
var hit_cooldown := 0.0
var mining_hud: CanvasLayer
var mining_bar: ProgressBar
var mining_label: Label
var blocked_notice := 0.0

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


func _physics_process(delta: float) -> void:
	if player == null or not player.is_multiplayer_authority():
		return
	if bool(player.get_meta("gameplay_disabled", false)):
		primary_held = false
		secondary_held = false
		return

	hit_cooldown = maxf(0.0, hit_cooldown - delta)
	place_cooldown = maxf(0.0, place_cooldown - delta)
	swing_cooldown = maxf(0.0, swing_cooldown - delta)
	blocked_notice = maxf(0.0, blocked_notice - delta)
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		primary_held = false
		secondary_held = false
	if breaking_active:
		var hit = _raycast()
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED or not hit:
			_reset_breaking()
		elif hit.position != breaking_position or GameAPI.world.get_block_id(hit.position) != breaking_block_id or inventory.get_selected_item_id() != breaking_item_id:
			_reset_breaking()
	elif mining_hud != null and blocked_notice <= 0.0:
		mining_hud.hide()
	if primary_held:
		if inventory != null and inventory.get_selected_item_id() != "core:pistol":
			_play_interaction_swing()
		_handle_primary_action()
	elif secondary_held and inventory != null and not GameAPI.content.get_placement_block(inventory.get_selected_item_id()).is_empty():
		_handle_secondary_action()


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.is_multiplayer_authority():
		return
	if bool(player.get_meta("gameplay_disabled", false)):
		return

	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			primary_held = event.pressed
			if event.pressed:
				_handle_primary_action()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			secondary_held = event.pressed
			if event.pressed:
				_handle_secondary_action()
			get_viewport().set_input_as_handled()


func _handle_primary_action() -> void:
	if player != null and bool(player.get_meta("gameplay_disabled", false)):
		return
	if inventory == null or hit_cooldown > 0.0:
		return
	# The pistol is a ranged tool: shooting is handled by core:player_actions,
	# so do not also break blocks with it.
	if inventory != null and inventory.get_selected_item_id() == "core:pistol":
		_reset_breaking()
		return

	_play_interaction_swing()
	hit_cooldown = 0.4
	var primary_event := GameAPI.events.emit(GameEvents.PRIMARY_ACTION, {"player": player, "handled": false})
	if bool(primary_event.get("handled", false)):
		_reset_breaking()
		return
	var hit = _raycast()
	if not hit:
		return

	var block_id := GameAPI.world.get_block_id(hit.position)
	for pending in pending_edits.values():
		if pending.get("action", "") == "break" and pending.get("position") == hit.position:
			return
	if block_id == ContentRegistry.AIR_ID:
		_reset_breaking()
		return

	var item_id := inventory.get_selected_item_id()
	var selected := inventory.get_slot(inventory.selected_slot)
	if not GameAPI.item_instances.usable(selected):
		_reset_breaking()
		_show_mining(0, 1, "Broken tool — repair at a workbench")
		blocked_notice = 1.5
		return
	var profile := GameAPI.content.get_mining_profile(item_id, block_id, GameAPI.item_instances.stats(selected))
	hit_cooldown = float(profile.interval)
	if not bool(profile.allowed):
		_reset_breaking()
		_show_mining(0, 1, str(profile.reason))
		blocked_notice = 1.5
		return
	var required_hits := int(profile.hits)

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
	_show_mining(breaking_hits, required_hits, "%s  %d / %d" % [GameAPI.content.get_block(block_id).get("display_name", block_id), breaking_hits, required_hits])

	var event_data := {
		"player": player,
		"position": hit.position,
		"block_id": block_id,
		"item_id": item_id,
		"hit_number": breaking_hits,
		"required_hits": required_hits,
		"cancelled": false,
	}
	var hit_event := GameAPI.events.emit(GameEvents.BLOCK_HIT, event_data)
	if bool(hit_event.get("cancelled", false)):
		breaking_hits -= 1
		_show_mining(breaking_hits, required_hits, "Hit cancelled")
		mining_progress.emit(breaking_position, float(breaking_hits) / required_hits)
		return
	mining_progress.emit(breaking_position, float(breaking_hits) / required_hits)
	block_feedback.emit(block_id, breaking_position, "hit")

	if breaking_hits < required_hits:
		return

	var result: Dictionary = GameAPI.session.submit_block_break(hit.position)
	if bool(result.get("pending", false)):
		pending_edits[int(result["request_id"])] = {
			"action": "break",
			"position": hit.position,
			"block_id": block_id,
		}
		_reset_breaking()
		return

	if bool(result.get("success", false)):
		_add_drops(result.get("drops", []))
		block_feedback.emit(block_id, hit.position, "break")

	_reset_breaking()


func _handle_secondary_action() -> void:
	if player != null and bool(player.get_meta("gameplay_disabled", false)):
		return
	if place_cooldown > 0.0:
		return
	place_cooldown = PLACE_INTERVAL
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
	# Wait for the server before spending another unit from this stack.
	for pending in pending_edits.values():
		if pending.get("action", "") == "place":
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
			"block_id": block_id,
			"position": place_position,
		}
	elif bool(result.get("success", false)):
		inventory.remove_item(item_id, 1)
		block_feedback.emit(str(result.get("block_id", block_id)), place_position, "place")


func _play_interaction_swing() -> void:
	if swing_cooldown > 0.0:
		return
	var visual: PlayerVisual = player.get_node_or_null("PlayerVisual") as PlayerVisual
	if visual != null:
		visual.play_interaction_swing()
		swing_cooldown = PlayerVisual.SWING_DURATION

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
			inventory.grant_item(item_id, count)


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
	block_feedback.emit(str(result.get("block_id", pending.get("block_id", ""))), pending.get("position", Vector3i.ZERO), action)


func _reset_breaking() -> void:
	mining_cleared.emit()
	if mining_hud != null:
		mining_hud.hide()
	breaking_active = false
	breaking_position = Vector3i.ZERO
	breaking_block_id = ""
	breaking_item_id = ""
	breaking_hits = 0


func _show_mining(hits: int, total: int, text: String) -> void:
	if mining_hud == null:
		mining_hud = CanvasLayer.new()
		add_child(mining_hud)
		var root := Control.new()
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mining_hud.add_child(root)
		var panel := VBoxContainer.new()
		root.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		panel.offset_left = -110
		panel.offset_right = 110
		panel.offset_top = 32
		panel.offset_bottom = 86
		panel.custom_minimum_size = Vector2(220, 0)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mining_label = Label.new()
		mining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mining_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(mining_label)
		mining_bar = ProgressBar.new()
		mining_bar.custom_minimum_size = Vector2(220, 10)
		mining_bar.show_percentage = false
		mining_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(mining_bar)
	mining_label.text = text
	mining_bar.max_value = total
	mining_bar.value = hits
	mining_hud.show()
