# AI Modding Guide

This file is the stable development contract for coding AIs working on GO.VW.

The intended workflow is: **create a mod, register content, add behavior with
services/events, and avoid editing core systems unless the public API is truly
missing something.**

## 1. Mod layout

```text
my_mod/
  mod.json
  mod.gd
  models/
  scripts/
  textures/
```

The same folder can be placed in `user://mods/`, `res://mods/`, or packaged as
`.pck` content.

### Manifest

```json
{
  "id": "example:copper",
  "name": "Copper Expansion",
  "version": "1.0.0",
  "api_version": 1,
  "entry": "mod.gd",
  "dependencies": ["core:base"]
}
```

Dependencies are resolved before `register()` is called, so a mod does not
have to depend on filesystem ordering.

## 2. The public API

Every mod receives a `ModAPI` instance containing:

- `api.content` — read content and inspect blocks/items/recipes.
- `api.world` — high-level voxel world access.
- `api.edits` — validated break/place operations.
- `api.crafting` — validated crafting operations.
- `api.events` / `api.on()` — extensible gameplay hooks.
- `api.register_block()` / `register_item()` / `register_recipe()`.
- `api.register_worldgen_stage()` — deterministic worldgen extension.
- `api.asset("models/file.tres")` and `api.load_asset(...)` — mod-local assets.
- `api.storage` — persistent JSON data owned by the mod.
- `api.save_storage()` — persist mod data immediately when needed.

Do **not** reach directly into `GameAPI` from a mod unless a deliberately
shared global service has been added to the API contract.

## 3. Stable IDs

Always use namespaced strings:

```gdscript
const COPPER := "example:copper_ore"
```

Never write numeric Zylann voxel IDs in user mods. The game maps logical IDs to
stable numeric IDs internally and persists those mappings in
`user://content/voxel_ids.json`.

## 4. Block

```gdscript
extends GameMod

func register(api: ModAPI) -> void:
    api.register_block({
        "id": "example:copper_ore",
        "display_name": "Copper Ore",
        "model": api.load_asset("models/copper_ore.tres"),
        "hardness": 3.0,
        "solid": true,
        "transparent": false,
        "tags": ["block", "ore"],
        "drops": [
            {"item": "example:copper_ore", "count": 1}
        ]
    })
```

A block automatically gets a matching placeable item. You may also register a
custom item with the same ID at any point during startup; an auto-generated item
will be replaced automatically.

## 5. Item

```gdscript
api.register_item({
    "id": "example:hammer",
    "display_name": "Hammer",
    "stack_size": 1,
    "tags": ["tool"],
    "properties": {
        "break_power": 8.0
    }
})
```

Items can also be non-placeable; omit `place_block` or leave it empty.

## 6. Recipe

```gdscript
api.register_recipe(
    "example:hammer",
    "example:hammer",
    1,
    {
        "core:stick": 2,
        "example:copper_ore": 3
    }
)
```

For gameplay code, use `api.crafting.craft(...)`, not direct inventory edits.

## 7. World generation

```gdscript
func register(api: ModAPI) -> void:
    api.register_worldgen_stage(
        "example:copper_ore",
        350,
        Callable(self, "_generate_copper")
    )

func _generate_copper(ctx: WorldGenContext) -> void:
    var noise := ctx.noise.get_custom_3d(
        "example:copper_ore",
        0.05,
        2
    )

    var size := ctx.buffer.get_size()
    for z in range(size.z):
        for x in range(size.x):
            for y in range(size.y):
                var p := Vector3i(x, y, z)
                if ctx.get_block_id_local(p) != "core:stone":
                    continue

                var wx := ctx.origin.x + x
                var wy := ctx.origin.y + y
                var wz := ctx.origin.z + z

                if wy < 40 and noise.get_noise_3d(wx, wy, wz) > 0.7:
                    ctx.set_voxel_local(p, "example:copper_ore")
```

### Important thread-safety rule

`_generate_copper()` may run on Zylann worker threads. A generator stage must
never access SceneTree, Nodes, multiplayer state, `GameAPI`, or mutable global
state. Use only `WorldGenContext`, its immutable content snapshot, deterministic
noise, and local computation.

## 8. Gameplay events

Events are dictionaries so mods can consume existing fields and ignore fields
they do not need.

```gdscript
func register(api: ModAPI) -> void:
    api.on(
        GameEvents.BEFORE_BLOCK_BREAK,
        Callable(self, "_on_break")
    )

func _on_break(event: Dictionary) -> Dictionary:
    if event["block_id"] == "example:protected":
        event["cancelled"] = true
    return event
```

Useful current events include:

```text
game_started
game_stopping
world_ready
world_stopping
player_spawned
player_despawned
item_use
block_hit
before_block_break
after_block_break
before_block_place
after_block_place
before_craft
after_craft
```

`before_*` events may set `cancelled = true`; `after_*` events are notifications.

## 9. Persistent mod data

```gdscript
func register(api: ModAPI) -> void:
    api.storage.set_value("research_level", 3)
    api.save_storage()

func get_level(api: ModAPI) -> int:
    return int(api.storage.get_value("research_level", 0))
```

Mod storage lives under `user://mod_data/` and is not mixed with world or core
saves. Use it for configuration and mod-owned progression.

## 10. AI-safe architecture rules

Prefer a new mod over editing a core file.

```text
GOOD
mods/automation/
  mod.json
  mod.gd
  scripts/
  models/

BAD
changing PlayerController.gd
changing GameManager.gd
changing ContentRegistry.gd
adding another Block enum
calling VoxelTerrain from feature code
```

Core changes are appropriate when the requested feature needs a new **generic
extension point**, not when it only needs one concrete feature.

## 11. Zylann boundary

Zylann Voxel Tools remains the terrain backend:

```text
VoxelTerrain
  -> VoxelGeneratorScript
       -> GenerationRuntime
            -> WorldGenContext
                 -> mod/core stages

VoxelTool
  -> VoxelWorldService
       -> WorldEditService
            -> gameplay systems / mods

VoxelBlockyLibrary
  <- ContentRegistry
       <- logical block definitions
```

This boundary is intentional. Mods should not depend on the internal numeric
layout of `VoxelBlockyLibrary` or on the lifetime of `VoxelTool`.

## 12. Player movement and damage

For lifecycle-created player components, use the generic movement hooks
specified in `mods/player_actions/README.md`. Register a mod-owned child with
`PlayerController.add_movement_extension()` and unregister on exit. Avoid adding
concrete ability code to the controller. The same README documents the optional
typed `DamageReceiver` child contract for entity damage; no receiver is assumed
on terrain, props, or remote players.

## Local world selection and saves

`GameAPI.saves` and `ModAPI.saves` expose the shared `WorldSaveService` (no new
autoload). This core extension is justified because local save identity, seed
selection and inventory routing must be resolved before world generation and
player restoration; existing gameplay lifecycle hooks were too late. The built-in
main menu is the generic service client, not a mod-specific feature.

- `list_worlds()` returns sorted metadata/SQLite entries with `save_name`,
  `display_name`, `valid`, `error`, and a known `seed` when valid.
- `create_world(name, seed_text, compatibility = {})` validates a signed 32-bit
  seed and reserves metadata with a sanitized `world_` identifier. Collisions
  receive numeric suffixes; existing saves/sidecars are never overwritten.
- `select_world(id)` validates metadata; `selected_config()` returns a copy.
  `clear_selection()` restores direct-scene/default behavior. These are local
  launch settings, not replicated networking configuration. Do not change a
  selection during an active session.
- `state_path(id)` is `user://worlds/<id>.player.json`; `state_load_path(id)`
  falls back to `user://player_state.json` only for default and only until a
  scoped default snapshot exists. The legacy file is not modified or removed.

Terrain remains `user://worlds/<id>.sqlite`, metadata remains `<id>.json`.
Old metadata without a display name is supported. Existing metadata supplies the
original generation seed; creation inputs never alter it. An existing legacy default SQLite database without metadata uses seed 1337; an absent default save is invalid. Other missing metadata and
corrupt/invalid seed metadata block loading and show the path to restore from
backup; no guessed seed, reset, or deletion is performed. Validating a backup
requires preserving its original seed and original mod/content signatures.

Host uses the selected save. Join retains the existing default-world protocol:
there is still no world-identity/seed handshake, so custom-seed multiplayer
joining is not newly supported. NetworkManager and RPCs are unchanged.

`tests/WorldSaves.gd` uses unique `user://world_save_tests/` fixtures and never
touches real saves. Fixtures are intentionally retained (no deletion).
