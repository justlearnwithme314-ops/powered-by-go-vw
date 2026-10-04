
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

	var ingredients: Dictionary = recipe.get("ingredients", {})

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

	return true


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

	var ingredients: Dictionary = recipe.get("ingredients", {})
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
