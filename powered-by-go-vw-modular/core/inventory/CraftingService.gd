
class_name CraftingService
extends RefCounted

## Gameplay service for crafting.
##
## The UI only asks this service to craft.
## Recipes remain data, and mods can intercept crafting through events.
##
## Inventory is intentionally handled as Object rather than the Inventory
## class directly. This keeps this service from depending on Inventory.gd
## being registered as a global class at parse time.

var content: ContentRegistry
var events: EventBus
var stations: BlockEntityService
var item_instances: ItemInstanceService
var grid_service: RefCounted

func _ingredients(inventory: Object, recipe: Dictionary) -> Dictionary:
	var available := {}
	for id in content.get_item_ids():
		var count := int(inventory.call("get_item_count", id))
		if count > 0: available[id] = count
	return content.resolve_ingredients(recipe.get("ingredients", {}), available)


func _init(p_content: ContentRegistry, p_events: EventBus) -> void:
	content = p_content
	events = p_events


func can_craft(inventory: Object, recipe_id: String) -> bool:
	if inventory == null:
		return false

	if not is_instance_valid(inventory):
		return false

	var recipe: Dictionary = content.get_recipe(recipe_id)

	if recipe.is_empty():
		return false
	if not requirement(inventory, recipe_id).is_empty():
		return false

	var resolved := _ingredients(inventory, recipe)
	if not resolved.success:
		return false
	var ingredients: Dictionary = resolved.items

	for item_id in ingredients:
		var logical_item_id: String = str(item_id)
		var required: int = int(ingredients[item_id])

		if required <= 0:
			continue

		var owned: int = int(
			inventory.call("get_item_count", logical_item_id)
		)

		if owned < required:
			return false

	if inventory.has_method("can_exchange"):
		return bool(inventory.call("can_exchange", ingredients, {"id": str(recipe.get("output", "")), "count": int(recipe.get("count", 1))}))
	return true

func requirement(inventory: Object, recipe_id: String) -> String:
	var recipe := content.get_recipe(recipe_id)
	if recipe.is_empty():
		return "Unknown recipe"
	if str(recipe.get("method", "craft")) != "craft":
		return "Requires fuel-based furnace processing"
	var station := str(recipe.get("station", "hand"))
	if station == "hand":
		return ""
	var player := inventory.get_parent() as Node3D if inventory is Node else null
	if stations == null or player == null or station not in stations.capabilities(player):
		return "Requires nearby %s" % station
	return ""


func craft(
	player: Node,
	inventory: Object,
	recipe_id: String
) -> Dictionary:
	if inventory == null:
		return {
			"success": false,
			"reason": "inventory_missing",
		}

	if not is_instance_valid(inventory):
		return {
			"success": false,
			"reason": "inventory_invalid",
		}

	var recipe: Dictionary = content.get_recipe(recipe_id)

	if recipe.is_empty():
		return {
			"success": false,
			"reason": "unknown_recipe",
		}
	var missing_station := requirement(inventory, recipe_id)
	if not missing_station.is_empty():
		return {"success": false, "reason": missing_station}

	if not can_craft(inventory, recipe_id):
		return {
			"success": false,
			"reason": "missing_ingredients",
		}

	# Let mods inspect or modify the crafting operation.
	var event: Dictionary = events.emit(
		GameEvents.BEFORE_CRAFT,
		{
			"player": player,
			"inventory": inventory,
			"recipe_id": recipe_id,
			"recipe": recipe,
			"cancelled": false,
		}
	)

	if bool(event.get("cancelled", false)):
		return {
			"success": false,
			"reason": "cancelled",
		}

	if inventory.has_method("craft_transaction"):
		if not can_craft(inventory, recipe_id):
			return {"success": false, "reason": "Crafting context changed"}
		var output_id := str(event.get("output", recipe.get("output", "")))
		var output_count := maxi(int(event.get("count", recipe.get("count", 1))), 1)
		if not content.has_item(output_id):
			return {"success": false, "reason": "invalid_output"}
		var output_stack := {"id": output_id, "count": output_count}
		if item_instances != null and output_count == 1:
			output_stack = item_instances.prepare(output_stack)
		var resolved := _ingredients(inventory, recipe)
		if not resolved.success or not bool(inventory.call("craft_transaction", resolved.items, output_stack)):
			return {"success": false, "reason": "ingredients_or_capacity"}
		var result := {"success": true, "recipe_id": recipe_id, "output": output_id, "count": output_count}
		events.emit(GameEvents.AFTER_CRAFT, {"player": player, "inventory": inventory, "recipe_id": recipe_id, "recipe": recipe, "result": result})
		return result

	var resolved := _ingredients(inventory, recipe)
	if not resolved.success:
		return {"success": false, "reason": "missing_ingredients"}
	var ingredients: Dictionary = resolved.items
	var removed_items: Array[Dictionary] = []

	# Remove all ingredients.
	for item_id in ingredients:
		var logical_item_id: String = str(item_id)
		var amount: int = int(ingredients[item_id])

		if amount <= 0:
			continue

		var removed: bool = bool(
			inventory.call(
				"remove_item",
				logical_item_id,
				amount
			)
		)

		if not removed:
			# Crafting failed partway through.
			# Restore anything already removed.
			for restored in removed_items:
				inventory.call(
					"add_item",
					str(restored["item_id"]),
					int(restored["count"])
				)

			return {
				"success": false,
				"reason": "inventory_changed",
			}

		removed_items.append({
			"item_id": logical_item_id,
			"count": amount,
		})

	# Allow BEFORE_CRAFT handlers to modify the result.
	var output_id: String = str(
		event.get(
			"output",
			recipe.get("output", "")
		)
	)

	var output_count: int = maxi(
		int(
			event.get(
				"count",
				recipe.get("count", 1)
			)
		),
		1
	)

	# Validate the output item.
	if output_id.is_empty() or not content.has_item(output_id):
		for restored in removed_items:
			inventory.call(
				"add_item",
				str(restored["item_id"]),
				int(restored["count"])
			)

		return {
			"success": false,
			"reason": "invalid_output",
		}

	# Add the crafted result.
	var added: bool = bool(
		inventory.call(
			"add_item",
			output_id,
			output_count
		)
	)

	if not added:
		# Roll back ingredients.
		for restored in removed_items:
			inventory.call(
				"add_item",
				str(restored["item_id"]),
				int(restored["count"])
			)

		return {
			"success": false,
			"reason": "output_rejected",
		}

	var result: Dictionary = {
		"success": true,
		"recipe_id": recipe_id,
		"output": output_id,
		"count": output_count,
	}

	events.emit(
		GameEvents.AFTER_CRAFT,
		{
			"player": player,
			"inventory": inventory,
			"recipe_id": recipe_id,
			"recipe": recipe,
			"result": result,
		}
	)

	return result
