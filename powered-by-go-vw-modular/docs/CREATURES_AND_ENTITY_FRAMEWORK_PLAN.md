# Creatures and reusable entity framework

Status: first creature release implemented and verified, 2026-10-06. The original
milestones below remain as the design reference; delivery details follow at the end.

## First playable release

One passive pig and one hostile melee skeleton. Both spawn on valid loaded
terrain, move with collision and gravity, animate, receive damage, die and leave
collectible world drops. The pig wanders and flees when hurt; the skeleton detects,
chases and attacks a living player, then returns to its territory when pursuit ends.
Initial balance is provisional: pig 10 health, skeleton 20 health, skeleton attacks
for 3 damage with a 1.2-second cooldown and visible wind-up. No breeding, ranged
attacks, bosses, NPC dialogue or day/night dependency in the first release.

## Current project findings

- DamageReceiver already lets player melee damage an opt-in collider. Reuse it.
- player_survival already supplies armor, hurt cooldown, death and respawn. Enemy
  attacks must use its damage receiver, rather than writing player health directly.
- World/player lifecycle events can create and clean up mod-owned runtime nodes.
- VoxelWorldService is the terrain boundary. Creature mods must not call Zylann.
- InventoryDrops currently supports local inventory-origin drops, not a public
  creature-loot API. It has separate persistence from the local inventory snapshot.
- New survival/combat remains single-player. Entity replication alone cannot make
  inventory transfers and rewards authoritative in multiplayer.

## Asset findings and choices

| Purpose | Available or researched assets | Decision |
| --- | --- | --- |
| First enemy | Uploaded KayKit_Skeletons_1.1_FREE: Skeleton_Minion, Warrior, Rogue, Mage GLBs, weapons, textures; included CC0 license | Use Minion, optionally holding Skeleton_Blade. Save others for variants. |
| Locomotion and reactions | Uploaded Rig_Medium_MovementBasic and Rig_Medium_General GLBs | Contains walk/run/jump, idle/hit/death/spawn clips. Character GLBs have no embedded clips; attach compatible animation libraries and verify bone paths. |
| Skeleton attack | [Current KayKit Character Animations](https://kaylousberg.itch.io/kaykit-character-animations) | Free CC0 melee sets are available. Download the current Rig_Medium melee set; included local animation files do not contain attacks. The old kaykit-animations page is explicitly legacy. |
| Passive pig, preferred blocky style | Uploaded entity/pig/pig.png; also cow, sheep and chicken textures | These are textures, not creature meshes. Build an original cuboid pig rig and procedural gait. The supplied README says Minecraft textures 1.19 and contains no demonstrated reuse license: use an original pig skin for a distributable build unless permission is established. |
| Passive animal alternative | [Quaternius LowPoly Animated Animals](https://quaternius.itch.io/lowpoly-animated-animals) | Free CC0 farm-animal pack; author lists idle/walk/run/jump/death, FBX/Blend/OBJ. Verify actual clips after download, import animated FBX or convert Blend to GLB; OBJ does not retain skeletal animation. Low-poly style differs from blocky terrain. |
| Blocky animal alternative | [Kenney Cube Pets](https://kenney.nl/assets/cube-pets) | Free CC0 3D animated pets. Useful for later companions; inspect downloaded species and clips before choosing it for farm animals. |
| Future NPCs | Uploaded KayKit_Adventurers_2.0_FREE characters | Reuse existing humanoid models and matching rig animations, with dialogue/shop behavior layered later. |
| Effects/audio | Uploaded Kenney particle pack and impact sounds | Reuse impact/death effects and hit sounds; inspect specific files. Animal calls are a separate asset gap. |

[KayKit Skeletons source](https://kaylousberg.itch.io/kaykit-skeletons) confirms
the free four-character CC0 pack. Skeleton Golem and Necromancer are paid EXTRA
content and are not in the uploaded free pack; neither is needed for this release.
No downloads or purchases were performed for this plan. Local GLB animation names
were inspected from their JSON chunks; final rig compatibility needs engine QA.

## Framework architecture

Create a reusable entity-framework mod and a separate first-creatures content mod.
Use namespaced definitions, declared dependencies and api.load_asset. Only add
small generic ModAPI extension points if current services cannot express the need.

- EntityDefinition: logical ID, visual scene, collision dimensions, health, speeds,
  faction, perception, behavior profile, attacks, spawn rules and loot table.
- EntityActor: CharacterBody3D with stable world entity ID, DamageReceiver,
  locomotion, animation adapter and composed behavior components.
- EntityRuntime: registry, creation/removal, simulation budgets, world lifecycle,
  saved records and future server ownership. No creature-specific ID switches.
- Behavior: simple explicit states idle, wander, flee, investigate, chase,
  wind-up, attack recovery and dead. Optional abilities supply later projectiles,
  boss phases or NPC interactions without replacing locomotion or health.
- Animation adapter: logical idle/walk/run/hurt/attack/death names map to actual
  model clips. Gameplay owns attack timing; visual animation never awards damage.
- Events: spawned, damaged, died and despawned carry stable IDs and context.
  Despawn/unload must never count as death or award loot.

## Milestone 1: asset and framework vertical slice

Import one skeleton and pig, normalize scale/orientation/feet origin, verify
shadows, skeleton tracks, attachment points and collision. Create one actor with
health, movement, hit reactions and an idempotent death transition. Harden generic
damage intake against non-finite amounts before exposing it to more actors.

Acceptance: player tools damage both actors through the existing combat path;
health cannot become NaN; death happens once; visual state follows actual velocity.

## Milestone 2: movement on editable voxel terrain

Start with grounded collision movement, local obstacle probes, one-block step/jump,
ledge and water avoidance, and bounded stuck recovery. Do not teleport creatures
through walls. For skeleton pursuit, add bounded local grid pathfinding through a
generic terrain query API when straight-line steering cannot pass obstacles.
Revalidate steps after block edits and pause at unloaded terrain boundaries.
Avoid a world-wide navigation rebake whenever a player places a block.

Acceptance: walk over slopes/steps, go around walls, avoid unsafe drops, respond
to placing/breaking blocks, and recover from a blocked route without flying or
leaving loaded terrain. Path searches have distance/node/time limits.

## Milestone 3: passive pig

Alternate idle and short wander goals. Flee from the attacker after damage for a
bounded time, then resume wandering. No attacks or player pursuit. Introduce raw
meat as an ordinary namespaced item, with a furnace cooking recipe and existing
food integration; pig death drops a small configurable amount.

Acceptance: passive behavior stays passive, fleeing has a clear visual response,
food drops can be picked up/cooked/consumed, and full inventories leave loot in
the world rather than discarding it.

## Milestone 4: hostile melee skeleton

Detect living targets by range and line of sight. Chase within a home/leash radius.
Stop to wind up, then check reach, obstruction and target validity at the actual
hit moment. Apply one hit per attack through DamageReceiver, honor armor and hurt
cooldown, then recover. Cancel attacks on death, target death or world unload.
Drop bones on death, usable initially as a crafting ingredient; recipes can grow later.

Acceptance: walls block detection/hits, fleeing beyond the leash ends pursuit,
dead players are ignored, frame rate does not multiply damage, and tool durability
continues to follow accepted player attacks.

## Milestone 5: spawning, persistence and loot

Spawn controller samples loaded ground around players on a budget. Validate
support, headroom, collision, water and distance from players. Provisional bounds:
24–64 metres, at most 8 pigs and 6 skeletons near one player; expose these as
configuration and tune in the actual world. Use surface/biome rules first; add
night/light-dependent rules only after a genuine light/time query exists.

Give persistent actors stable IDs. Save definition, position, health and essential
behavior/home data; rebuild transient targets and paths on load. Dormant records
count toward population limits so unloading/reloading cannot create duplicate herds.
Unknown mod records survive round trips. Never spawn into an unready chunk.

Add a generic world-loot operation, retaining the existing pickup behavior. Persist
death and its loot receipt as one recoverable commit: entity ID/death sequence is
the deduplication key, and recovery replays missing drops exactly once. Define
pickup/save failure rollback; do not rely on separate best-effort creature/drop
JSON writes. World deletion must include any new sidecar, temp and backup files.

Acceptance: save/reload preserves health and identity, dead creatures stay dead,
chunk cycling respects caps, repeated death callbacks/recovery do not duplicate
loot, full inventory and write failure cannot lose or duplicate items.

## Milestone 6: multiplayer and extensibility

Ship the initial vertical slice explicitly in single-player. Then connect entity
simulation to the host/server: clients interpolate transforms and animation state;
only the authority chooses targets, validates hits, applies damage and creates loot.
Use stable entity IDs, spawn/despawn messages, late-join snapshots and sequence
numbers. Loot pickup integration depends on the existing inventory-authority work;
do not claim multiplayer creatures complete while rewards remain client-owned.

Exercise the framework with a second definition using existing components, then
document boss phase/ability and NPC interaction extension points. Actual boss AI,
dialogue, shops, breeding and taming are later content, not required infrastructure.

## Verification and delivery order

1. Deterministic framework health/death/attack tests with fake terrain and targets.
2. Actual Godot/Zylann scenes for collisions, step/path behavior and edited blocks.
3. Persistence and loot failure/replay fixtures in isolated world directories.
4. Rendered inspection of pig gait, skeleton attack, hit/death clips and held weapon.
5. Existing mining, inventory, durability, survival and world-deletion regressions.
6. Profile a population near the configured cap; throttle sensing/pathfinding and
   dormant actors. Add network latency/late-join tests during multiplayer milestone.

First implementation sequence: framework + skeleton asset test, pig movement,
skeleton combat, spawning, recoverable persistence/loot, then multiplayer authority.

## Delivered implementation

- Framework: EntityRegistry/ModAPI plus mod-owned runtime, stable IDs, health,
  animation adapters, ability composition, persistent ability state and interaction hooks.
- Pig: original blocky mesh/materials and gait, wandering, fleeing, raw pork drops,
  furnace cooking and existing food integration.
- Skeleton: uploaded KayKit Minion, walk/run/hit/death clips and an original
  procedural arm strike. No external animation-pack download was required.
- Movement: collision/gravity, bounded grid routes, step/jump, water/ledge avoidance,
  edited-waypoint checks, unloaded-terrain pausing and bounded stuck retry.
- Spawning: validated loaded ground, player separation, species caps and dormant
  records. Default range changed to 24–48 metres to fit existing terrain loading.
- Persistence/loot: single-player combined snapshot and network host creature ledger,
  atomic death/reward records, rollback on save failure, server-owned profile inventory,
  receipt-based delivery and backups. World deletion covers the new sidecar.
- Multiplayer creatures: host AI, validated hits/tool stats/condition, health/death/
  respawn, 5-Hz interpolated snapshots, stale-sequence rejection, late snapshots,
  authoritative slot/cursor operations and private-credential reconnect ownership.
- Extension proof: a third test NPC definition uses the ability and interaction
  hooks and serializes its custom state. Actual bosses/NPC content remains deferred
  exactly as described in the first-release scope.

Verified in Godot 4.7.1/Zylann: deterministic creature suite; actual voxel-world
movement/edit/spawn/reload scene; real ENet host/client/reconnect suite; rendered
models/shadows/attack pose; inventory, crafting, durability, survival, mining,
world-deletion and multiplayer presentation regressions.

Limits: shared furnaces/manual network dropping and broader environmental/hunger
authority are not completed by this creature release. Terrain SQLite and the older
manual-drop persistence remain outside the creature transaction. First-time server
profiles start empty; previous local multiplayer inventory is backed up separately.
Detailed contracts and limits are in mods/entity_framework/README.md.
