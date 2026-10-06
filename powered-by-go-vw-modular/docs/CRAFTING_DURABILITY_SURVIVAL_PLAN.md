# Crafting progression, item condition, survival and combat

Status: single-player first release implemented and tested, 2026-10-06. This extends INVENTORY_AND_STATIONS_PLAN.md using the current
implementation; historical eight-slot and click-only descriptions there are stale.

## Target experience

Gather wood, hand-craft basic supplies and a bench, build wooden tools, mine
stone, build a furnace, use fuel to refine ore, and upgrade tools and armor.
Equipment has individual condition and can be repaired. Players take damage,
heal, fight, die and respawn. Terraria stations, shooter equipment and RPG
modifiers use the same underlying services and persistence.

## Baseline before implementation

- Inventory has ten hotbar slots, 24 backpack slots, five equipment slots,
  cursor ownership, metadata-aware transfers, recovery and versioned saves.
- SlotContainer already preserves instance_id and prevents instance stacking.
  Instance creation, condition mutations and effective equipment stats are absent.
- CraftingService already commits ingredients/output atomically. Recipes are
  currently available without station context; ore refining is instantaneous.
- Material tool tiers and mining restrictions already exist. Holding primary
  input now repeats accepted hits; durability must follow those accepted actions.
- FrontierVitals owns hunger, stamina, food and poison-related resource drain.
  DamageReceiver offers basic health/depletion, but there is no complete player
  survival, armor, melee or respawn policy.
- Manual world drops are single-player. Shared inventory authority, persistent
  interactive stations and a custom-world multiplayer handshake remain unfinished.

## Architecture and execution order

Core exposes small generic services through ModAPI: container commands,
world-scoped block entities, recipe context, item instances/effective stats,
damage and lifecycle operations. Mods own stations, progression recipes,
material balance, survival rules, UI and presentation. Keep terrain queries
inside the existing voxel adapter; do not add ability rules to PlayerController.

Build each milestone through the same command interface in single-player.
Multiplayer activates only after its authoritative validation and replication
are implemented and tested. Do not claim local transactions are shared authority.
Complete these milestones sequentially, with the authority groundwork first.

## Milestone 0: shared state and station groundwork

Finish the relevant prerequisites from the inventory/stations plan:

- Stable world/player identity, world configuration handshake, versioned
  world-scoped entity storage and reconnect routing.
- Server-owned container commands, request IDs, revisions, deduplication,
  reach/access checks and owner-only inventory replication.
- Mining-hit validation on the server: target, tool, timing, accumulated damage
  and resulting break. Placement, loot and crafting use the same ownership path.
- Block entity registration and persistent state independent of chunk visuals.
  Reuse SlotContainer for stations and chests. Station destruction transfers
  contents once and invalidates open interfaces.

Acceptance: simultaneous actions, replayed requests, disconnects and restarts
cannot duplicate items. A client cannot invent a stack or change another player's
inventory. Existing worlds and inventory migrate with backups and no lost items.

## Milestone 1: hand crafting and workbench progression

Extend recipe records with a method, station capability, optional grid pattern,
ingredients, output and processing duration. Existing registrations remain valid
through a backward-compatible default; explicitly classify bundled recipes.

- Hand crafting: planks, sticks, basic supplies and a workbench, accessible from
  inventory. Use a 2x2 grid with recipe suggestions.
- Workbench: 3x3 crafting grid, tools, weapons and equipment. A valid nearby
  bench grants the required capability; a UI-open flag cannot grant access.
- Revalidate station existence, distance, ingredients and output capacity when
  committing each craft. Preview and execution use the same matching rules.
- Show unavailable recipes with a concrete missing ingredient/station reason.
  Output preview does not own a real item; clicking commits a transaction.
- Grid inputs remain owned container slots. Closing, walking away, destruction
  or disconnect returns ingredients to inventory or existing recovery storage.

Acceptance: a new world can reach stone tools from gathered wood without starter
equipment; hand crafting cannot bypass bench requirements; full output capacity,
ambiguous patterns and cancelled operations preserve all ingredients.

## Milestone 2: fuel-based smelting and material upgrades

Add a furnace block entity with input, fuel, output, selected processing recipe,
remaining burn time and processing progress. Fuel declares burn duration; recipes
declare input/output and time. Server ticks state even when the UI is closed.

- Initial fuels: wood/planks, coal and charcoal; include charcoal production.
- Move ore-to-ingot and applicable cooked food recipes out of instant crafting.
- Establish an initial wood -> stone -> iron/steel -> diamond progression.
  Retain bronze as an alternate route and existing advanced materials as later
  branches; tune ore gates only after checking every required recipe is reachable.
- Output blockage stops processing/new fuel consumption. Already-lit fuel keeps
  burning while the world is running. No processing or burning while the game is
  closed in the initial release. Save partial recipe and burn state explicitly.
- Changing input invalidates progress for the previous recipe. Breaking a furnace
  drops its contents and block once; queued completions cannot also award output.
- UI shows recipe progress, burn time and reasons for inactivity.

Acceptance: fuel is required, item counts are conserved, state survives reload
and chunk unloading, and destruction/full output cannot grant free ingots.

## Milestone 3: item instances and durability

Introduce an instance factory and validated mutations around existing records:
item definition ID, unique instance_id, count=1, versioned condition and modifier
metadata. Mint IDs on the authority. Definitions own base stats/max condition;
instances store only approved overrides and current state.

- Crafted and rewarded tools/weapons/armor receive individual IDs. Moving,
  equipping, dropping, recovering and reloading preserves the same instance.
- Migrate existing non-instance equipment into individual records without losing
  quantities; excess equipment goes to persisted recovery. Preserve unknown mod
  metadata rather than deleting it. No arbitrary executable data is loaded.
- Consume tool condition on accepted mining hits, weapon condition on successful
  melee hits, and armor condition on mitigated damage. Empty swings, cancelled
  hits and rejected network requests do not spend condition.
- At zero condition retain a visibly broken item that cannot perform its equipment
  function. Repair restores that same item; the policy stays configurable.
- Repair station/anvil consumes compatible material atomically, restores bounded
  condition and preserves instance ID/modifiers. Show the cost before committing.
- Add condition bars and detailed tooltips. Compute effective stats in a shared
  resolver with bounded additive/multiplicative modifiers and defined ordering.
- Start with a few data-defined modifiers such as mining speed, damage and
  durability. Provide extension points for enchantments and attachments later;
  ammunition remains a separate consumable system.

Acceptance: identical tools with different condition remain separate; replayed
actions cannot spend condition twice; repairs cannot duplicate items or change
identity; old saves and unknown mod records remain recoverable.

## Milestone 4: complete survival

Expand the shared damage contract with source/target IDs, damage type, amount,
impact and operation ID. Authority validates damage; mods can apply rules through
documented hooks. Reuse DamageReceiver as an adapter to the shared health model.

- Health, maximum health, hurt feedback and a health HUD; authoritative health
  snapshots rather than client-reported damage totals.
- Fall damage from landing history, with a configurable safe distance. Reset
  tracking on spawn/teleport; resolve water and other cushioning rules explicitly.
- Oxygen based on head immersion queried through the voxel adapter. Oxygen
  drains underwater, recovers above water, and applies timed drowning damage.
- Food retains hunger restoration. High hunger enables paced regeneration;
  healing items apply validated effects. Starvation and poison use the damage
  pipeline rather than only resource drain.
- Equipment contributes armor through the stat resolver. Damage types specify
  what armor can mitigate; ordinary armor does not block drowning/starvation.
- Persist health, hunger, condition and remaining effects per player/world.
  Avoid one-frame HUD or effect resets when restoring a session.

Acceptance: damage cannot heal accidentally or go below zero; effect ticks remain
consistent at different frame rates; landing, teleport, immersion, healing and
armor all have deterministic focused tests and multiplayer checks.

## Milestone 5: melee, death and respawning

- Melee validates reach, line of sight, cooldown, equipped instance and damage
  stats. Select an entity target before mining so one swing cannot both attack
  an entity and damage the block behind it. Include knockback and hurt cooldowns.
- Route pistol hits and future projectiles through the same damage rules.
  Replicate authoritative hit results and cosmetic feedback separately.
- Death is a single transition: stop input/action processing, invalidate pending
  station actions, settle cursor ownership, then resolve inventory exactly once.
- Initial default: drop carried/equipped items as persistent world loot; offer a
  keep-inventory setting. Never award both the drop and the respawned item.
- Add death screen and explicit respawn action. Validate a safe world spawn
  position, restore health/oxygen, clear temporary effects, and briefly prevent
  repeated spawn damage. Reuse the chosen world; do not create a default world.
- Death drops require the authoritative dropped-item work from milestone 0.
  Persist/reconnect around death without repeating the inventory transfer.
- Start combat verification with a mod-owned target dummy/test enemy; AI and
  broad enemy content can follow after the combat loop is sound.

Acceptance: simultaneous lethal hits produce one death/drop transaction; dead
players cannot craft/mine/attack; reconnecting before or after respawn preserves
the correct state; two peers see consistent health, equipment and respawns.

## Delivery and verification

Deliver one playable milestone at a time, document public contracts and migrations,
and run the project in the target Godot/Zylann build. Add meaningful transaction,
instance, recipe, furnace, environment and combat tests plus two-peer scenarios.
Retain existing inventory, mining, world-save and multiplayer presentation checks.
Visually verify station interfaces, condition/health HUDs, damage and death states.

Final end-to-end check: start with an empty inventory, craft a bench and tools,
obtain fuel/ore, smelt and upgrade, wear down/repair a tool, equip armor, take/heal
damage, fight, die, recover loot and reload/reconnect without loss or duplication.

After these milestones, Terraria adds station capabilities and material routes;
shooters add weapon instances, attachments, ammunition and projectiles; RPG mods
add stat modifiers, status effects and progression. Avoid separate inventories,
health pools or conflicting persistence systems for each module.


## Implementation status, 2026-10-06

The first release provides empty-start hand crafting, nearby workbench requirements,
fuel-based furnace processing with persistent contents, individual tool IDs and
condition, material repairs, armor, melee against DamageReceiver entities, health,
fall damage, drowning, healing, hunger/poison effects, death and respawn. Inventory,
station state and survival data share a versioned local world snapshot.

Gameplay lives in crafting_progression, equipment_condition and player_survival
mods. Generic core APIs supply atomic container operations, item-instance stats,
station records, validated commands and player action/lifecycle hooks.

This is a partial implementation of the larger plan. Shared multiplayer authority,
stable network ownership, inventory RPCs and crash-atomic terrain/drop transactions
remain unfinished. New progression/survival interactions are single-player only.
Death retains inventory. Shaped crafting grids, modifier acquisition, attachments,
repair workstations, death loot, checkpoints and enemy AI remain future milestones.

Validation: crafting/station and equipment suites, survival/combat physics tests,
actual game/world save-reload tests, inventory, mining, world catalog/deletion and
multiplayer presentation regression checks. Fixtures use isolated save locations.

