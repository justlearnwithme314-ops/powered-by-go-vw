class_name InventoryCommandService
extends RefCounted

## Trusted actor supplied by the caller; network adapters must resolve RPC sender.
## Requests carry operations and slot indices, never replacement stack records.
var stations: BlockEntityService
var crafting: CraftingService
var item_instances: ItemInstanceService
var _receipts: Dictionary = {}
var _request_order: Array[String] = []
var _highwater: Dictionary = {}
var _next_id := 1

func _init(entities: BlockEntityService, recipes: CraftingService) -> void:
	stations = entities
	crafting = recipes

func revisions(inventory: Inventory) -> Array:
	inventory._ensure_storage()
	return [inventory.container.revision, inventory.equipment.revision, inventory.cursor.revision, inventory.crafting_grid.revision]

func request(actor: Node, action: String, arguments: Dictionary = {}) -> Dictionary:
	var inventory := actor.get_node_or_null("Inventory") as Inventory
	if inventory == null:
		return {"success": false, "reason": "Inventory missing"}
	if inventory.is_remote_inventory():
		return inventory.network_request(action, arguments)
	if bool(actor.get_meta("gameplay_disabled", false)):
		return {"success": false, "reason": "Player cannot act right now"}
	var payload := arguments.duplicate(true)
	payload.merge({"request_id": _next_id, "action": action, "revisions": revisions(inventory)}, true)
	_next_id += 1
	return execute(actor, payload)

func execute(actor: Node, request: Dictionary) -> Dictionary:
	var inventory := actor.get_node_or_null("Inventory") as Inventory if is_instance_valid(actor) else null
	if inventory == null:
		return {"success": false, "reason": "Inventory missing"}
	if bool(actor.get_meta("gameplay_disabled", false)):
		return {"success": false, "reason": "Player cannot act right now"}
	if actor.is_inside_tree() and actor.multiplayer.multiplayer_peer != null and not actor.multiplayer.multiplayer_peer is OfflineMultiplayerPeer and not bool(actor.get_meta("inventory_authority", false)):
		return {"success": false, "reason": "Shared inventory commands require the forthcoming server ownership protocol"}
	var request_id := int(request.get("request_id", 0))
	if request_id <= 0:
		return {"success": false, "reason": "Invalid request ID"}
	var receipt_key := "%d:%d" % [actor.get_instance_id(), request_id]
	var fingerprint := JSON.stringify(request)
	if _receipts.has(receipt_key):
		var cached: Dictionary = _receipts[receipt_key]
		return cached.result.duplicate(true) if cached.fingerprint == fingerprint else {"success": false, "reason": "Request ID reused"}
	if request_id <= int(_highwater.get(actor.get_instance_id(), 0)):
		return {"success": false, "reason": "Expired request ID"}
	if request.get("revisions", []) != revisions(inventory):
		return {"success": false, "reason": "Inventory changed; retry"}
	var action := str(request.get("action", ""))
	var result := {"success": true}
	match action:
		"grid_resize", "grid_click", "grid_craft", "grid_return":
			result = crafting.grid_service.call("command", actor, inventory, action, request) if crafting.grid_service != null else {"success":false,"reason":"Grid unavailable"}
		"select": inventory.set_selected_slot(int(request.get("index", 0)))
		"equip": result = inventory.equip(int(request.get("from", -1)), int(request.get("to", -1)))
		"move": result = inventory.move_stack(int(request.get("from", -1)), int(request.get("to", -1)), int(request.get("amount", 2147483647)))
		"click": inventory.click_slot(int(request.get("index", -1)), bool(request.get("right", false)), bool(request.get("equipped", false)))
		"return_cursor": inventory.return_cursor()
		"collect": inventory.collect_matching()
		"quick_transfer": inventory.quick_transfer(int(request.get("index", -1)))
		"unequip": result = inventory.unequip(int(request.get("from", -1)), int(request.get("to", -1)))
		"organize": inventory.organize_backpack()
		"recover": result["added"] = inventory.recover_available()
		"craft": result = crafting.craft(actor, inventory, str(request.get("recipe_id", "")))
		"repair":
			var index := int(request.get("index", -1))
			var required_station := str(item_instances.stats(inventory.get_slot(index)).get("repair_station", "hand")) if item_instances != null else "hand"
			if item_instances == null or required_station not in stations.capabilities(actor as Node3D):
				result = {"success": false, "reason": "Repair requires nearby %s" % required_station}
			else:
				result = item_instances.repair(inventory, index)
		"station_transfer":
			var id := str(request.get("station", ""))
			var target := stations.container(id, str(request.get("container", "")))
			if bool(request.get("into", true)) and str(request.get("container", "")) == "output":
				result = {"success": false, "reason": "Output is collection only"}
			elif not stations.accessible(actor as Node3D, id) or target == null or int(request.get("station_revision", -1)) != target.revision:
				result = {"success": false, "reason": "Station unavailable or changed"}
			else:
				var into := bool(request.get("into", true))
				var source := inventory.container if into else target
				var destination := target if into else inventory.container
				result = source.transfer_to(destination, int(request.get("from", -1)), int(request.get("to", -1)), int(request.get("amount", 2147483647)))
		_: result = {"success": false, "reason": "Unknown inventory command"}
	result["revisions"] = revisions(inventory)
	if bool(result.get("success", false)) and stations.inventory == inventory and not stations.path.is_empty():
		result["persisted"] = stations.save()
	_receipts[receipt_key] = {"fingerprint": fingerprint, "result": result.duplicate(true)}
	_highwater[actor.get_instance_id()] = request_id
	_next_id = maxi(_next_id, request_id + 1)
	_request_order.append(receipt_key)
	if _request_order.size() > 256:
		_receipts.erase(_request_order.pop_front())
	return result
