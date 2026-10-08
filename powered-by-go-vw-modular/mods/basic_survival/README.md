# Part 1: core survival content

Reuses existing IDs, terrain/ores, furnaces, station storage, shaped crafting,
item condition, armor/food stats, entity AI/persistence, and multiplayer authority.

## Integrated content

- Pig, cow, sheep, chicken, zombie, skeleton, creeper and spider. New animals and
  spider use textured cuboids with the shared roaming/fleeing/chase/melee AI.
  Canonical zombie/creeper summon aliases retain saved `box_*` definitions.
  Skeleton natural spawning is enabled for this requested survival content set.
- Nine wood families: oak, spruce, birch, jungle, acacia, dark oak, mangrove,
  crimson and warped. Seven overworld tree families generate in new chunks;
  Nether stems are currently craftable/testable building materials, not generated.
- Shared `core:logs`, `core:planks` and `core:stone` recipe selectors. All wood
  planks interchange, all logs support existing hand recipes; cobblestone works
  in stone tools/furnace recipes. Stone drops cobblestone; smelting restores stone.
- Existing terrain, glass, coal/iron/copper ores, workbenches and furnaces reused.
- Durable iron/copper tool sets and wood/stone/iron/copper hoes. Existing tool
  tiers and iron/diamond armor retained. Leather armor uses existing equipment,
  protection, condition and repair services.
- Bow, arrows, flint, string, feathers, leather, wool, eggs, sugar, crop seeds,
  wheat, meat/cooking recipes, baked potatoes, melon slices and pumpkin pie.
- 27-slot chests reuse the saved station container and transfer interface.

## Controls and progression

- Wood logs -> planks -> sticks/workbench; place ingredients in the shaped grid.
  Chest: plank ring. Bow: three sticks and three string in the curved bow layout.
  Arrows: flint above stick above feather. Hoes: two material cells above sticks.
- Right-click with a hoe on exposed dirt/grass to till it. Right-click farmland
  with wheat/beetroot/pumpkin/melon seeds, carrot or potato to plant.
- Loaded crops advance every 15 seconds (wheat seven advances; others three).
  Break mature crops for produce and seeds. Crops save as terrain stages; farm
  changes also have a per-world sidecar for multiplayer catch-up. Growth pauses
  outside loaded terrain and while the game is closed. There is no hydration,
  light-level or seasonal growth simulation in this minimal version.
- Leaves provide seeds, gravel provides flint, spiders provide string, chickens
  provide meat/feathers/eggs, cows provide meat/leather, sheep provide meat/wool.
  Sugar currently has a simple wheat recipe; pumpkin/melon use the generic crop
  growth/harvest system rather than separate fruit-spreading stems.
- Right-click with a bow to shoot: consumes one arrow, wears the bow, has a
  0.6-second cooldown and 32-block ray range. This first implementation uses
  instant ray damage, not physical arrow flight/charging. Skeletons retain shared
  melee AI; ranged skeleton attacks are a future extension.
- Creepers approach using shared pathfinding, then flash/swell during a 1.5-second
  fuse within 2.6 blocks. Moving beyond 3.8 blocks or breaking line of sight
  defuses them. Detonation destroys loaded blocks whose centers lie in a 2.3-block
  sphere and damages players within 4.5 blocks with distance falloff (maximum 12),
  armor protection and a short outward/upward launch. Walls block player damage.
  A generated blast sound, cube particles and brief light flash play on each peer.
  Death is saved before the blast; self-detonation awards no creeper kill loot.
  Destroyed container contents become world pickups. Craters use the existing
  terrain save and cell-change sidecar, including multiplayer late-join replay.
- Right-click a chest to open storage; select an inventory stack, then click a
  chest slot to deposit. Deselect the carried stack to retrieve. Right-click
  transfers one; left-click transfers a stack. Contents save with stations and
  return through the existing station destruction/recovery mechanism.
  Like the existing furnace UI, chest access is currently single-player/host;
  remote station panels remain unavailable. Bows and farming support clients.

Existing generated terrain remains intact; wood diversification appears in new
chunks. Console examples: `/summon cow`, `/summon chicken`, `/summon spider`,
`/give survival:chest`, `/give survival:bow`, `/give survival:arrow 64`,
`/give frontier:wood_hoe`, `/give survival:wheat_seeds 16`.

## Verification

- `BasicSurvivalSmoke.tscn`: eight mob visuals, hoe wear, planting/growth/harvest,
  crop persistence, chest/container/UI persistence, actual bow ray damage,
  ammunition/cooldown and asset references.
- `BasicSurvivalNetworkSmoke.tscn`: authenticated host/client bow, inventory,
  hoe/seed/growth replication and farm snapshot catch-up.
- `BasicSurvivalPreview.tscn`: rendered mob, wood/chest and crop-stage preview.
- `CreeperSmoke.tscn`: fuse/escape, damage/launch, spherical destruction, saved
  death/cells, sound/particles and reference model proportions.
- `CreeperNetworkSmoke.tscn`: actual ENet fuse/effect/health/knockback/cell sync.
- `MobExplosionPreview.tscn`: front/side mob texture and explosion render.
- Existing crafting/station, creature simulation/network and world lifecycle tests.
