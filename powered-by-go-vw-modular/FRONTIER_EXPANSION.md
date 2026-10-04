# Frontier Survival Expansion — integrated build

This build adds `mods/frontier_survival` and two small core hooks.

Gameplay:
- Hunger survival loop with food consumption.
- Stamina + Shift sprinting.
- Hunger-based movement penalties and poison mushroom effect.
- Starter inventory appropriate for progression.
- Wood/stone/bronze/steel/mese/diamond/murexium tool tiers.
- Copper/tin/silver/mese/murexium ores and refined materials.
- Rare deep obsidian vaults with mese and murexium.
- Climate-driven biome surface variants.
- Additional building blocks.
- Texture-backed inventory and crafting icons.

Core hooks:
- `InventoryUI.gd` reads optional `item["icon"]` paths.
- `PlayerController.gd` makes the prototype debug inventory opt-in.
- `VoxelInteractor.gd` lets ITEM_USE handlers consume items without a voxel target.

Controls:
- Shift: sprint.
- Right click: eat food while a food item is selected.
- E: inventory.
- Mouse wheel / 1–8: hotbar.

The existing player model was left unchanged because it is already voxel/block-based and changing it was not necessary for the gameplay expansion.

Validation:
- Texture/model/icon paths checked.
- Standalone mod structure checked.
- Godot runtime validation was not possible in this sandbox because the Godot executable is not installed.
