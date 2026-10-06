extends GameMod
func register(api: ModAPI) -> void:
	var service := api.load_asset("GridCrafting.gd").new() as RefCounted
	service.setup(api)
	api.crafting.grid_service = service
	# Wooden tools use planks in the familiar Minecraft layouts.
	for kind in ["pickaxe","axe","shovel","sword"]:
		var recipe: Dictionary = api.content.recipes.get("frontier:wood_" + kind,{})
		if not recipe.is_empty() and recipe.ingredients.has("core:log"):
			var count := int(recipe.ingredients["core:log"])
			recipe.ingredients.erase("core:log")
			recipe.ingredients["survival:planks"] = count
	# Semantic tags are shared by blocks and their inventory items.
	for id in ["survival:planks", "frontier:dark_plank", "frontier:weathered_plank", "frontier:cherry_plank", "frontier:ebony_plank"]:
		for definition in [api.content.get_block(id), api.content.get_item(id)]:
			if not definition.is_empty() and "core:planks" not in definition.tags:
				definition.tags.append("core:planks")
	for id in api.content.get_recipe_ids():
		var recipe := api.content.get_recipe(id)
		if recipe.ingredients.has("survival:planks"):
			var count := int(recipe.ingredients["survival:planks"])
			recipe.ingredients.erase("survival:planks")
			recipe.ingredients["#core:planks"] = count
