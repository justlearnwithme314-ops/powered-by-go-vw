class_name ContentSnapshot
extends RefCounted

## Read-only runtime view of content used by worker-thread world generation.
##
## It intentionally contains plain data only. It never calls SceneTree,
## GameAPI, VoxelTerrain, or any other main-thread-only system.

var blocks: Dictionary = {}
var items: Dictionary = {}
var recipes: Dictionary = {}
var _block_to_voxel: Dictionary = {}
var _voxel_to_block: Dictionary = {}


func from_registry(registry: ContentRegistry) -> ContentSnapshot:
	blocks = {}
	for block_id in registry.blocks:
		var source: Dictionary = registry.blocks[block_id]
		blocks[str(block_id)] = {
			"id": str(block_id),
			"voxel_id": int(source.get("voxel_id", 0)),
			"display_name": str(source.get("display_name", "")),
			"solid": bool(source.get("solid", true)),
			"transparent": bool(source.get("transparent", false)),
			"hardness": float(source.get("hardness", 1.0)),
			"tags": source.get("tags", []).duplicate(true),
		}

	items = {}
	for item_id in registry.items:
		var item_source: Dictionary = registry.items[item_id]
		items[str(item_id)] = {
			"id": str(item_id),
			"display_name": str(item_source.get("display_name", "")),
			"stack_size": int(item_source.get("stack_size", 64)),
			"place_block": str(item_source.get("place_block", "")),
			"tags": item_source.get("tags", []).duplicate(true),
			"properties": item_source.get("properties", {}).duplicate(true),
		}

	recipes = registry.recipes.duplicate(true)
	_block_to_voxel = {}
	_voxel_to_block = {}

	for block_id in blocks:
		var voxel_id := int(blocks[block_id].get("voxel_id", 0))
		_block_to_voxel[str(block_id)] = voxel_id
		_voxel_to_block[voxel_id] = str(block_id)

	return self


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


func get_voxel_id(block_id: String) -> int:
	return int(_block_to_voxel.get(block_id, 0))


func get_block_id_from_voxel(voxel_id: int) -> String:
	return str(_voxel_to_block.get(voxel_id, ContentRegistry.AIR_ID))
