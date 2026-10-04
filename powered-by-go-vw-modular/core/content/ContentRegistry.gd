class_name ContentRegistry
extends RefCounted

## Authoritative startup registry for game content.
##
## Public IDs are namespaced strings: "core:stone", "my_mod:copper_ore".
## Zylann voxel integers are allocated internally and never exposed as a
## requirement to mod authors.

const AIR_ID := "core:air"
const ID_MAP_PATH := "user://content/voxel_ids.json"
const MAX_VOXELS := 65535

var blocks: Dictionary = {}
var items: Dictionary = {}
var recipes: Dictionary = {}

var _voxel_ids: Dictionary = {}
var _used_voxel_ids: Dictionary = {}
var _voxel_to_block: Dictionary = {}
var _finalized := false
var _auto_generated_items: Dictionary = {}


func _init() -> void:
	_load_voxel_id_map()


func is_finalized() -> bool:
	return _finalized


# ------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------

func _can_register(kind: String) -> bool:
	if _finalized:
		push_error(
			"[ContentRegistry] Cannot register %s after content finalization."
			% kind
		)
		return false
	return true


func _validate_id(content_id: String) -> bool:
	if content_id.is_empty() or not content_id.contains(":"):
		push_error(
			"[ContentRegistry] '%s' is invalid. Use namespace:name."
			% content_id
		)
		return false

	var parts := content_id.split(":", false)
	if parts.size() != 2 or parts[0].is_empty() or parts[1].is_empty():
		push_error(
			"[ContentRegistry] '%s' is invalid. Use namespace:name."
			% content_id
		)
		return false

	return true


# ------------------------------------------------------------------
# Blocks
# ------------------------------------------------------------------

func register_block(definition: Dictionary) -> int:
	if not _can_register("blocks"):
		return -1

	var content_id := str(definition.get("id", ""))
	if not _validate_id(content_id):
		return -1

	if blocks.has(content_id):
		push_error("[ContentRegistry] Duplicate block: %s" % content_id)
		return -1

	var model := definition.get("model") as VoxelBlockyModel
	if model == null:
		push_error(
			"[ContentRegistry] Block '%s' has no VoxelBlockyModel."
			% content_id
		)
		return -1

	var preferred_id := int(definition.get("voxel_id", -1))
	var voxel_id := _allocate_voxel_id(content_id, preferred_id)
	if voxel_id < 0:
		return -1

	var block := definition.duplicate(true)
	block["id"] = content_id
	block["voxel_id"] = voxel_id
	block["display_name"] = str(
		block.get("display_name", content_id.get_slice(":", 1).capitalize())
	)
	block["solid"] = bool(block.get("solid", true))
	block["transparent"] = bool(block.get("transparent", false))
	block["hardness"] = float(block.get("hardness", 1.0))
	block["drops"] = block.get(
		"drops",
		[{"item": content_id, "count": 1}]
	)
	block["tags"] = block.get("tags", ["block"])

	blocks[content_id] = block
	_voxel_to_block[voxel_id] = content_id

	# A placeable block automatically gets a basic item. An explicit item with
	# the same ID can replace this generated item later in startup, which keeps
	# mod registration order flexible and AI-friendly.
	if content_id != AIR_ID and not items.has(content_id):
		register_item({
			"id": content_id,
			"display_name": block["display_name"],
			"stack_size": int(block.get("stack_size", 64)),
			"place_block": content_id,
			"tags": block.get("tags", ["block"]),
			"_auto_generated": true,
		})

	return voxel_id


# ------------------------------------------------------------------
# Items
# ------------------------------------------------------------------

func register_item(definition: Dictionary) -> bool:
	if not _can_register("items"):
		return false

	var content_id := str(definition.get("id", ""))
	if not _validate_id(content_id):
		return false

	if items.has(content_id):
		if _auto_generated_items.has(content_id):
			items.erase(content_id)
			_auto_generated_items.erase(content_id)
		else:
			push_error("[ContentRegistry] Duplicate item: %s" % content_id)
			return false

	var item := definition.duplicate(true)
	item["id"] = content_id
	item["display_name"] = str(
		item.get("display_name", content_id.get_slice(":", 1).capitalize())
	)
	item["stack_size"] = maxi(int(item.get("stack_size", 64)), 1)
	item["tags"] = item.get("tags", [])
	item["properties"] = item.get("properties", {})
	item["place_block"] = str(item.get("place_block", ""))
	var auto_generated := bool(item.get("_auto_generated", false))
	item.erase("_auto_generated")

	items[content_id] = item
	if auto_generated:
		_auto_generated_items[content_id] = true
	else:
		_auto_generated_items.erase(content_id)
	return true


# ------------------------------------------------------------------
# Recipes
# ------------------------------------------------------------------

func register_recipe(
	recipe_id: String,
	output_id: String,
	output_count: int,
	ingredients: Dictionary
) -> bool:
	if not _can_register("recipes"):
		return false
	if not _validate_id(recipe_id):
		return false
	if not _validate_id(output_id) or not items.has(output_id):
		push_error(
			"[ContentRegistry] Recipe '%s' outputs unknown item '%s'."
			% [recipe_id, output_id]
		)
		return false
	if recipes.has(recipe_id):
		push_error("[ContentRegistry] Duplicate recipe: %s" % recipe_id)
		return false

	var normalized_ingredients: Dictionary = {}
	for item_id in ingredients:
		var item_key := str(item_id)
		var amount := int(ingredients[item_id])
		if amount <= 0 or not items.has(item_key):
			push_error(
				"[ContentRegistry] Recipe '%s' has invalid ingredient '%s'."
				% [recipe_id, item_key]
			)
			return false
		normalized_ingredients[item_key] = amount

	recipes[recipe_id] = {
		"id": recipe_id,
		"output": output_id,
		"count": maxi(output_count, 1),
		"ingredients": normalized_ingredients,
	}
	return true


# ------------------------------------------------------------------
# Queries
# ------------------------------------------------------------------

func has_block(block_id: String) -> bool:
	return blocks.has(block_id)


func has_item(item_id: String) -> bool:
	return items.has(item_id)


func get_block(block_id: String) -> Dictionary:
	return blocks.get(block_id, {})


func get_item(item_id: String) -> Dictionary:
	return items.get(item_id, {})


func get_recipe(recipe_id: String) -> Dictionary:
	return recipes.get(recipe_id, {})


func get_block_ids() -> Array[String]:
	var result: Array[String] = []
	for block_id in blocks:
		result.append(str(block_id))
	result.sort()
	return result


func get_item_ids() -> Array[String]:
	var result: Array[String] = []
	for item_id in items:
		result.append(str(item_id))
	result.sort()
	return result


func get_recipe_ids() -> Array[String]:
	var result: Array[String] = []
	for recipe_id in recipes:
		result.append(str(recipe_id))
	result.sort()
	return result


func get_block_ids_with_tag(tag: String) -> Array[String]:
	var result: Array[String] = []
	for block_id in blocks:
		if tag in blocks[block_id].get("tags", []):
			result.append(str(block_id))
	result.sort()
	return result


func get_item_ids_with_tag(tag: String) -> Array[String]:
	var result: Array[String] = []
	for item_id in items:
		if tag in items[item_id].get("tags", []):
			result.append(str(item_id))
	result.sort()
	return result


func get_item_display_name(item_id: String) -> String:
	var item := get_item(item_id)
	return str(item.get("display_name", "Unknown")) if not item.is_empty() else "Unknown"


func get_block_display_name(block_id: String) -> String:
	var block := get_block(block_id)
	return str(block.get("display_name", "Unknown")) if not block.is_empty() else "Unknown"


func get_voxel_id(block_id: String) -> int:
	return int(_voxel_ids.get(block_id, 0))


func get_block_id_from_voxel(voxel_id: int) -> String:
	return str(_voxel_to_block.get(voxel_id, AIR_ID))


func get_placement_block(item_id: String) -> String:
	return str(get_item(item_id).get("place_block", ""))


func get_break_hits(item_id: String, block_id: String) -> int:
	var block := get_block(block_id)
	if block.is_empty():
		return 999999

	var hardness := maxf(float(block.get("hardness", 1.0)), 0.1)
	var item := get_item(item_id)
	var properties: Dictionary = item.get("properties", {})
	var power := maxf(float(properties.get("break_power", 1.0)), 0.1)
	return maxi(ceili(hardness / power), 1)


# ------------------------------------------------------------------
# Zylann adapter
# ------------------------------------------------------------------

func build_voxel_library() -> VoxelBlockyLibrary:
	## VoxelBlockyLibrary is an array-backed ID system. Holes are kept as
	## VoxelBlockyModelEmpty so removing a mod does not shift other IDs.
	var max_id := 0
	for block_id in blocks:
		max_id = maxi(max_id, int(blocks[block_id]["voxel_id"]))
	max_id = mini(max_id, MAX_VOXELS)

	var models: Array = []
	models.resize(max_id + 1)
	for i in range(models.size()):
		models[i] = VoxelBlockyModelEmpty.new()

	for block_id in blocks:
		var voxel_id := int(blocks[block_id]["voxel_id"])
		if voxel_id >= 0 and voxel_id < models.size():
			models[voxel_id] = blocks[block_id]["model"]

	var library := VoxelBlockyLibrary.new()
	library.set_models(models)
	return library


# ------------------------------------------------------------------
# Runtime snapshot for worker threads
# ------------------------------------------------------------------

func create_snapshot() -> ContentSnapshot:
	return ContentSnapshot.new().from_registry(self)


# ------------------------------------------------------------------
# Stable voxel ID persistence
# ------------------------------------------------------------------

func _allocate_voxel_id(content_id: String, preferred_id: int) -> int:
	if _voxel_ids.has(content_id):
		var existing := int(_voxel_ids[content_id])
		if existing < 0 or existing > MAX_VOXELS:
			push_error("[ContentRegistry] Invalid stored voxel ID for %s." % content_id)
			return -1
		if _used_voxel_ids.has(existing) and str(_used_voxel_ids[existing]) != content_id:
			push_error(
				"[ContentRegistry] Stored voxel ID conflict: %d is used by '%s'."
				% [existing, _used_voxel_ids[existing]]
			)
			return -1
		_used_voxel_ids[existing] = content_id
		return existing

	if preferred_id >= 0:
		if preferred_id > MAX_VOXELS:
			push_error(
				"[ContentRegistry] Preferred voxel ID out of range: %d"
				% preferred_id
			)
			return -1
		if _used_voxel_ids.has(preferred_id):
			push_error(
				"[ContentRegistry] Preferred voxel ID %d is already used by '%s'."
				% [preferred_id, _used_voxel_ids[preferred_id]]
			)
			return -1

		_voxel_ids[content_id] = preferred_id
		_used_voxel_ids[preferred_id] = content_id
		return preferred_id

	var candidate := 1
	while _used_voxel_ids.has(candidate):
		candidate += 1
		if candidate > MAX_VOXELS:
			push_error("[ContentRegistry] No free voxel IDs remain.")
			return -1

	_voxel_ids[content_id] = candidate
	_used_voxel_ids[candidate] = content_id
	return candidate


func _load_voxel_id_map() -> void:
	if not FileAccess.file_exists(ID_MAP_PATH):
		return

	var file := FileAccess.open(ID_MAP_PATH, FileAccess.READ)
	if file == null:
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return

	for content_id in parsed:
		var voxel_id := int(parsed[content_id])
		if voxel_id < 0 or voxel_id > MAX_VOXELS:
			continue
		if _used_voxel_ids.has(voxel_id):
			continue
		_voxel_ids[str(content_id)] = voxel_id
		_used_voxel_ids[voxel_id] = str(content_id)


func save_voxel_id_map() -> void:
	DirAccess.make_dir_recursive_absolute("user://content")
	var file := FileAccess.open(ID_MAP_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_voxel_ids, "\t"))


# ------------------------------------------------------------------
# Finalization / compatibility
# ------------------------------------------------------------------

func finalize() -> void:
	if _finalized:
		return
	if not _validate_references():
		push_error("[ContentRegistry] Content validation failed; see errors above.")
	_finalized = true
	save_voxel_id_map()


func _validate_references() -> bool:
	var valid := true

	for block_id in blocks:
		var block: Dictionary = blocks[block_id]
		for drop in block.get("drops", []):
			if not drop is Dictionary:
				push_error("[ContentRegistry] Block '%s' has a malformed drop entry." % block_id)
				valid = false
				continue
			var drop_item := str(drop.get("item", ""))
			if not items.has(drop_item):
				push_error(
					"[ContentRegistry] Block '%s' drops unknown item '%s'."
					% [block_id, drop_item]
				)
				valid = false

	for item_id in items:
		var item: Dictionary = items[item_id]
		var place_block := str(item.get("place_block", ""))
		if not place_block.is_empty() and not blocks.has(place_block):
			push_error(
				"[ContentRegistry] Item '%s' places unknown block '%s'."
				% [item_id, place_block]
			)
			valid = false

	return valid


func get_content_signature() -> String:
	var entries: Array[String] = []

	for block_id in blocks.keys():
		var block: Dictionary = blocks[block_id]
		entries.append(
			"block|%s|%d|%s|%s|%s|%s|%s|%s"
			% [
				block_id,
				int(block.get("voxel_id", 0)),
				str(block.get("display_name", "")),
				str(block.get("hardness", 1.0)),
				str(block.get("solid", true)),
				str(block.get("transparent", false)),
				JSON.stringify(block.get("tags", [])),
				JSON.stringify(block.get("drops", [])),
			]
		)

	for item_id in items.keys():
		var item: Dictionary = items[item_id]
		entries.append(
			"item|%s|%s|%d|%s|%s"
			% [
				item_id,
				str(item.get("display_name", "")),
				int(item.get("stack_size", 64)),
				str(item.get("place_block", "")),
				JSON.stringify(item.get("properties", {})),
			]
		)

	for recipe_id in recipes.keys():
		var recipe: Dictionary = recipes[recipe_id]
		entries.append(
			"recipe|%s|%s|%d|%s"
			% [
				recipe_id,
				str(recipe["output"]),
				int(recipe["count"]),
				JSON.stringify(recipe["ingredients"]),
			]
		)

	entries.sort()
	return JSON.stringify(entries)
