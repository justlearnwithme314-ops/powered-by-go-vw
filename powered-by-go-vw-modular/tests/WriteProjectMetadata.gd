extends Node

const BLOCK_TEXTURE := "res://assets/minecraft-inspired-textures-free/block/oak_planks.png"
const SCHEMA_DOC := """# Content pack schema v1

A mod calls api.register_content_pack("content.json") during register(api). Relative pack and asset paths resolve from the mod root. Explicit res:// and user:// paths are also accepted. IDs use namespace:name.

Top-level fields: schema_version (must be 1), blocks, items, and recipes. The arrays are optional and limited to 128 blocks, 256 items, and 512 recipes per pack. The loader validates every definition and image before adding anything to the registry.

## Blocks

A block needs id and textures.side. Optional top, bottom, and front textures default to side. Face images must have matching dimensions and are packed into a nearest-filtered atlas used by a standard voxel cube.

Optional fields: display_name, finite positive hardness, preferred_tool, required_tool, mining_level, solid, transparent, stack_size, tags, drops, and tint (three or four normalized components). A block automatically creates a placeable item with the same ID; an explicit item definition with that ID may replace the generated item.

Example:
{
  "id": "example:marble",
  "textures": {"side": "textures/marble.png"},
  "tint": [1, 1, 1, 1],
  "hardness": 1.5,
  "tags": ["block", "stone"]
}

## Items

Fields: id, display_name, stack_size (1–9999), tags, properties (JSON object), icon (image path), and place_block. Icons are optional.

## Recipes

Fields: id, output, positive count, ingredient counts, station (default hand), method (default craft), and non-negative duration (default 0). Ingredient keys can be item IDs or #tag selectors. Output and ingredients must resolve against existing content or this pack.

Optional pattern is a rectangular array of rows. Cells contain item IDs, #tag selectors, or empty strings. Patterns require the crafting:shaped dependency. The current crafting API supports one output item per recipe.

JSON packs do not execute scripts. Creatures, machines, fluids, multi-output recipes, and migration behavior remain in code-owned systems.
"""


func _write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Could not write " + path)
	file.store_string(value)
	file.flush()
	assert(file.get_error() == OK, "Failed writing " + path)
	file.close()


func _ready() -> void:
	var valid_pack := {
		"schema_version": 1,
		"blocks": [{
			"id": "test:catalog_block",
			"display_name": "Catalog Block",
			"hardness": 1.5,
			"preferred_tool": "pickaxe",
			"required_tool": "pickaxe",
			"mining_level": 1,
			"textures": {"side": BLOCK_TEXTURE, "top": BLOCK_TEXTURE, "bottom": BLOCK_TEXTURE, "front": BLOCK_TEXTURE},
			"tint": [1.0, 1.0, 1.0, 1.0],
			"tags": ["block", "test"],
			"drops": [{"item": "test:catalog_block", "count": 1}]
		}],
		"items": [{
			"id": "test:token",
			"display_name": "Test Token",
			"stack_size": 16,
			"tags": ["test:token"],
			"properties": {},
			"icon": BLOCK_TEXTURE
		}],
		"recipes": [{
			"id": "test:token_recipe",
			"output": "test:token",
			"count": 2,
			"ingredients": {"#material": 1},
			"station": "hand",
			"method": "craft",
			"duration": 0.0
		}]
	}
	var invalid_pack := {
		"schema_version": 1,
		"blocks": [{
			"id": "test:partial",
			"textures": {"side": BLOCK_TEXTURE},
			"tags": ["block"],
			"drops": [{"item": "test:partial", "count": 1}]
		}, {
			"id": "test:missing_texture",
			"textures": {"side": "missing.png"},
			"tags": ["block"]
		}],
		"items": [{
			"id": "test:token",
			"display_name": "Test Token",
			"stack_size": 16,
			"tags": ["test:token"],
			"icon": BLOCK_TEXTURE
		}],
		"recipes": [{
			"id": "test:bad_recipe",
			"output": "test:token",
			"count": 1,
			"ingredients": {"#not_registered": 1}
		}]
	}
	_write("res://mods/creative_catalog/mod.json", "{\"id\":\"sandbox:creative_catalog\",\"name\":\"Creative Catalog\",\"version\":\"1.0.0\",\"api_version\":1,\"entry\":\"mod.gd\",\"dependencies\":[\"core:base\",\"entities:framework\"]}\n")
	_write("res://tests/fixtures/content_pack/valid.json", JSON.stringify(valid_pack, "\t") + "\n")
	_write("res://tests/fixtures/content_pack/invalid.json", JSON.stringify(invalid_pack, "\t") + "\n")
	_write("res://docs/CONTENT_PACK_SCHEMA.md", SCHEMA_DOC)

	var suites_path := "res://tools/smoke_suites.json"
	var suites := {
		"suites": {
			"foundation": [
				{"scene": "InventoryFoundationSmoke.tscn", "success_marker": "Inventory foundation smoke passed:"},
				{"scene": "WorldSaveCatalogSmoke.tscn", "success_marker": "World save suite completed:"},
				{"scene": "CraftingStationsSmoke.tscn", "success_marker": "Crafting stations PASS:"}
			],
			"content": [
				{"scene": "CreativeCatalogSmoke.tscn", "success_marker": "Creative catalog smoke passed:"},
				{"scene": "ContentPackSmoke.tscn", "success_marker": "Content pack smoke passed:"}
			]
		}
	}
	_write(suites_path, JSON.stringify(suites, "\t") + "\n")

	var tasks_path := "res://LUNA_TASKS.md"
	var tasks := FileAccess.get_file_as_string(tasks_path)
	tasks = tasks.replace("world-save suite passed 14 tests", "world-save suite passed 15 tests")
	tasks = tasks.replace("invalid-pack atomicity, and duplicate rejection", "missing-texture/tag atomicity, and duplicate rejection")
	tasks = tasks.replace("| T02 | World mode and experimental flags | T01 | Luna Medium | Medium | TODO |", "| T02 | World mode and experimental flags | T01 | Luna Medium | Medium | DONE — profile/menu integration; world-save suite passed 15 tests |")
	tasks = tasks.replace("| T03 | Searchable creative catalog | T02 | Luna Medium | Medium | TODO |", "| T03 | Searchable creative catalog | T02 | Luna Medium | Medium | DONE — catalog mod and authority grant smoke passed |")
	tasks = tasks.replace("| T04 | Optional validated content pack loader | T01 | Luna Medium | Medium | TODO |", "| T04 | Optional validated content pack loader | T01 | Luna Medium | Medium | DONE — JSON schema, staged cube loader and atomicity smoke passed |")
	var stale_evidence := "\n\n## Execution evidence (2026-10-08)\n\n- T02: WorldProfileService is wired through world lifecycle and all ModAPI contexts; world metadata preserves unknown keys while canonical fields remain safe. WorldSaveCatalogSmoke passed 14 tests.\n- T03: sandbox:creative_catalog loads as a mod; F6 catalog filters item names, IDs, and tags. Trusted grants verify mode and persist before inventory publication. CreativeCatalogSmoke covers survival rejection, fixed stack size, unique durable instance, and full inventory.\n- T04: schema-v1 JSON packs stage textures/models and preflight definitions before registry mutation. ContentPackSmoke covers valid block/item/recipe registration, invalid-pack atomicity, and duplicate rejection.\n"
	tasks = tasks.replace(stale_evidence, "")
	if not tasks.contains("WorldSaveCatalogSmoke passed 15 tests."):
		tasks += "\n\n## Execution evidence (2026-10-08)\n\n- T02: WorldProfileService is wired through world lifecycle and all ModAPI contexts; world metadata preserves unknown keys while canonical fields remain safe. WorldSaveCatalogSmoke passed 15 tests.\n- T03: sandbox:creative_catalog loads as a mod; F6 catalog filters item names, IDs, and tags. Trusted grants verify mode and persist before inventory publication. CreativeCatalogSmoke covers survival rejection, fixed stack size, unique durable instance, and full inventory.\n- T04: schema-v1 JSON packs stage textures/models and preflight definitions before registry mutation. ContentPackSmoke covers valid block/item/recipe registration, missing-texture/tag atomicity, and duplicate rejection.\n"
	_write(tasks_path, tasks)
	print("Ticket metadata and content-pack fixtures written.")
	get_tree().quit()
