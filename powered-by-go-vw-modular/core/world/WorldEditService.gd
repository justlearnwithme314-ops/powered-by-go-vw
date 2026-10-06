class_name WorldEditService
extends RefCounted

## High-level block operations.
##
## This is intentionally separate from VoxelWorldService so mods can
## hook gameplay rules without touching Zylann directly.

var content: ContentRegistry
var world: VoxelWorldService
var events: EventBus


func _init(
	p_content: ContentRegistry,
	p_world: VoxelWorldService,
	p_events: EventBus
) -> void:
	content = p_content
	world = p_world
	events = p_events


func break_block(player: Node, pos: Vector3i) -> Dictionary:
	if player != null and bool(player.get_meta("gameplay_disabled", false)):
		return {"success": false, "reason": "player_inactive"}
	var block_id: String = world.get_block_id(pos)

	if block_id == ContentRegistry.AIR_ID:
		return {
			"success": false,
			"reason": "air"
		}

	if not content.has_block(block_id):
		return {
			"success": false,
			"reason": "unknown_block"
		}

	var inventory: Inventory = player.get_node_or_null("Inventory") as Inventory if player != null else null
	if inventory != null:
		var item_id := inventory.get_selected_item_id()
		if not player.is_multiplayer_authority() and not bool(player.get_meta("inventory_authority", false)):
			var visual := player.get_node_or_null("PlayerVisual") as PlayerVisual
			item_id = visual.held_item_id if visual != null else ""
		var profile := content.get_mining_profile(item_id, block_id)
		if not bool(profile.allowed):
			return {"success": false, "reason": profile.reason}

	var block_data: Dictionary = content.get_block(block_id)

	var default_drops_value: Variant = block_data.get(
		"drops",
		[]
	)

	var default_drops: Array = []

	if default_drops_value is Array:
		default_drops = default_drops_value.duplicate(true)

	var event: Dictionary = events.emit(
		GameEvents.BEFORE_BLOCK_BREAK,
		{
			"player": player,
			"position": pos,
			"block_id": block_id,
			"drops": default_drops,
			"cancelled": false,
		}
	)

	if bool(event.get("cancelled", false)):
		return {
			"success": false,
			"reason": "cancelled"
		}

	var drops_value: Variant = event.get(
		"drops",
		default_drops
	)

	var drops: Array = default_drops

	if drops_value is Array:
		drops = drops_value

	if not world.set_block(
		pos,
		ContentRegistry.AIR_ID
	):
		return {
			"success": false,
			"reason": "world_not_ready"
		}

	events.emit(
		GameEvents.AFTER_BLOCK_BREAK,
		{
			"player": player,
			"position": pos,
			"block_id": block_id,
			"drops": drops,
		}
	)

	return {
		"success": true,
		"block_id": block_id,
		"drops": drops,
	}


func place_block(player: Node, pos: Vector3i, item_id: String) -> Dictionary:
	if player != null and bool(player.get_meta("gameplay_disabled", false)):
		return {"success": false, "reason": "player_inactive"}
	if not content.has_item(item_id):
		return {"success": false, "reason": "unknown_item"}

	var current_block := world.get_block_id(pos)
	if current_block != ContentRegistry.AIR_ID:
		return {"success": false, "reason": "occupied"}

	var block_id := content.get_placement_block(item_id)
	if block_id.is_empty() or not content.has_block(block_id):
		return {"success": false, "reason": "not_placeable"}

	var before := events.emit(GameEvents.BEFORE_BLOCK_PLACE, {
		"player": player,
		"position": pos,
		"item_id": item_id,
		"block_id": block_id,
		"cancelled": false,
	})
	if bool(before.get("cancelled", false)):
		return {"success": false, "reason": "cancelled"}

	block_id = str(before.get("block_id", block_id))
	if not content.has_block(block_id) or block_id == ContentRegistry.AIR_ID:
		return {"success": false, "reason": "invalid_block_override"}

	if not world.set_block(pos, block_id):
		return {"success": false, "reason": "world_not_ready"}

	events.emit(GameEvents.AFTER_BLOCK_PLACE, {
		"player": player,
		"position": pos,
		"item_id": item_id,
		"block_id": block_id,
	})

	return {
		"success": true,
		"block_id": block_id,
	}
