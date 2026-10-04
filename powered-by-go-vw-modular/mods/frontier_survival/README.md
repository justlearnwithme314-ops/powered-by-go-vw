# Frontier Survival Expansion

A content-heavy gameplay expansion for Powered by GO-VW.

## Gameplay
- Hunger meter and food consumption with right-click.
- Stamina meter and Shift sprinting.
- Starvation/exhaustion movement penalties.
- Poison mushroom risk.
- Starter survival loadout replaces the prototype debug inventory.
- Seven tool/material tiers: wood, stone, bronze, steel, mese, diamond, murexium.
- Copper, tin, silver, mese and murexium underground ores.
- New metal blocks and a building-material palette.
- Climate-driven surface variants using supplied biome textures.
- Rare deep obsidian vaults containing mese and murexium.
- Texture-backed inventory/crafting icons.

## Asset strategy
The supplied texture packs are copied into this mod and normalized to safe filenames.
The block resources use `VoxelBlockyModelCube` with pixel-texture materials.

## Important
The expansion uses only the existing v1 public mod API plus two small core presentation hooks:
1. inventory/crafting list icons
2. a debug-starting-inventory switch in PlayerController
