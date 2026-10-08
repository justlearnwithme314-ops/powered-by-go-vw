# Minecraft feature coverage: project audit and staged roadmap

Reviewed 2026-10-07. This document is an analysis and implementation plan;
it does not add gameplay. It describes the checked-in code and recent Godot
verification, not a claim that every feature has been exhaustively playtested.

## 1. Overall assessment and target

The project has a working modular voxel survival foundation. It already supports
building, mining, crafting, inventory, smelting, basic survival, creatures, saves
and multiplayer. The next priority should be connecting these systems into one
consistent survival game, rather than registering hundreds more texture-backed
items whose behavior is missing.

Do not estimate completion by counting textures or block registrations. A door
requires states, collision and persistence; an animated water texture requires
fluid simulation; a villager texture requires navigation, trading and persistence.

Recommended target: broad coverage of Minecraft's established survival systems,
while preserving this project's deliberate adaptations: repeated mining hits,
ten hotbar slots, expandable workbench arrangements, translucent leaves and
existing extra material tiers. Exact Java/Bedrock parity is a separate, much larger
goal. Record a specific reference edition/version before attempting exact combat,
redstone, spawning or recipe compatibility. Future Minecraft releases should not
continually move the milestone boundaries.

Two useful completion points:

1. **Core survival complete:** players can start empty, obtain tools and iron,
   build and light a shelter, survive nights, farm and breed food, explore caves,
   die/respawn, and resume the same world together without losing state.
2. **Broad Minecraft coverage:** automation, enchantments, brewing, villagers,
   structures, transport, Nether/End progression and bosses also work. New mobs,
   decorative variants and rare mechanics remain an explicitly tracked backlog.

## 2. What exists now

| System | Implemented foundation | Remaining gap |
| --- | --- | --- |
| Architecture | Mod manifests/dependencies; namespaced IDs; events; content snapshots; service APIs | Several feature-specific runtimes still duplicate persistence/network routes |
| Terrain | Native Zylann voxel backend, deterministic staged generation, caves, ores, climate surface variants, trees and rare deep vaults | Coherent biome ecology, rivers/aquifers, structures and dimension generation |
| Blocks | Textured terrain and wood families, glass/leaves with transparency and correct neighbor visibility | General orientation/state properties, multipart blocks, attachment rules and scheduled updates |
| Mining/building | Tool requirements and priorities, durability, repeated/held swings, hit intervals, cracks, sounds and placement cooldown | Unified server mining-progress validation, shared cracks/sounds, balance and richer drop rules |
| Inventory | Ten-slot hotbar, backpack, cursor stacks, split/merge/transfer, sorting, equipment and recovery | One authoritative world-item system; remote manual drops; richer storage shortcuts and content filtering |
| Crafting | Hand grid, expandable connected workbench grid, shaped/mirrored and shapeless recipes, interchangeable ingredient tags | Recipe discovery, complete recipe coverage, workstation-specific upgrades and clearer progression |
| Stations | Fuel/input/output furnace processing, persistent containers, 27-slot chests | Remote chest/furnace panels and concurrent-user transfers; double chests and other workstations |
| Item instances | Tool identities, condition, repair and stat modifiers | Modifier acquisition, enchantment UI, naming, broader equipment metadata and upgrade workflows |
| Player | Minecraft-compatible skins, held items, procedural poses/swings and movement presentation | Swimming, fire/lava/freezing, shields, richer status effects and complete mode/difficulty rules |
| Survival | Local health, hunger, oxygen, falling, drowning, poison, food/healing, armor and respawn | Multiplayer environmental/hunger/healing parity; beds/checkpoints; configurable death inventory drops |
| Combat | Melee damage, tool/armor wear; server creature combat; bow consumes arrows | Bow is currently an instant ray; physical arrows, charge, shields, ranged skeletons and richer combat states |
| Creatures | Pig/cow/sheep/chicken/zombie/skeleton/creeper/spider, shared bounded pathfinding, roaming/chasing/fleeing, drops and persistence | Breeding, babies, following food, shearing/milking, sunlight responses, aquatic/flying AI and ecology |
| Creepers | Fuse/escape, flashing/swelling, sound/particles, damage/launch, spherical block destruction and multiplayer crater replay | Blast resistance, water shielding, chain interactions and common explosion support for TNT/projectiles |
| Farming | Tilling, seeds/crops, mature drops, loaded-area timed growth and persistence | Hydration/light conditions, saplings/leaf decay, stems, sugar cane, cactus and animal farming |
| Multiplayer | Player presentation, host-owned creature simulation, validated inventory commands, combat health, loot receipts and snapshots | Shared station interfaces, manual drops, environmental survival, lower-cost entity replication and wider consistency testing |
| World management | User-created/deletable worlds, per-world data, native terrain saves and sidecars | Save schema migration, cross-file recovery, generation versions and explicit dimension/player scopes |
| Time/weather | Console time command adjusts the sun as a testing preset | Persistent advancing world time, synchronized sleep, weather and light-driven spawning |
| Testing | Smoke scenes for inventory, crafting, mining, survival, worlds, skins, creatures, ENet multiplayer, transparency and explosions | Long-session exploration/load tests; multi-user container contention; crash/reconnect scenarios |

Recent runtime initialization reported 15 executable mods, 107 registered blocks,
220 items and 117 recipes. These counts indicate content breadth, not completeness.
The main code entry points are `core/api/ModAPI.gd`, `ContentRegistry`,
`WorldEditService`, `BlockEntityService`, `ItemInstanceService`, `EntityRegistry`,
`mods/entity_framework`, `mods/shaped_crafting` and `mods/basic_survival`.

## 3. Issues to settle before expanding

### A. Single-player and multiplayer currently differ

Local survival uses `PlayerSurvival`; network creature combat uses `NetworkVitals`.
They do not yet implement the same complete hunger/environmental/healing rules.
The inventory-command and creature-loot network routes already offer a useful
foundation, but remote station panels remain missing.

Manual dropped items use `InventoryDrops` and `.drops.json`; creature rewards use
the entity ledger and receipt logic. These are separate systems. Bring both onto
one shared authoritative item-entity service before expanding death loot, automation,
or projectile recovery. Preserve the user-approved permissive local drop behavior
unless the user explicitly chooses to change it.

### B. Saves have multiple owners

Terrain lives in native SQLite; station/player snapshots, creatures, drops and
farming/cell replay use separate JSON files. Existing atomic operations generally
cover an individual file or ledger, not every related file together. Add versioned
migrations, operation identifiers and recovery rules for operations spanning saves.
Do not promise a single global transaction unless it is actually implemented.

Explosion cell replication currently reuses the farming runtime's change history.
That works for current checks, but should become a generic world-edit replay service
before introducing TNT, fluids, pistons or many other block-mutating systems.

### C. Population and replication need a scalable policy

The failed summon exposed 256 saved actors in the user's world. Explicit summons
now allow up to 1,024 records while natural spawning stops at 256. Raising a cap
fixes testing, but not long-term population management. Define persistent animals
versus transient hostiles, dormant chunk populations, despawn rules and per-biome
caps. Never silently delete user-summoned or named entities to solve a limit.

Current entity snapshots run at 5 Hz and include records/ability state. Add interest
management and changed-state replication as populations grow. Keep the existing
bounded local path searches; profile before attempting a global navigation mesh.

### D. Documentation and balance need cleanup

Some older README/AI notes still describe skeleton spawning as disabled, creepers
as melee-only, or all survival/network work as pending. Current code supersedes
those statements. Maintain one feature matrix with implementation status and tests.

Frontier materials and starter inventory intentionally differ from Minecraft.
Offer a baseline survival preset and a Frontier preset rather than mixing their
recipes and difficulty assumptions accidentally. Keep IDs compatible with saves.

## 4. Staged implementation order

Every stage should finish a small playable slice, including persistence and
multiplayer where applicable. Avoid implementing an entire stage in one enormous
change. The exit checks below define reviewable outcomes.

| Stage | Work to implement | Depends on | Exit check |
| --- | --- | --- | --- |
| 0. Reliability | Feature matrix, save migrations/recovery, generic edit history, population policy, unified survival/drops/container authority | Existing services | Two players explore, transfer items, die, disconnect and reload without cross-world state leakage or lost contents |
| 1. Shelter and night | Persisted clock, difficulty settings, day/night sky; torches, skylight/block-light groundwork; doors/trapdoors, beds/spawn points and sleep | Block states and clock | An empty-start player builds a lit shelter, survives the night and respawns at a saved bed |
| 2. Living world | Water/lava sources and bounded flow, buckets, swimming, fire/extinguishing, fluid reactions, sand/gravel gravity | Scheduled updates, edit replay, damage/status APIs | Water flows across loaded chunk borders, saves/reloads, extinguishes fire and behaves consistently on host/client |
| 3. Sustainable food | Soil hydration/light, crop growth rules, saplings/trees, leaf decay, cane/cactus; food following, breeding/babies, shears/milk, animal cooldowns | Clock, light, entities and items | A player can build a renewable food/wood farm without console items and keep it after reload |
| 4. Combat and mob ecology | Physical arrows/throwables, charged bow, ranged skeletons, shields, sunlight responses, spawning by light/biome, more status effects | Projectile and lighting services | Skeleton arrows hit/block correctly, ammunition and wear stay authoritative, mobs obey light/day rules |
| 5. Building catalog | Stairs/slabs/fences/walls/panes, facing/connection states, ladders, signs, beds/multipart placement, paintings and decorative palettes | Block states, collision/model variants | Rotated and connected blocks render/collide correctly, survive reload and refund sensible items when broken |
| 6. Exploration | Height-dependent ores, stronger biome identities, river/ocean generation, cave variants; reusable structure templates, ruins/dungeons/mineshafts/villages and loot tables | Versioned worldgen, loot, lighting/fluids | Several seeds produce reachable resources/structures with no chunk seams or duplicated structure loot |
| 7. Equipment progression | Experience, enchantments, anvil naming/repair/combining, grindstone, smithing/material upgrades; brewing and potion effects | Item instances, status effects, station authority | One item preserves identity, wear, name and enchantments through use, storage, trade and reload |
| 8. Automation | Redstone signal graph, switches/buttons/plates, lamps, repeaters/comparators; hoppers, dispensers/droppers; pistons later | Scheduled updates, block states, containers and edit replay | A small crop/loot processing machine works with two players and after chunk unload/reload |
| 9. Villages and transport | Villager professions/trading/restocking, schedules/POIs, golems; boats, rails/minecarts, mounts, leads, fishing | Entity abilities, economy, fluid and movement systems | A persistent village restocks trades and a vehicle transports a player across chunk boundaries |
| 10. Dimensions and endgame | Dimension registry/saves, portals, Nether generation, fortresses and relevant mobs/resources; strongholds, End access, dragon; Wither and later bosses | All world/survival/progression services | A complete resource-to-portal-to-boss journey survives player deaths, reconnects and world reloads |
| 11. Completion backlog | Remaining mobs/biomes, advanced redstone, weather variants, maps/compasses, advancements, creative/spectator modes, accessibility, specialized blocks and effects | Earlier stages | Every targeted feature has an explicit complete/deferred entry and a validation scenario |

### Suggested first six implementation batches

1. Unify remote chest/furnace transactions and manual world drops with existing
   server inventory ownership. Exercise two users opening the same container.
2. Add saved world time and a configurable survival preset; route console `time`
   through the clock rather than editing a light directly.
3. Add generic facing/properties, multipart placement and neighbor-update hooks;
   use a working door as the first proof.
4. Add torches and usable light queries. Prototype light propagation on a bounded
   region before tying spawning/farming to it; avoid one permanent light node per
   torch in a large world.
5. Add beds with saved respawn points and synchronized sleep policy.
6. Add a shared physical projectile implementation and give skeletons bows.

These batches close noticeable gameplay gaps and establish services later stages
need. Do not begin with a mass asset import or a full redstone/Nether implementation.

## 5. Reusable technical foundations

- **Block properties:** logical block ID plus typed facing/open/half/connection/
  fluid-level/growth properties. Decide how native voxel model variants map to
  these without leaking integer voxel IDs into mods. Estimate model/state growth
  and migration requirements before implementing every orientation as a new ID.
- **Scheduled world updates:** deterministic, budgeted updates for fluids,
  gravity, growth, redstone and support rules; clear loaded/unloaded chunk policy.
- **Clock and light queries:** common APIs for time, sky exposure and block light;
  behavior must not depend on what a camera currently renders.
- **Projectiles/explosions:** reusable damage context, collision, ownership,
  impulse, resistance and effect replication. Creeper behavior becomes one client
  of this service; TNT, RPG spells and shooter grenades can reuse it later.
- **Containers:** per-player session/revision validation; server-side transfers,
  close/reopen/reconnect handling, processing while UI is closed and saved metadata.
- **Entity abilities:** keep species behavior composed around shared movement;
  add navigation profiles for swimming/flying/climbing rather than copying actors.
- **Statuses and stats:** timed effects with stacking/expiry rules, shared armor/
  resistance calculations, and item-instance modifiers for enchantments and RPG gear.
- **Generation/structures:** pure snapshot-driven stages, deterministic templates,
  coordinate-scoped randomness, and generation version recorded with each world.
- **Dimension ownership:** keys for dimension/chunk/entity/player scope; portal
  transitions must not overwrite inventories, clocks or world-specific survival.

Follow `AGENTS.md`: implement gameplay in mods through `ModAPI` and events; keep
backend details in the world adapter. Add small generic core extension points
only when existing public services cannot express the required behavior.

## 6. Assets already available

The local catalog lists thousands of images across multiple packs. The Minecraft
texture folder includes many block/item textures, entity atlases, GUIs and particle
frames; the project also has assorted voxel textures, Kenney impact sounds and
additional model packs. See `ASSET_TEXTURE_CATALOG.md` for actual filenames.

- **Immediate reuse:** supplied torch/door/sapling/building textures; existing
  wool/wood/food textures; mob atlases; station GUI and explosion particle images.
- **Medium-term reuse:** rails, redstone/piston/hopper assets, brewing/enchanting
  imagery, boat/mob atlases and Nether/deepslate materials. Model dimensions,
  collision, state variants and animation still need implementation.
- **Later reuse:** dimension/boss/specialized creature imagery where present;
  validate each species' atlas and model layout before registering it.

Availability does not establish permission to redistribute a pack. Record the
pack's actual author/license/source before publishing; Kenney pack licensing does
not establish the license of unrelated folders. Research model references are
documented separately in `mods/basic_survival/MOB_MODEL_REFERENCES.md`.

## 7. Validation and handoff rules

For each batch, record implemented behavior, intentional adaptation, limitations,
save migration and relevant test scenes. Test the actual gameplay command/UI path,
not only the lower-level service: the summon bug passed earlier service checks
while failing through the console resolver and a real populated world.

Require new-world and existing-world checks; host/client parity; late join;
restart/reconnect; full inventories; unloaded chunk boundaries; and save-failure
handling when the change affects these paths. Use appropriate visual previews for
new models/materials. Add meaningful focused tests rather than repeating every
test after an unrelated cosmetic change.

Performance milestones should measure long exploration sessions, dormant actors,
active projectiles, lights, flowing cells, scheduled updates and snapshot traffic.
Set numeric budgets after profiling the target machine, not by guessing an FPS
promise. Large automation farms need bounded queues and chunk-level interest.

Before starting Terraria/shooter/RPG modules, aim to finish stages 0–7 if the goal
is a strong shared survival foundation. If the user's requirement remains broad
Minecraft coverage first, continue through stages 8–11; do not label the earlier
milestone as “all Minecraft features.” Later modules can reuse every service above
without inheriting Minecraft-specific recipes or AI rules.

## Reference links

- [Minecraft official beginner guides](https://www.minecraft.net/en-us/minecraft-tips-for-beginners)
- [Minecraft official crafting guide](https://www.minecraft.net/en-us/article/how-craft)
- [Minecraft official game-mode guide](https://help.minecraft.net/hc/en-us/articles/360058743992-Minecraft-Differences-Between-Creative-Survival)
- [Mojang sample entity geometries](https://github.com/Mojang/bedrock-samples/tree/main/resource_pack/models/entity)

Implementation order and completion criteria above are project-specific design
recommendations, not a claim that Minecraft uses the same architecture.
