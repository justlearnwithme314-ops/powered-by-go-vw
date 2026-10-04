# Architecture Rework Summary

## Audit findings from the previous prototype

The prototype was functional as an MVP, but its extension surface was fragile:

- `Global` exposed active terrain as mutable global state.
- Blocks were represented by hard-coded integers in gameplay and terrain code.
- Inventory/UI contained concrete crafting behavior.
- `PlayerController` mixed movement, terrain collision checks, and gameplay glue.
- `GameManager` owned networking, player lifecycle, voxel synchronization, and
  gameplay validation at once.
- `ModLoader` only loaded PCKs and had no content registration contract.
- World generation depended on concrete block constants and was difficult for a
  new feature author to extend safely.
- Zylann's worker-thread generator boundary was not isolated from the autoload.
- The game scene previously did not instantiate the world scene in the reworked
  package; this version restores that composition explicitly.

## New architecture

```text
                         ┌─────────────┐
                         │   Mod files  │
                         └──────┬──────┘
                                │ ModAPI
             ┌──────────────────▼──────────────────┐
             │       Game application layer        │
             │                                     │
             │ Content  Events  World  Edits       │
             │ Crafting  Network  Player  UI       │
             └──────────────┬──────────────┬───────┘
                            │              │
                   generation adapter   edit adapter
                            │              │
                    ┌───────▼───────┐  ┌──▼───────────┐
                    │ GenerationRun │  │ VoxelWorld   │
                    │ Context+stages│  │ Service      │
                    └───────┬───────┘  └──┬───────────┘
                            │              │
                    Zylann VoxelGenerator  VoxelTool
```

## What became possible

### Add a block

One mod file + one model asset.

### Add an item/tool

One `register_item()` call and optional `item_use` listener.

### Add crafting

One recipe; the UI automatically sees the registry entry.

### Add an ore/biome/structure generation pass

One worldgen stage in a mod; no core generator edit.

### Change break/place rules

Use `before_block_break` / `before_block_place` events.

### Add a custom crafting rule

Use `before_craft` / `after_craft` events.

### Add custom runtime content

Subscribe to lifecycle events and attach a mod-owned scene/system.

### Persist mod progression/configuration

Use `api.storage` without sharing save files with the engine.

## Compatibility model

The multiplayer handshake includes:

```text
network protocol
+ loaded mod IDs/versions
+ registered content signature
```

Clients with different content sets are rejected instead of silently using
incompatible voxel mappings.

## Zylann integration model

`VoxelBlockyLibrary` remains the actual blocky mesh library. Because Zylann
maps model-array positions to voxel IDs, GO.VW treats those integers as an
implementation detail and allocates them in `ContentRegistry`.

The generator now receives a frozen `GenerationRuntime`. It does not ask an
autoload for state while Zylann is generating chunks in worker threads.

## Verification status

Static project verification completed in the build environment:

- 134 files in the reworked source tree.
- JSON manifests parse.
- `.tscn` resource paths resolve to existing files.
- no active-code references to the old `Global` / numeric `Block.*` architecture.
- all 12 bundled Zylann native binaries are present.

The build environment did not contain the Godot executable, so the package was
not run through the Godot parser/renderer. The first runtime validation should
be performed in the project's target Godot 4.7.x + Zylann environment.
