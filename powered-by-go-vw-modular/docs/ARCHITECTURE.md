# GO.VW Architecture

## Goal

GO.VW is organized as a small voxel engine shell plus a set of replaceable
systems and executable content mods. The architectural rule is:

> Features should depend on stable services and events; only the voxel adapter
> should know that Zylann exists.

This lets an AI add a large feature by creating one self-contained mod instead
of changing unrelated files.

## Runtime layers

```text
┌──────────────────────────────────────────────────────────┐
│                        MODS                              │
│  blocks / items / recipes / worldgen / gameplay hooks    │
└──────────────────────────┬───────────────────────────────┘
                           │ ModAPI
┌──────────────────────────▼───────────────────────────────┐
│                     GAME SERVICES                        │
│ ContentRegistry  EventBus  CraftingService               │
│ WorldEditService  CraftingService    VoxelWorldService   │
│ Player / Inventory / UI                                   │
└──────────────────────────┬───────────────────────────────┘
                           │ adapter boundary
┌──────────────────────────▼───────────────────────────────┐
│                    ZYLANN VOXEL TOOLS                     │
│ VoxelTerrain / VoxelTool / VoxelGeneratorScript          │
│ VoxelMesherBlocky / VoxelBlockyLibrary / SQLite stream    │
└──────────────────────────────────────────────────────────┘
```

## Startup

```text
GameAPI
  -> ContentRegistry
  -> EventBus
  -> WorldGenerationPipeline
  -> VoxelWorldService
  -> WorldEditService
  -> CraftingService
  -> ModLoader
       -> core:base
       -> dependency-resolved mods
  -> finalize content
  -> finalize worldgen stages
```

The core game registers blocks, items, recipes, and terrain stages through the
same `ModAPI` contract that third-party mods use.

## Content IDs vs voxel IDs

Mods use stable IDs such as:

```text
core:stone
example:copper_ore
machines:steel_plate
```

`ContentRegistry` internally maps them to Zylann's numeric block types. The map
is persisted to:

```text
user://content/voxel_ids.json
```

Missing IDs are never inserted into the middle of an existing map. Instead,
free IDs are appended, and unused slots become
`VoxelBlockyModelEmpty` holes in the generated library.

This is what keeps a mod from accidentally renumbering every block after it.

## Zylann boundary

### Generation

```text
VoxelTerrain
  -> VoxelGeneratorScript
  -> GenerationRuntime
  -> WorldGenContext
  -> ordered stage Callables
```

`VoxelGeneratorScript` is deliberately tiny. It does not use `GameAPI` because
Zylann can invoke `_generate_block()` from worker threads.

`World._ready()` creates a `GenerationRuntime` snapshot after all mods have
registered their stages. The runtime contains:

- world seed
- immutable content snapshot
- ordered stage Callables

Each generation job creates its own `WorldNoise` instance, so custom noise maps
are not lazily mutated by multiple worker threads.

### Editing

```text
Player / server / mod
  -> WorldEditService
  -> VoxelWorldService
  -> VoxelTool
  -> VoxelTerrain
```

`VoxelWorldService` is the only gameplay service that directly uses
`VoxelTerrain`/`VoxelTool`.

## Mod dependencies

Every mod has a manifest. Example:

```json
{
  "id": "example:machines",
  "name": "Machines",
  "version": "1.0.0",
  "api_version": 1,
  "entry": "mod.gd",
  "dependencies": ["core:base", "example:metals"]
}
```

`ModLoader` resolves dependencies before registering a mod. Filesystem order is
not part of gameplay behavior.

## Mod asset paths

Each mod receives a context-specific `ModAPI` with `root_path` and helpers:

```gdscript
api.load_asset("models/copper_ore.tres")
```

The same line works when the mod is under `res://`, `user://`, or a mounted
`.pck`.

## Mod storage

Every mod can use `api.storage` for persistent JSON data under `user://mod_data/`.
This prevents feature-specific save data from leaking into core save files.

## Events

Events are the low-coupling extension mechanism for runtime behavior. Canonical
names are in `GameEvents.gd`.

Examples:

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

`before_*` events are mutable/cancellable; `after_*` events are notifications.
A mod can therefore add behavior around an existing system without patching
the system itself.

## Why there is no giant GameManager mod API

The old pattern made mods depend directly on a large gameplay node. That forced
mod authors to know scene paths, node names, and implementation details.

The new rule is:

```text
mod -> ModAPI -> service -> implementation
```

A future service can be implemented differently without changing the mod
contract.

## Where new features belong

| Feature | Preferred location |
|---|---|
| New block/item/recipe | `mods/<feature>/` |
| New worldgen pass | mod `register_worldgen_stage()` |
| Block break/place rule | event listener or generic edit service extension |
| New item behavior | `item_use` event + mod-owned behavior |
| New crafting rule | `before_craft` / `after_craft` |
| New UI | mod-owned `Control`/scene, attached from `player_spawned`/`game_started` |
| New mob/entity system | mod scene + lifecycle event |
| Generic missing extension point | add one small stable core API, then use it from a mod |

## AI workflow

1. Read `docs/AI_MODDING_GUIDE.md`.
2. Search `mods/_template` for the nearest pattern.
3. Create a feature folder under `mods/`.
4. Give everything a namespaced ID.
5. Register content through `ModAPI`.
6. Register runtime behavior with events/services.
7. Do not touch Zylann or numeric voxel IDs.
8. Keep the feature self-contained.

The architecture is intentionally optimized for agents that have not seen the
entire project before.

## Player runtime extensions

`core:player_actions` creates mod-owned movement/pistol child nodes from
`player_spawned`, after saved inventory restoration. The controller provides
small optional movement hooks; core owns collider ownership, posture clearance,
gravity and collision movement. Legacy tuning exports remain for existing scene
compatibility. See `mods/player_actions/README.md` for the hook and typed
`DamageReceiver` contracts, development opt-in, and posture contracts. Multiplayer presentation is documented below.

## Multiplayer presentation

The controller sends 20 Hz snapshots through the server: transform, look pitch,
held item, velocity, grounded state, capsule height, whitelisted pose flags and
normalized animation phase. `PlayerSyncState` bounds numeric fields and excludes
arbitrary mod data. RPC sender identity selects the player's node; packets from
peers that have not completed the spawn handshake are ignored. Movement uses an
ordered unreliable channel separate from reliable spawn/voxel messages.

Remote controllers apply posture without running local input extensions or
clearance queries. Transforms interpolate, with first snapshots and large
teleports snapping. The server retains the latest position for edit checks.
The model adapter samples replicated locomotion and corrects animation phase;
head aim follows look pitch. Stationary players continue sending snapshots, so
late joiners receive their current pose without waiting for movement.

Protocol `govw3` rejects clients using the previous packet format through the
existing content handshake. Use matching builds on every peer. This does not
add multiplayer damage authority, weapon effects, inventory replication or a
custom-seed world handshake.

Presentation also replicates a bounded interaction swing timer. Valid block
hits and placement attempts trigger it; the model adapter bends the wielding
arm and remote peers consume the same timer. The local character's full mesh
uses shadow-only rendering. A camera viewmodel reuses its skinned right-arm
geometry and hand socket with all viewmodel shadows disabled. Tools use crisp,
size-normalized icons anchored at their handles; held blocks use cached meshes
from the generic `VoxelWorldService.get_block_display_mesh()` adapter method.

Run `tests/MultiplayerPresentation.tscn` headlessly for a real local two-peer
ENet test of the production RPCs, pose/animation/collider application, owner
echo rejection, airborne state, held-item visibility and interpolation. Its
session fixture does not open or save worlds.

## Local world selection and saves

Local launches now require a world created and selected in the menu. Running
the world/game scene without a selection returns to the menu before persistence
is configured. The catalog lists saved files only, without an automatic default
entry. Joining a host uses transient client terrain and the existing global
player snapshot; it does not create default world metadata or a SQLite database.
Existing saves are retained and remain deletable through the menu.

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

## Slot inventory foundation

SlotContainer is the generic storage model: fixed capacity, per-slot predicates,
metadata-aware merging and atomic transfers/recipe exchange. Slot reads and
snapshots are deep copies. Revisions advance before transfer notifications.
Inventory wraps 34 player slots (first ten form the hotbar) and five equipment
slots. Items declare accepted equipment positions in properties.equipment_slots.

Use get_slot, add_stack (exact added/remainder), move_stack, equip, unequip and
craft_transaction. Legacy add_item is all-or-nothing; callers must handle false.
The transitional grant_item preserves reward overflow in recovery storage. items
and hotbar are compatibility views: modifying their returned arrays cannot mutate
inventory state. Concrete stack selection will be exposed by the new slot UI.

Snapshot version 2 stores slots, equipment, selection and recovery. Old snapshots
migrate without discarding overflow or unavailable mod items. Recovery is saved
and can be reclaimed through the inventory panel when space exists. Networking
must subsequently route these operations through authoritative commands; phase 1
preserves the existing local ownership model.

## Inventory slot interface and world dropping

The inventory panel exposes 24 backpack slots, ten hotbar slots and filtered
 equipment slots. Left click/drag moves, merges or swaps; right click takes half
or places one; Shift-click transfers between backpack and hotbar. Double click
collects compatible stacks into the held stack up to its limit. Group & sort
compacts only the backpack, retaining hotbar assignments. Hovering a slot and
pressing 1-9 or 0 moves its actual stack to that hotbar position.

Cursor stacks belong to Inventory's single-slot cursor container, are included
in version-2 snapshots, and return on closing/rebinding UI. Reloaded cursor stacks
return to inventory or persisted recovery. Invalid drags return safely. UI reads
copies and delegates mutations to Inventory/SlotContainer.

Q drops one item; Ctrl+Q drops a stack. Clicking/dragging outside the open panel
also drops the held stack (right-click drops one). InventoryDrops creates small
world meshes/sprites with a pickup delay and partial collection. These records
are saved in the world's .drops.json sidecar; catalog/deletion include that data.
This bridge is single-player only. Multiplayer world dropping returns an explicit
failure without consuming anything, pending authoritative shared inventory work.
Mining rewards still enter inventory through the existing grant path.

Hotbar keys are 1-9 and 0 (the tenth slot). Version-2 snapshots include hotbar_size;
old eight-slot snapshots gain two empty hotbar slots before their backpack, keeping
old stack positions and quantities intact. Backpack capacity remains 24 slots.

### Local progression services

GameAPI exposes BlockEntityService, InventoryCommandService and ItemInstanceService.
Feature mods implement crafting stations, tool condition and player survival over
these generic services. The local world .entities.json contains station containers,
processing state, inventory and namespaced player data. Atomic container mutations
and bounded revision/request validation prevent local transfer/replay mistakes.
Terrain and dropped-item persistence remain separate, and shared server inventory
and combat authority are pending. New survival/progression is currently single-player.

### Creature framework

EntityRegistry is the generic ModAPI entry point; entity_framework owns actors,
movement, composable abilities, spawning, snapshots and world loot transactions.
first_creatures supplies the pig and melee skeleton definitions/assets. Single-player
entity data is a namespace in the combined .entities.json snapshot. Network hosts
use .creatures.json for creature state, loot and credential-scoped server inventories;
clients mirror inventories through validated slot commands and scoped receipt saves.
Damage and item stats remain on the host. Existing terrain/manual-drop persistence
and shared station/survival networking remain outside this creature ledger.
