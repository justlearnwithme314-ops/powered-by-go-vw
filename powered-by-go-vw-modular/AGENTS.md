# AI Contributor Contract for GO.VW

Read this file before changing the project.

## Mission

GO.VW is a Godot voxel game whose application architecture must remain easier
to extend than the current feature set. New features should normally be a mod,
not a core edit.

## First files to read

```text
docs/AI_MODDING_GUIDE.md
docs/ARCHITECTURE.md
mods/_template/mod.gd
mods/_template/mod.json
```

## Architecture rules

### Content

Use namespaced logical IDs:

```text
namespace:name
```

Never hard-code a Zylann voxel integer in a mod. `ContentRegistry` owns that
mapping.

### Mods

Every executable mod has:

```text
mod.json
mod.gd
```

Use `ModAPI`, not `GameAPI` internals.

Use:

```gdscript
api.load_asset("models/foo.tres")
```

instead of `res://...` paths. This keeps a mod portable between project folders,
`user://mods`, and `.pck` packs.

### World generation

Worldgen stages receive `WorldGenContext` and may run on Zylann worker threads.
They must use only:

- the supplied context
- deterministic noise
- the supplied content snapshot
- local computation

Never access SceneTree, Nodes, multiplayer, autoloads, or mutable global state
from a world-generation callback.

### Voxel backend

Only these layers should know about Zylann:

```text
terrain/world_generator.gd
core/world/VoxelWorldService.gd
scenes/world/World.gd
```

Do not call `VoxelTerrain`, `VoxelTool`, or `VoxelBlockyLibrary` directly from a
feature mod.

### Gameplay

Use services/events:

```text
WorldEditService
CraftingService
EventBus
GameEvents
```

Do not put crafting or block-rule logic in UI scripts.

### Runtime extension

For custom runtime entities/UI/systems, listen for lifecycle events and create
mod-owned scenes/nodes there. Keep those nodes and scripts inside the mod.

Useful lifecycle events:

```text
game_started
world_ready
player_spawned
player_despawned
world_stopping
game_stopping
```

## What not to do

Do not create another `Block` enum.

Do not revive the old `Global` singleton.

Do not edit `PlayerController.gd` merely to add a feature that could be a mod.

Do not put mod-specific logic in `ContentRegistry`.

Do not access `GameAPI` from `terrain/world_generator.gd` or generation stages.

Do not assume filesystem ordering determines mod ordering; use manifest
`dependencies` and worldgen stage `order`.

## When core changes are justified

Core changes are appropriate when the requested feature needs a new generic
extension point that no current public service/event can express.

When adding one, keep the public API small, document it, and add the concrete
feature itself as a mod/example where possible.

## Verification

Before delivering changes:

1. Check all `res://` references in `.tscn` files exist.
2. Check all JSON manifests parse.
3. Search for numeric block constants or `Global.` references.
4. Check mod IDs/namespaces and dependency declarations.
5. Verify Zylann native binaries remain present.
6. Open the project in the target Godot/Zylann environment and resolve any
   engine-specific parser/API errors before claiming runtime verification.
