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

Transparent block definitions (`transparent: true`) are mapped to native voxel
models with a positive transparency index, neighbour culling disabled, and no
LOD skirts. Alpha-cutout or alpha-blended materials are still required for
visible transparency and light through texture gaps. Optional definition fields
`transparency_index` (default 1) and `culls_neighbors` (default false for
transparent blocks) customize this behavior. Opaque models retain normal culling.

Crafting ingredients may use `#namespace:tag` selectors, such as
`{"#core:planks": 4}`. Set matching item `tags` to `["core:planks"]`;
automatically generated block items inherit the block's tags. Shaped grid cells
accept the same selectors. `api.content.ingredient_matches(item_id, selector)`
checks a single item; `resolve_ingredients(requirements, available_counts)`
returns `{success, items}` with concrete consumable counts, allocating each
unit once even across overlapping selectors. Matching tag items must be
registered before registering a recipe using that tag. These selectors are
supported by crafting; furnace processing still uses concrete item IDs.

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

## Click mining

Blocks can declare `breakable` (default true), `preferred_tool`, `required_tool`
and `mining_level`. Items declare `properties.tool_type`, `mining_level`,
`break_power` and `mining_interval` (seconds between accepted clicks).
`content.get_mining_profile(item_id, block_id)` returns allowed/reason/hits/interval.
Preferred tools gain hit strength and swing speed; other tools use hand speed.
Required tools must match both category and minimum strength. The edit service
also checks these requirements for player edits, including remote players.
BLOCK_HIT cancellation stops that click contributing progress.
Each press contributes one hit; holding repeats hits at the tool's interval.
Progress resets on target,
item or mouse capture changes. A small HUD below the crosshair shows hits
remaining or the missing tool requirement. Tool strength is a material tier,
not consumable durability. Bedrock and water are unbreakable.

VoxelInteractor exposes `mining_progress(position, progress)` with normalized
accepted damage, `mining_cleared`, and `block_feedback(block_id, position, action)`
where action is hit, break or place. Break/place feedback follows successful local
results or network acknowledgements. The core:block_feedback mod listens to these
signals for eight-stage crack rendering and material impact sounds. Held swings
use the existing replicated animation timer. Placement repeats every 0.2 seconds;
network placement waits for acknowledgement before another inventory expenditure.

## Progression and survival extension APIs

Use api.stations (BlockEntityService) to register block capabilities and named
containers, check reach, read copied records, update processing state and persist
local world data. Use api.inventory_commands.request(actor, action, args) for
validated craft, repair and station transfers; never accept caller-supplied stacks.
Current command ownership is local only: real multiplayer peers are rejected.

Use api.item_instances to prepare durable stacks, resolve effective stats, spend
condition and quote/commit repairs. Modifier IDs must be registered and namespaced;
unknown metadata survives transfers and saves. Recipe options include station,
method and duration; configure_item_properties/configure_recipe run at registration.

PRIMARY_ACTION lets a mod handle a physical attack before voxel mining.
PLAYER_DIED and PLAYER_RESPAWNED expose lifecycle events. DamageReceiver is the
opt-in damage interface. The gameplay_disabled actor metadata suppresses core
movement/interaction and inventory commands while dead. Do not assume these hooks
provide network authority. See the three survival feature-mod READMEs and smoke tests.

## Creatures and composed entity behavior

Register namespaced definitions through api.entities; feature models and behavior
remain mod-owned. EntityRegistry exposes spawn and receipt-based spawn_loot. Visual
scripts implement setup/animate; optional abilities implement setup/tick/decide,
interact and save_state/restore. Use entity lifecycle events and DamageReceiver.
VoxelWorldService exposes is_loaded/is_solid/can_stand for bounded terrain paths.

The entity framework supplies host-authoritative creature combat, profile inventory
and loot transactions. Inventory.network_adapter routes remote slot commands;
load_snapshot(state, true) preserves cursor ownership for a trusted server mirror.
Only a server-resolved actor may carry inventory_authority metadata. Read
mods/entity_framework/README.md before extending networking: shared stations and
all previous survival systems are not implicitly authoritative through this API.
