# Expandable shaped crafting

Open inventory with E or right-click a workbench. Pick up stacks with left
click, drag them into grid slots, and right-click to place one per slot. The
result list contains only outputs matching the current arrangement; click a
result to consume one ingredient per occupied cell and craft into inventory.
If the inventory has no output space, ingredients remain unchanged.

Without a nearby workbench: 2x2. One workbench within three blocks: 3x3.
The arrangement of edge-connected workbenches on the same level determines
the grid: a two-table row gives 6x3, a 2x2 square gives 6x6, and a 3x2
rectangle gives 9x6. Each block of the tabletop footprint maps to 3x3 slots.
The longer dimension becomes the grid width, so rotated rows behave alike.
Irregular connected shapes use their rectangular bounds. Stacked tables
and disconnected tables do not enlarge this tabletop.
There is no fixed maximum crafting dimension; large grids scroll. Connected
tables must be in loaded terrain. Disconnected benches do not expand the grid.
Changing dimensions returns existing ingredients before rebuilding the grid.

Patterns trim empty borders and allow horizontal mirrors. Initial shapes:
workbench (2x2 planks), furnace (stone ring), sticks (two vertically stacked
planks), pickaxes, axes, shovels, swords, helmets, chestplates, leggings, boots.
Wood tools use planks. Existing game metal tiers are retained. Other recipes
use shapeless ingredient matching; several valid outputs may be listed.

All five plank variants carry the `core:planks` tag on both block and item.
Plank ingredient recipes use `#core:planks`, allowing mixed species in a shape.
For other groups, add a namespaced tag to item definitions (block auto-items
inherit block tags), then use `{"#your_mod:material": 3}` as recipe ingredients
or `"#your_mod:material"` in custom pattern cells. Explicit replacement items
must also retain the tag. Items keep their own textures and stack identities.
Only tag selectors allow substitution; ordinary item IDs still match exactly.
Tag-aware shapeless allocation handles overlapping groups without double use.

To add larger patterns, register a normal recipe with its ingredient totals,
then call `api.crafting.grid_service.register_pattern(recipe_id, rows)`.
Rows are equally sized arrays of logical item IDs, using "" for empty cells.
Example: a five-wide recipe can require two or more connected workbenches.

Grid edits/crafts route through InventoryCommandService, including server
authority in multiplayer. Grid stacks live in the inventory snapshot; closing
returns them to inventory, with overflow in the existing Recover list. Normal
save reload also recovers grid stacks rather than losing ingredients.

Furnaces retain their separate input/fuel/output interface, processing delay,
and saved contents. Smelting recipes never match the crafting grid.
