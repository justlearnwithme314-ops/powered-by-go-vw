# Inventory, loot and interactive stations implementation plan

Status: phase 1 and the player slot UI implemented (2026-10-05).
Single-player manual world drops/pickups implemented. Shared authority,
mining-spawned loot and interactive stations remain planned.
Scope: priorities 1 and 2. Networking authority and new station/drop gameplay
are not implemented by the first milestone.

## Outcome

A player can mine a block, collect its dropped items, split and move stacks,
equip items, store supplies in a chest, craft at a workbench and smelt using
fuel. Two players can use the same world without duplicating or losing items.
All relevant state survives saving, reconnecting and restarting that world.

## Current constraints

- Inventory has unlimited stacks; eight hotbar entries reference item IDs,
  rather than concrete slots. Item counts can therefore represent several stacks.
- Mining presently grants drops directly to the local inventory.
- CraftingService already validates ingredients and attempts rollback, but needs
  capacity-aware output reservation and server authority for shared gameplay.
- GameManager handles network block edits, but inventory ownership and pickup
  transactions need a consistent authoritative protocol.
- ModStorage uses global per-mod files. World entities and stations must use
  world-scoped storage, with stable player ownership rather than transient peer IDs.
- Existing survival tools, food, recipes, held-item visuals and saves must migrate.

## Architecture

Core owns generic stack/container transactions, item metadata, world entity state,
save integration and networking. A survival-interactions mod owns chest,
workbench and furnace definitions, recipes, scenes, UI and presentation.
Expose these services through ModAPI with small documented extension points.
Keep Zylann operations within the existing voxel adapter boundary.
Do not encode concrete survival block rules in UI or PlayerController.

Use namespaced content IDs and versioned serializable records:
- Stack: item ID, quantity, metadata and optional individual-item ID.
- Container: stable ID, slot definitions, stacks and revision.
- Block entity: world ID, grid position, type, orientation and persistent state.
- Dropped item: stable entity ID, stack, position and pickup delay.
Stack compatibility includes metadata; differently modified items never merge.
No arbitrary code or Nodes are deserialized from saves/network messages.

## Phase 1: containers and save migration

Implement fixed-slot containers with capacity checks, accepted-item filters,
add/remove/move/split/merge/swap operations and exact remainder reporting.
Make multi-container operations atomic: either every change commits or none does.
Reserve crafting output space before consuming ingredients.
Keep compatibility wrappers for existing add_item/remove_item/count callers.

Default inventory: eight existing hotbar slots plus 24 backpack slots. Hotbar
slots hold actual stacks. Add head/body/legs/feet equipment and a future offhand
slot; item definitions declare allowed slots. Combat bonuses are a later module.
Validate selected equipment against existing held-item and pistol behavior.

Migrate old snapshots once, retaining every valid item and its quantity. Put
legacy overflow into recoverable storage, never silently discard it. Keep a
backup before migration. New saves use a versioned format and stable owner IDs.
Do not conflate authentication/security identity with a user-chosen display name.

Acceptance: stack limits, partial adds, metadata compatibility, migrations and
failed transactions preserve exact item totals, including full inventories.

## Phase 2: authoritative inventory operations

Route local and remote gameplay through the same server-owned transactions.
Clients submit actions, not replacement inventory snapshots or invented stacks.
Use request IDs, container revisions, duplicate-request handling and validated
ownership/access. Replicate private inventory to its owner and equipment visuals
to observers. Validate station reach and access for each action, not just opening.

Move placement consumption, crafting output and mining rewards to this protocol;
remove client-side reward/consumption paths to prevent double application.
Submit individual mining hits so the server validates cooldown, target, tool and
required hit count before accepting the final break. Preserve click-only mining.

Acceptance: two clients cannot duplicate items through simultaneous requests,
retries, stale revisions, disconnects or forged container access.

## Phase 3: inventory interface

Replace the item list with stack slots: icons, quantities, selection and tooltips.
Left click picks up/swaps/merges; right click takes half or places one;
Shift-click transfers between inventory and an open container; drag moves stacks.
Q drops one selected item; Ctrl+Q drops the selected stack, while gameplay has focus.
Provide equipment slots and retain number-key/wheel hotbar controls.

The cursor-held stack must have explicit ownership. Closing a panel, losing
access or disconnecting returns it safely; a full inventory retains a recoverable
stack or produces one authoritative drop. UI only requests service operations.

Acceptance: no input conflicts with mining, food, pistol use or mouse capture;
all stack operations work with full containers and cancelled interactions.

## Phase 4: dropped world items

Spawn loot on successful server block removal, manual dropping and station
destruction. Use textured mini block meshes for blocks, sprites for icon items,
and supplied 3D models when a suitable mapping exists. Add modest bounce,
bobbing, pickup sounds and a short delay preventing immediate self-pickup.

Server performs nearby pickup, compatible drop merging and quantity transfer.
A full inventory leaves the remainder in the world. Bound active drop counts
and merge checks; avoid a physics body or expensive per-frame scan per item.
Persist drops per world. Initially keep loot until collected; configurable
despawn policies can be added later without silently deleting saved valuables.

Acceptance: simultaneous pickup awards each item once; late joiners see remaining
drops; partial pickups and save/reload preserve counts.

## Phase 5: interactive block entities and chests

Add a registry for mod-defined interactive blocks and a world-scoped block-entity
service. Keep state bound to occupied voxel positions. Render chest/workbench
models as presentation nodes with adapter-managed placeholder voxel models;
avoid duplicate visible cubes and enforce player collision/placement bounds.
Support orientation and right-click dispatch before ordinary placement.

Implement a 27-slot chest with inventory transfers and shared updates. Use revision
checks rather than permanently locking a chest to one player. Removing a chest
closes its viewers and atomically drops the chest and its contents once.

Acceptance: two viewers see committed transfers; breaking an open chest cannot
lose or duplicate contents; unloaded/reloaded areas recreate correct entities.

## Phase 6: crafting workbench

Extend recipe definitions with station requirements while retaining current
ingredient-based recipes. Personal crafting shows hand recipes; the workbench
shows its unlocked recipe set, ingredient shortages and available output space.
Support craft-one and bounded craft-many with server validation of each batch.
Classify existing tool recipes for station crafting without creating a circular
dependency: the workbench itself must be craftable by hand.

Acceptance: unavailable stations cannot be bypassed by direct requests; failed
or capacity-blocked crafting consumes nothing. Crafting-grid recipes are deferred.

## Phase 7: furnace processing

Implement input, fuel and output slots using the same container service. Recipes
declare input, output, station and processing time; fuels declare burn duration.
UI shows cooking progress and remaining fuel. Start with basic metal smelting
and food cooking, replacing instant equivalents only after the furnace recipe
and starter progression are available.

Processing belongs to the server and continues when the panel closes or players
walk away. Store state outside presentation nodes so visual chunk unloading does
not reset progress. Stop consuming new ingredients when output cannot fit; retain
partial progress and account for fuel explicitly. Preserve remaining fuel and
progress on save/reload. Initial policy: no progress while the game is closed.
Breaking a furnace drops contents and furnace once, then cancels processing.

Acceptance: full output, missing fuel, input changes, restart and destruction
cannot create free output, consume items twice or reset stored contents.

## Phase 8: integration and verification

World saves include containers, drops, block entities and stable player records;
write atomically with backups and debounce frequent changes. World deletion must
remove only that world's data. Global mod preferences remain separate.
Define recovery when a mod/item disappears: retain unknown records in quarantine
and explain missing content instead of discarding valuable inventory.

Verify isolated service tests, real two-client RPC tests, save migrations and
in-engine UI/model presentation. Check scene references, manifests, namespaced
IDs, native voxel binaries and engine diagnostics per AGENTS.md.

Final acceptance playthrough: two players mine, collect, split, equip, drop,
share a chest, craft a tool and smelt ore; one reconnects, then the host saves and
restarts. Item totals, chest contents and furnace progress remain correct.

## Asset use

Uploaded packs verified present: KayKit Dungeon, Adventurers and Skeletons;
Kenney Survival, Particle, Impact Sounds and Blaster kits, plus existing textures.
Kenney Survival includes chest.glb and workbench models. Choose a consistent
chest/workbench family after a scale/material preview; keep original packs intact.
Use existing pixel block textures for a custom furnace if no suitable model exists.
Particles and impact sounds provide pickup/mining/station feedback. Enemies and
shooter assets are available but outside these first two priorities.

## Deferred scope

Double chests, hopper automation, crafting grids, sorting rules, durability loss,
equipment combat bonuses, enchantments, animal AI, quests and new shooter systems.
Provide extension points for these rather than coupling them into this milestone.

## Delivery order

1. Stack/container foundation and lossless migration.
2. Authoritative transactions and mining/crafting integration.
3. Inventory UI and equipment slots.
4. World drops and pickups.
5. Persistent interactive blocks and chests.
6. Workbench progression.
7. Furnace processing.
8. Complete multiplayer/save acceptance and presentation polish.

Each delivery is playable and verified before the next. Networking and persistence
are implemented alongside the relevant systems, rather than appended at the end.

## Phase 1 delivery notes

Implemented SlotContainer and the Inventory facade with 32 slots, five filtered
 equipment slots, metadata-aware merging, partial insertion, move/split/swap and
atomic recipe exchange. Inventory snapshots are version 2. Legacy valid items
are migrated, overflow and missing content are retained in recovery, and the
existing inventory UI exposes a recovery button. Hotbar counts reflect real
stacks. Equipment slots now have their slot UI; concrete armor definitions are separate content.
Mining still grants inventory rewards; overflow is retained instead of lost.

GameManager backs up legacy saves before migration, writes replacement snapshots
through a temporary file, and retains original saves when backup/write fails or
newer/corrupt formats are found. World deletion includes scoped backup/temp files.
No real player saves were migrated during development: tests use isolated data.

Verification: InventoryFoundationSmoke (including real inventory UI binding and
save replacement), MiningSmoke, WorldSaveCatalogSmoke (10 tests), player model
and multiplayer presentation regressions. The first milestone does not claim
server-authoritative inventory, world pickups, chests, workbenches or furnaces.

## Slot UI delivery

Added drag/click transfers, right-click splitting and single placement,
Shift quick-transfer, double-click gather, numbered hotbar swapping, backpack
compaction/sorting, recovery, and safe cursor persistence/return. Rendered and
inspected at 1152x648. Added InventoryUISmoke covering the interaction paths.
Q/Ctrl+Q and outside-panel dropping create collectible persistent world items in
single-player; multiplayer dropping stays disabled until phase 2 provides shared
inventory ownership. This does not claim phase 2 or all of phase 4 complete.
