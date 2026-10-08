# Content pack schema v1

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
