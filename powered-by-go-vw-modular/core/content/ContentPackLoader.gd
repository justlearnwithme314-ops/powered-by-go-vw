class_name ContentPackLoader
extends RefCounted

const MAX_BLOCKS := 128
const MAX_ITEMS := 256
const MAX_RECIPES := 512


func register_pack(api: Variant, pack_path: String) -> Dictionary:
	if api == null or api.content == null or api.content.is_finalized():
		return {"success": false, "errors": ["Content packs must register before content finalization."], "registered": {}}
	var resolved_path: String = str(api.asset(pack_path))
	if not FileAccess.file_exists(resolved_path):
		return {"success": false, "errors": ["Pack file not found: %s" % resolved_path], "registered": {}}
	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		return {"success": false, "errors": ["Could not read pack file: %s" % resolved_path], "registered": {}}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"success": false, "errors": ["Pack must contain a JSON object."], "registered": {}}
	var staged := _stage(api, parser.data)
	if not bool(staged.get("success", false)):
		return {"success": false, "errors": staged.get("errors", []), "registered": {}}
	var blocks: Array = staged.blocks
	var items: Array = staged.items
	var recipes: Array = staged.recipes
	for definition in blocks:
		if api.content.register_block(definition) < 0:
			return {"success": false, "errors": ["Registry rejected block %s after preflight." % definition.id], "registered": {}}
	for definition in items:
		if not api.content.register_item(definition):
			return {"success": false, "errors": ["Registry rejected item %s after preflight." % definition.id], "registered": {}}
	for definition in recipes:
		var options: Dictionary = definition.get("options", {})
		if not api.register_recipe(str(definition.id), str(definition.output), int(definition.count), definition.ingredients, options):
			return {"success": false, "errors": ["Registry rejected recipe %s after preflight." % definition.id], "registered": {}}
		if definition.has("pattern"):
			api.crafting.grid_service.register_pattern(str(definition.id), definition.pattern)
	return {
		"success": true,
		"errors": [],
		"registered": {
			"blocks": blocks.map(func(value: Dictionary) -> String: return str(value.id)),
			"items": items.map(func(value: Dictionary) -> String: return str(value.id)),
			"recipes": recipes.map(func(value: Dictionary) -> String: return str(value.id)),
		},
	}


func _stage(api: Variant, data: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not data is Dictionary or int(data.get("schema_version", 0)) != 1:
		return {"success": false, "errors": ["Expected schema_version: 1."]}
	for section in ["blocks", "items", "recipes"]:
		if not data.get(section, []) is Array:
			errors.append("%s must be an array." % section)
	if not errors.is_empty():
		return {"success": false, "errors": errors}
	var block_rows: Array = data.get("blocks", [])
	var item_rows: Array = data.get("items", [])
	var recipe_rows: Array = data.get("recipes", [])
	if block_rows.size() > MAX_BLOCKS or item_rows.size() > MAX_ITEMS or recipe_rows.size() > MAX_RECIPES:
		errors.append("Pack exceeds the schema-v1 definition limits.")
	if not errors.is_empty():
		return {"success": false, "errors": errors}

	var blocks: Array[Dictionary] = []
	var items: Array[Dictionary] = []
	var recipes: Array[Dictionary] = []
	var seen_blocks := {}
	var seen_items := {}
	var seen_recipes := {}
	for value in block_rows:
		if not value is Dictionary:
			errors.append("Each block must be an object.")
			continue
		var error_count := errors.size()
		var definition: Dictionary = value.duplicate(true)
		var id := str(definition.get("id", ""))
		if not _valid_id(id):
			errors.append("Invalid block ID: %s" % id)
			continue
		if api.content.has_block(id) or seen_blocks.has(id):
			errors.append("Block already exists: %s" % id)
		seen_blocks[id] = true
		if not _finite_number(definition.get("hardness", 1.0)) or float(definition.get("hardness", 1.0)) < 0.0:
			errors.append("Block %s has invalid hardness." % id)
		if not _valid_string_array(definition.get("tags", ["block"])):
			errors.append("Block %s has invalid tags." % id)
		if not _valid_drops(definition.get("drops", [{"item": id, "count": 1}])):
			errors.append("Block %s has invalid drops." % id)
		var tint: Color = _tint(definition.get("tint", [1.0, 1.0, 1.0, 1.0]), errors, id)
		var texture_rows: Variant = definition.get("textures", {})
		if not texture_rows is Dictionary or str(texture_rows.get("side", "")).is_empty():
			errors.append("Block %s needs textures.side." % id)
			continue
		var textures: Dictionary = {}
		for face in ["side", "top", "bottom", "front"]:
			if face == "side" or texture_rows.has(face):
				var texture_path := str(texture_rows.get(face, ""))
				var loaded := _load_texture(api, texture_path)
				if loaded == null:
					errors.append("Block %s texture %s is missing or not an image: %s" % [id, face, texture_path])
				else:
					textures[face] = loaded
		var model := _cube_model(api, textures, tint, bool(definition.get("transparent", false)), id, errors)
		definition["model"] = model
		definition["id"] = id
		definition["tags"] = definition.get("tags", ["block"])
		definition["drops"] = definition.get("drops", [{"item": id, "count": 1}])
		if errors.size() > error_count:
			continue
		blocks.append(definition)

	for value in item_rows:
		if not value is Dictionary:
			errors.append("Each item must be an object.")
			continue
		var error_count := errors.size()
		var definition: Dictionary = value.duplicate(true)
		var id := str(definition.get("id", ""))
		if not _valid_id(id):
			errors.append("Invalid item ID: %s" % id)
			continue
		if seen_items.has(id) or (api.content.has_item(id) and not blocks.any(func(block: Dictionary) -> bool: return str(block.id) == id)):
			errors.append("Item already exists: %s" % id)
		seen_items[id] = true
		var stack_size: Variant = definition.get("stack_size", 64)
		if not (stack_size is int or stack_size is float) or not _finite_number(stack_size) or int(stack_size) < 1 or int(stack_size) > 9999:
			errors.append("Item %s stack_size must be from 1 to 9999." % id)
		if not _valid_string_array(definition.get("tags", [])):
			errors.append("Item %s has invalid tags." % id)
		if not definition.get("properties", {}) is Dictionary:
			errors.append("Item %s properties must be an object." % id)
		var icon_path := str(definition.get("icon", ""))
		if not icon_path.is_empty():
			var icon := _load_texture(api, icon_path)
			if icon == null:
				errors.append("Item %s icon is missing or not an image: %s" % [id, icon_path])
			else:
				definition["icon"] = icon
		definition["id"] = id
		if errors.size() > error_count:
			continue
		items.append(definition)

	var trial := _copy_registry(api.content)
	for definition in blocks:
		if trial.register_block(definition) < 0:
			errors.append("Block preflight failed: %s" % definition.id)
	for definition in items:
		if not trial.register_item(definition):
			errors.append("Item preflight failed: %s" % definition.id)
	for definition in blocks:
		for drop in definition.get("drops", []):
			if not trial.has_item(str(drop.get("item", ""))):
				errors.append("Block %s drops an unknown item." % definition.id)

	for value in recipe_rows:
		if not value is Dictionary:
			errors.append("Each recipe must be an object.")
			continue
		var error_count := errors.size()
		var definition: Dictionary = value.duplicate(true)
		var id := str(definition.get("id", ""))
		var output := str(definition.get("output", ""))
		var count: Variant = definition.get("count", 1)
		var ingredients: Variant = definition.get("ingredients", {})
		if not _valid_id(id) or trial.recipes.has(id) or seen_recipes.has(id):
			errors.append("Invalid or duplicate recipe ID: %s" % id)
		seen_recipes[id] = true
		if not (count is int or count is float) or not _finite_number(count) or int(count) < 1 or int(count) > 9999:
			errors.append("Recipe %s has invalid output count." % id)
		if not ingredients is Dictionary or ingredients.is_empty():
			errors.append("Recipe %s needs ingredient counts." % id)
			continue
		var options := {
			"station": str(definition.get("station", "hand")),
			"method": str(definition.get("method", "craft")),
			"duration": definition.get("duration", 0.0),
		}
		if not _finite_number(options.duration) or float(options.duration) < 0.0:
			errors.append("Recipe %s has invalid duration." % id)
		var ingredient_values: Dictionary = {}
		for selector in ingredients:
			var selector_id := str(selector)
			var amount: Variant = ingredients[selector]
			if not _valid_selector(trial, selector_id) or not (amount is int or amount is float) or not _finite_number(amount) or int(amount) < 1:
				errors.append("Recipe %s has invalid ingredient selector/count: %s" % [id, selector_id])
			else:
				ingredient_values[selector_id] = int(amount)
		if not trial.has_item(output):
			errors.append("Recipe %s references unknown output item %s." % [id, output])
		if definition.has("pattern"):
			if api.crafting == null or api.crafting.grid_service == null:
				errors.append("Recipe %s has a pattern but crafting:shaped is unavailable." % id)
			elif not _valid_pattern(definition.pattern, trial):
				errors.append("Recipe %s has an invalid pattern." % id)
		if errors.size() > error_count:
			continue
		if trial.register_recipe(id, output, int(count), ingredient_values, options):
			if definition.has("pattern"):
				definition["pattern"] = _normalize_pattern(definition.pattern)
			definition["options"] = options
			recipes.append(definition)
		else:
			errors.append("Recipe preflight failed: %s" % id)

	if not errors.is_empty():
		return {"success": false, "errors": errors}
	return {"success": true, "errors": [], "blocks": blocks, "items": items, "recipes": recipes}


func _copy_registry(source: ContentRegistry) -> ContentRegistry:
	var copy := ContentRegistry.new()
	copy.blocks = source.blocks.duplicate()
	copy.items = source.items.duplicate()
	copy.recipes = source.recipes.duplicate()
	copy._voxel_ids = source._voxel_ids.duplicate()
	copy._used_voxel_ids = source._used_voxel_ids.duplicate()
	copy._voxel_to_block = source._voxel_to_block.duplicate()
	copy._auto_generated_items = source._auto_generated_items.duplicate()
	return copy


func _valid_id(value: String) -> bool:
	var parts := value.split(":", false)
	if parts.size() != 2:
		return false
	for part in parts:
		if part.is_empty():
			return false
		for character in part:
			if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") and character not in ["_", "-", "."]:
				return false
	return true


func _valid_string_array(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry in value:
		if not entry is String or str(entry).is_empty():
			return false
	return true


func _valid_drops(value: Variant) -> bool:
	if not value is Array:
		return false
	for drop in value:
		if not drop is Dictionary or not _valid_id(str(drop.get("item", ""))) or int(drop.get("count", 1)) < 1:
			return false
	return true


func _valid_selector(registry: ContentRegistry, selector: String) -> bool:
	if selector.begins_with("#"):
		return not registry.get_item_ids_with_tag(selector.substr(1)).is_empty()
	return registry.has_item(selector)


func _valid_pattern(value: Variant, registry: ContentRegistry) -> bool:
	if not value is Array or value.is_empty() or value.size() > 16:
		return false
	var width := -1
	for row in value:
		if not row is Array or row.is_empty() or row.size() > 16:
			return false
		if width < 0:
			width = row.size()
		elif width != row.size():
			return false
		for cell in row:
			if not cell is String or (not str(cell).is_empty() and not _valid_selector(registry, str(cell))):
				return false
	return true


func _normalize_pattern(value: Array) -> Array:
	var result: Array = []
	for row in value:
		var cells: Array[String] = []
		for cell in row:
			cells.append(str(cell))
		result.append(cells)
	return result


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _tint(value: Variant, errors: Array[String], id: String) -> Color:
	if not value is Array or value.size() not in [3, 4]:
		errors.append("Block %s tint must have three or four components." % id)
		return Color.WHITE
	for component in value:
		if not _finite_number(component) or float(component) < 0.0 or float(component) > 1.0:
			errors.append("Block %s tint components must be from 0 to 1." % id)
			return Color.WHITE
	return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]) if value.size() == 4 else 1.0)


func _load_texture(api: Variant, path: String) -> Texture2D:
	if path.is_empty():
		return null
	var resource_path: String = str(api.asset(path))
	if not ResourceLoader.exists(resource_path):
		return null
	var texture: Texture2D = ResourceLoader.load(resource_path) as Texture2D
	return texture


func _cube_model(api: Variant, textures: Dictionary, tint: Color, transparent: bool, id: String, errors: Array[String]) -> VoxelBlockyModelCube:
	var world_adapter: VoxelWorldService = api.world as VoxelWorldService
	if world_adapter == null:
		errors.append("Block %s cannot be built without the voxel world adapter." % id)
		return null
	var model: VoxelBlockyModelCube = world_adapter.build_cube_model(textures, tint, transparent)
	if model == null:
		errors.append("Block %s face textures are invalid or have different sizes." % id)
	return model
