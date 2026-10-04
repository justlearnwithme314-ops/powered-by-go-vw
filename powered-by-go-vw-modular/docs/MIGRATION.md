# Migration / Rework Notes

This package is an architectural rework of the earlier prototype.

## Main changes

The old prototype had gameplay systems directly coupled to numeric voxel IDs,
large scene scripts, and the `Global` singleton. The rework replaces that with:

```text
logical content IDs
    -> ContentRegistry
    -> Zylann voxel IDs (internal)

mods
    -> ModAPI
    -> services / events / worldgen

VoxelTerrain
    -> tiny VoxelGeneratorScript adapter
    -> frozen GenerationRuntime
```

## Important file moves

```text
old scripts/                       -> core/
old terrain/generators/             -> content/core worldgen stages
old numeric Block constants         -> namespaced string IDs
old ModLoader                      -> core/modding/ModLoader.gd
old global terrain access           -> core/world/VoxelWorldService.gd
old inventory crafting UI logic     -> core/inventory/CraftingService.gd
```

## Save data

The old SQLite file from the prototype is preserved at:

```text
legacy/world.sqlite
```

The current game saves to:

```text
user://worlds/<save_name>.sqlite
```

Stable voxel ID allocation is stored at:

```text
user://content/voxel_ids.json
```

Keep that file when updating the game or adding/removing mods from an existing
save.

## Compatibility note

This rework has been statically checked for file references and architecture,
but the execution environment used to produce the package does not contain the
Godot editor/runtime. Open the project once in Godot 4.7.x with the bundled
Zylann addon so Godot can import resources and report any engine-specific parse
or API issues.
