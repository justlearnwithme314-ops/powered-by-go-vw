# Powered by GO.VW

A modular Minecraft-like voxel game built with Godot 4 and
[Zylann's Godot Voxel Tools](https://github.com/Zylann/godot_voxel).

The project is structured so an AI can add a feature by creating a new mod
folder instead of editing the engine core. The shipped game scene contains the
Zylann `VoxelTerrain`, player scene, UI, and network session composition.

## Start here

Read:

```text
docs/AI_MODDING_GUIDE.md
docs/ARCHITECTURE.md
mods/_template/
```

## What is already modular

- Namespaced string IDs for blocks/items/recipes.
- Stable internal voxel ID allocation for Zylann's blocky library.
- Core game content is itself a mod.
- Dependency-aware mod loader.
- Folder and `.pck` mods.
- Mod-local asset resolution for `res://` and `user://`.
- Ordered world-generation stages.
- Thread-safe generation runtime for Zylann worker threads.
- Generic event bus for gameplay hooks.
- Dedicated world/edit/crafting services.
- Multiplayer content signatures to reject mismatched mod sets.
- Per-mod persistent JSON storage.
- SQLite voxel persistence through Zylann when the installed build provides it.

## Mod example

```text
user://mods/my_mod/
  mod.json
  mod.gd
  models/
  scripts/
```

The minimum executable mod is:

```gdscript
extends GameMod

func register(api: ModAPI) -> void:
    api.register_block({
        "id": "my_mod:copper_ore",
        "display_name": "Copper Ore",
        "model": api.load_asset("models/copper_ore.tres"),
    })
```

No numeric voxel ID is required.

## Zylann integration

Zylann remains the actual voxel terrain backend:

```text
VoxelTerrain
VoxelTool
VoxelGeneratorScript
VoxelMesherBlocky
VoxelBlockyLibrary
VoxelStreamSQLite
```

The project adds a clean application layer above those classes instead of
replacing them.

## Security

Mods are executable code. Only install mods you trust.
