# GO.VW implementation tickets and Luna prompts

Prepared 2026-10-08 from the actual project. Initial status: all 30 tasks were **TODO**; the execution index records subsequent completion. This file describes planned work, not proof that a feature exists. Architecture and preservation rules: [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md).

Project root: `C:/Users/Admin/Downloads/powered-by-go-vw-modular-steve-tools/powered-by-go-vw-modular`. Paths are project-relative. Every new path and API in these tickets is **proposed** until its prerequisite ticket lands. Listed existing paths were located/inspected. Do not assume a proposal exists in a later session; check the prerequisite's status and interface first.

Read `AGENTS.md`, `docs/AI_MODDING_GUIDE.md`, `docs/ARCHITECTURE.md` and `mods/_template/mod.gd`/`mod.json` once per implementation session. Preserve existing modified/untracked files. Ordinary blocks stay voxels. Mods use `ModAPI`, logical IDs, lifecycle/events and mod-relative asset helpers. No engine upgrades, numeric voxel enums, `Global`, unrelated player rewrites, broad renames or new external dependencies.

## Execution index

| ID | Title | Prerequisites | Model | Complexity | Status |
| --- | --- | --- | --- | --- | --- |
| T01 | Bounded headless smoke runner | Existing test scenes | Luna Light | Low | DONE — default suite 3/3; timeout and invalid-path checks |
| T02 | World mode and experimental flags | T01 | Luna Medium | Medium | DONE — profile/menu integration; world-save suite passed 15 tests |
| T03 | Searchable creative catalog | T02 | Luna Medium | Medium | DONE — catalog mod and authority grant smoke passed |
| T04 | Optional validated content pack loader | T01 | Luna Medium | Medium | DONE — JSON schema, staged cube loader and atomicity smoke passed |
| T05 | Eight decorative building blocks | T03, T04 | Luna Light | Low | DONE — pack loads; 8 blocks and recipes registered at startup |
| T06 | Industrial materials and shaped recipes | T04 | Luna Light | Low | DONE — pack loads; 4 items and 3 recipes registered at startup |
| T07 | Furnace kind isolation | T01 | Luna Light | Low | DONE — direct/runtime guard; station and host furnace smoke |
| T08 | Recoverable shared station commands | T02, T07 | Sol | High | TODO |
| T09 | Client station UI and live views | T08 | Luna Medium | Medium | TODO |
| T10 | Generic machine registration and processing | T02, T04, T07 | Luna Medium | Medium | DONE — reusable registry/runtime; MachineSmoke passed |
| T11 | First manual crusher | T06, T10 | Luna Light | Low | TODO |
| T12 | Energy ports and bounded connectivity | T10 | Luna Medium | Medium | DONE — bounded graph service and EnergySmoke passed |
| T13 | Conserving energy allocation | T12 | Sol | High | TODO |
| T14 | Fuel generator | T06, T13 | Luna Light | Low | TODO |
| T15 | Battery block | T13 | Luna Light | Low | TODO |
| T16 | Electric furnace | T14, T15 | Luna Light | Low | TODO |
| T17 | Electric crusher variant | T11, T14 | Luna Light | Low | TODO |
| T18 | Adjacent item transfer | T08, T10 | Luna Medium | Medium | TODO |
| T19 | Filtered transfer pipe | T18 | Luna Light | Low | TODO |
| T20 | Shared terrain replay and blast service | T01, T02 | Luna Medium | Medium | TODO |
| T21 | Output-safe mining drill | T17, T18, T20 | Luna Medium | Medium | TODO |
| T22 | Fused TNT block | T06, T20 | Luna Light | Low | TODO |
| T23 | Shared traveling projectiles | T01, T02 | Luna Medium | Medium | TODO |
| T24 | Skeleton ranged ability | T23 | Luna Light | Low | TODO |
| T25 | Powered defensive turret | T13, T23 | Luna Medium | Medium | TODO |
| T26 | Sparse fluid tank and pump | T10, T13 | Luna Medium | Medium | TODO |
| T27 | Sprinkler accelerates crops | T26 | Luna Light | Low | TODO |
| T28 | One deterministic multiblock | T10, T16 | Luna Medium | Medium | TODO |
| T29 | Chunk-safe ruin blueprint stamps | T02, T04 | Luna Medium | Medium | TODO |
| T30 | Three configured creature variants | T24 | Luna Light | Low | TODO |

No task in this index depends on a later task. A task marked Light is intentionally definition/configuration work over an established contract; do not invent missing prerequisite APIs. After completion update only its status and a short evidence note: `DONE — files; test commands/results; known limits`.

## Contracts shared by the tickets

**Existing:** `api.content`, `events`, `world`, `edits`, `crafting`, `saves`, `stations`, `inventory_commands`, `item_instances`, `entities`, `storage`; `register_block`, `register_item`, `register_recipe`, `on`, `off`, `asset`, `load_asset`.

**Existing station/stack methods:** `register_kind(block_id, capabilities, slots)`, `ensure(pos)`, `record(id)`, `container(id,name)`, `accessible(actor,id)`, `ids()`, `update_state(id,state)`, `remove(id)`, `mark_dirty()`, `save()`. `SlotContainer` has `snapshot`, `restore`, `stack_at`, `insert`, `take`, `transfer_to`, `exchange_to`, `set_filter`, `revision`. Verify argument/return details in their source before use.

**Proposed by T02:** `WorldProfileService` exposed as `api.profile`, with `activate(config)`, `clear()`, `mode() -> String`, `enabled(id) -> bool`, `snapshot() -> Dictionary`, `set_replica(config)`. Only a trusted host snapshot calls `set_replica` on clients. Profile schema: `{profile_version:1, game_mode:"survival"|"creative", feature_flags:{"industry:machines":bool,"industry:energy":bool,"sandbox:explosives":bool,"combat:projectiles":bool,"industry:fluids":bool,"world:structures":bool}}`. Older worlds default survival/false. Flags are chosen for new worlds or edited in metadata while closed; no runtime toggle UI in T02.

**Proposed by T04:** content schema v1 has arrays `blocks`, `items`, `recipes`; block `textures:{side,top?,bottom?,front?}` and `tint:[r,g,b,a]`; item `icon`, `stack_size`, `tags`, `properties`; recipe `id`, `output`, `count`, `ingredients`, `station`, `method`, `duration`, optional `pattern` as rows of logical IDs/selectors/empty strings. `api.register_content_pack(path)` returns `{success:bool,errors:Array,registered:Dictionary}`. Reject the pack before registration when validation fails. Current recipes allow one output; do not introduce multi-output now.

**Proposed by T10:** `api.machines.register(definition)`, `definition(block_id)`, `ids()`. Definition `{block_id, capabilities:[], slots:{input:4,output:2}, method, duration_scale:1.0, energy_per_second:0, feature:"industry:machines"}`. Recipe duration is the base; final duration = base × positive scale. Concrete processing inputs first. New machine records store `machine:{version:1,recipe:"",input_fingerprint:"",progress_seconds:0,status:""}` inside station state, preserving other keys. `MachineRuntime.tick_record(id,delta)` permits deterministic fixtures. Runtime never processes `survival:furnace`. T08 supplies `api.stations.is_locked(id)`; without T08, local machines need no transfer lock and remote interaction remains disabled. T09 is required for shared UI, not local machine production.

**Proposed by T12–T13:** `api.energy` definitions use `{block_id, role:"cable"|"producer"|"storage"|"consumer", capacity:int, transfer_limit:int, faces:[0,1,2,3,4,5]}`. Units are integer abstract energy. `stored(cell)`, `deposit(cell,amount)->int accepted`, `consume(cell,amount)->bool`, `register(definition)->bool`. State under station `energy:{version:1,stored:int}`; definitions for cables need no inventory node. Fixed 0.2-second tick: producers run, network allocation runs, consumers run. Fractional per-tick costs use a carried remainder, never rounding each frame into free energy.

Later proposed interfaces are scoped in their owning tickets. Generic services receive additive wiring in `GameAPI`, `ModAPI` and `ModLoader` only when established. Extend the existing API v1 compatibly. Feature-mod entry points own world nodes and unsubscribe/free on shutdown.

Energy contract clarification: `transfer_limit` is units/second. Optional producer fields are `production_per_second` and `fuel_container`. T13 implements generic fuel producer behavior using existing `fuel_seconds`, saves burn/remainder, validates fuel and pauses at full buffer; T14 only configures it. Energy-only devices may omit a processing method and skip recipe processing.

## First 30 executable tasks

### T01 — Bounded headless smoke runner

- **Objective:** one PowerShell command reliably runs selected existing smoke scenes and fails on timeout, runtime diagnostics or absent expected completion marker.
- **Prerequisites:** existing Godot installation and `tests/*.tscn`; no new framework.
- **Files to inspect:** `tests/InventoryFoundationSmoke.gd`, `WorldSaveCatalogSmoke.gd`, `HostFurnaceSmoke.gd`; installed executable path in the plan; existing `tools` folder.
- **Files to modify:** none of the gameplay files; update this ticket's status after success.
- **Files to create (proposed):** `tools/run_smoke.ps1`, `tools/smoke_suites.json`.
- **Implementation steps:** accept `-GodotPath`, `-Suite foundation` or `-Scenes`, `-TimeoutSeconds` (default 60), `-LogDirectory` optional. Resolve project root from `$PSScriptRoot`; validate paths before running. For each scene start the console executable with `--headless --path <root> res://tests/<scene>.tscn`, hidden window, redirected stdout/stderr and a bounded timeout. Kill only that child on timeout. Require exit 0, no script/parser/assert/load error diagnostics and the scene's configured completion substring. Include the actual existing lowercase `smoke passed` and `World save suite completed` markers, not an invented universal PASS string. Default suite: inventory foundation, world catalog, crafting stations. Print one result per scene and a concise failure tail; exit 1 on any failure. Keep logs in a temporary or chosen directory. No editor launch, destructive cleanup or real-world fixture edits.
- **Assets:** none.
- **Acceptance criteria:** foundation suite succeeds on the existing baseline; invalid executable/scene fail clearly; a stalled/failing process cannot produce success. Custom scenes can supply an expected marker without changing game code.
- **Validation:** run foundation suite; exercise invalid scene/path; use a harmless existing persistent preview to verify timeout rejection. Do not commit a test fixture.
- **Recommended model / complexity:** Luna Light / low.
- **Completion evidence:** `tools/run_smoke.ps1 -Suite foundation` — InventoryFoundationSmoke, WorldSaveCatalogSmoke and CraftingStationsSmoke passed 3/3; invalid Godot and scene paths rejected; RoguePreview stopped at 2s and reported one timeout. HostFurnaceSmoke passed separately. No fixture was added.

### T02 — World mode and experimental flags

- **Objective:** expose a world-scoped profile with creative/survival mode and six initial feature flags; legacy worlds retain current behavior and unknown metadata survives.
- **Prerequisites:** T01.
- **Files to inspect:** `core/world/WorldSaveService.gd`, `scenes/world/World.gd`, `core/ui/MainMenu.gd`, `core/api/{GameAPI,ModAPI}.gd`, `core/modding/ModLoader.gd`, `tests/WorldSaves.gd`.
- **Files to modify:** those six existing service/world/menu files; `tests/WorldSaves.gd` only for metadata round-trip cases.
- **Files to create (proposed):** `core/world/WorldProfileService.gd`, `tests/WorldProfileSmoke.gd`, `tests/WorldProfileSmoke.tscn`.
- **Implementation steps:** implement the shared profile contract above, normalize enums/known bool flags, preserve unknown metadata in the catalog result without letting it overwrite canonical safe ID/valid/seed fields. New-world menu adds mode choice and a single "Enable experimental sandbox systems" checkbox setting the six flags; existing creation defaults stay survival/off. Feed normalized profile from selection into `World` before `WORLD_READY`; clear after world runtimes stop. Wire the same service into every ModAPI context. Keep definitions registered regardless of flag. `set_replica` exists but is not connected to a client-supplied RPC; T03 transmits host profiles. Do not change hunger, terrain generation, compatibility signatures or default-world behavior.
- **Assets:** existing menu controls/theme.
- **Acceptance criteria:** two worlds keep different mode/flag values; old metadata loads as survival/off; arbitrary existing metadata survives; leaving a creative world clears profile; no automatic world is created.
- **Validation:** world profile fixture with separate roots and repeated A→B switching; T01 world/catalog regression; one menu creation check.
- **Recommended model / complexity:** Luna Medium / medium.

### T03 — Searchable creative catalog

- **Objective:** F6 opens a searchable, scrollable catalog of all registered items in a creative world; clicking grants one max-size stack (unique equipment one fresh instance) through authority commands.
- **Prerequisites:** T02.
- **Files to inspect:** `core/ui/InventoryUI.gd`, `core/inventory/{Inventory,InventoryCommandService,ItemInstanceService}.gd`, `core/player/VoxelInteractor.gd`, `mods/debug_console/{mod.gd,Console.gd}`, `mods/entity_framework/EntityRuntime.gd` inventory/join paths, `project.godot` inputs.
- **Files to modify:** `InventoryCommandService.gd`, `core/api/GameAPI.gd` to inject profile, `EntityRuntime.gd` for creative whitelist/profile snapshot. Existing UI/interactor only if its current UI-blocking pattern needs a generic additive guard.
- **Files to create (proposed):** `mods/creative_catalog/{mod.json,mod.gd,CreativeCatalog.gd}`, `tests/CreativeCatalogSmoke.gd/.tscn`.
- **Implementation steps:** mod ID `sandbox:creative_catalog`, dependencies `core:base`, `entities:framework`. Create player-owned CanvasLayer through lifecycle hooks; use a named F6 action, name/ID/tag filter and item icons, reuse existing cursor/mouse/close patterns. Add `creative_grant` to the trusted command service: resolve item server-side, fixed stack limit, `item_instances.prepare` for condition items, all-or-nothing insertion with full-inventory reason. Host adapter accepts only item ID, verifies host world creative, saves before publishing; reject survival clients. On join send profile via authority-only reliable message before enabling catalog. Close restores mouse/controls and blocks mining/placing while open. This ticket provides creative item access, not flight/invulnerability/unlimited placement.
- **Assets:** registered item icons; text fallback when absent.
- **Acceptance criteria:** all registered items are discoverable, full inventory does not lose stacks, unique tools have distinct IDs, survival grants fail, clients cannot self-select creative, F6/E/Esc do not leave mouse stuck.
- **Validation:** local grant/full/condition/rejection fixture; small host/client grant fixture using existing ENet pattern; one visual/input playtest.
- **Recommended model / complexity:** Luna Medium / medium.

### T04 — Optional validated content pack loader

- **Objective:** definitions for cube blocks, items and single-output recipes can be added through schema-v1 JSON without repetitive custom registration code.
- **Prerequisites:** T01.
- **Files to inspect:** `core/api/ModAPI.gd`, `core/content/ContentRegistry.gd`, `core/world/VoxelWorldService.gd`, cube/material construction in `mods/basic_survival/mod.gd`, `mods/shaped_crafting/GridCrafting.gd`, template manifest.
- **Files to modify:** `ModAPI.gd` for `register_content_pack`; `VoxelWorldService.gd` for a generic cube builder; `mods/_template/mod.gd` optional commented example. No legacy mod migrations.
- **Files to create (proposed):** `core/content/ContentPackLoader.gd`, `docs/CONTENT_PACK_SCHEMA.md`, `tests/ContentPackSmoke.gd/.tscn`, small fixture JSON under `tests/fixtures/content_pack/`.
- **Implementation steps:** validate schema, finite/positive numeric fields, IDs, duplicates against existing and pending definitions, asset presence/type, output refs and ingredients/tags against the combined pack + registry before registration. Stage all resources before mutating registry. Register blocks, explicit items, recipes in that order; explicit block items may replace only that pack's generated item. Delegate native model construction to adapter using verified cube/material/atlas operations; nearest filtering and top/bottom/front faces optional. Respect transparency and registry culling behavior. Register explicit patterns through `grid_service.register_pattern` only when grid service is available; a manifest needing patterns declares `crafting:shaped`. Assets use `api.asset/load_asset`; built-in packs may explicitly reference supplied `res://assets/...`, portable packs use relative paths. Return structured errors. Scope deliberately excludes creatures, machines, arbitrary scripts, multi-output recipes and schema migration.
- **Assets:** existing stone/glass textures for fixture; no download.
- **Acceptance criteria:** valid pack adds a block/item/recipe with icon; malformed, duplicate, missing-texture and unresolved-tag packs add nothing; six face textures render correctly; legacy mods load unchanged.
- **Validation:** pack fixture before registry finalization, malformed-pack no-partial-registration cases, existing transparent/shaped smoke; one cube preview.
- **Recommended model / complexity:** Luna Medium / medium.

### T05 — Eight decorative building blocks

Verified assets: seven exact-name textures are present. `smooth_sandstone.png` is absent; use the present `block/sandstone_top.png` on all faces for `building:smooth_sandstone`.

- **Objective:** ship eight usable building variants by data only.
- **Prerequisites:** T03, T04.
- **Files to inspect:** `docs/CONTENT_PACK_SCHEMA.md` (T04), `docs/ASSET_TEXTURE_CATALOG.md`, registry IDs via console/definitions to avoid duplicates, `mods/_template/mod.json`.
- **Files to modify:** only the new pack and its manifest/entry script created by this ticket.
- **Files to create (proposed):** `mods/building_catalog/{mod.json,mod.gd,content.json}`.
- **Implementation steps:** ID `building:catalog`; dependencies `core:base`, `crafting:shaped`. Register `building:polished_granite`, `polished_diorite`, `polished_andesite`, `mossy_stone_bricks`, `chiseled_stone_bricks`, `smooth_sandstone`, `cut_sandstone`, `quartz_bricks` in namespace `building`. Verify each same-name PNG under supplied `block/`; if absent use existing stone-brick texture with a distinct tint and record fallback. Use hardness 1.5, preferred/required pickaxe, level 1, tags `block`, `stone`, `building:decorative`, self-drop, correct icon. Add one simple recipe per block: four `core:stone` → four variant blocks, station workbench, explicit 2×2 stone pattern. Check identical patterns currently yield multiple output choices; if the existing UI cannot select them, give this pack creative access first and defer ambiguous survival recipes instead of changing crafting.
- **Assets:** eight verified PNGs or declared placeholders.
- **Acceptance criteria:** eight distinct IDs visible in creative catalog, correctly textured world/HUD placement and breakable with existing mining rules; no duplicate registry errors or altered legacy stone.
- **Validation:** content loader + mining smoke and a visual placement of at least two variants; no bespoke test mirroring all eight rows.
- **Recommended model / complexity:** Luna Light / low.

### T06 — Industrial materials and shaped recipes

- **Objective:** introduce inputs for machines without a parallel ore/metal progression.
- **Prerequisites:** T04; existing `frontier:survival`, `crafting:shaped`.
- **Files to inspect:** `mods/frontier_survival/mod.gd` resource IDs/icons, `GridCrafting.gd` pattern registration, schema doc.
- **Files to modify:** only this new content pack.
- **Files to create (proposed):** `mods/industry_materials/{mod.json,mod.gd,content.json}`.
- **Implementation steps:** ID `industry:materials`; dependencies `frontier:survival`, `crafting:shaped`. Items: `industry:copper_wire` stack64, `iron_plate` stack64, `machine_frame` stack64, `iron_dust` stack64. Tags `resource`, `industry:material`; iron dust also `industry:ore_dust`. Recipes at workbench: two `frontier:copper_ingot` horizontally → four wire; two `frontier:iron_ingot` horizontally → two plates; pattern `[plate,wire,plate] / [plate,empty,plate] / [plate,plate,plate]` → one frame (seven plates, one wire). Dust has no hand recipe. Reuse copper/iron ingot or nugget icons with labels/tint where supported; do not create tools or change existing ingot smelting.
- **Assets:** verified `item/copper_ingot.png`, `iron_ingot.png`, `iron_nugget.png`; frame uses `block/iron_block.png`.
- **Acceptance criteria:** mixed plank recipe tags remain unchanged; wire/plate/frame craft only with exact counts/patterns/station; creative gives dust; existing iron/copper tool recipes still work.
- **Validation:** shaped crafting smoke plus one craft of each new recipe; registry/manifests/assets validation.
- **Recommended model / complexity:** Luna Light / low.

### T07 — Furnace kind isolation

- **Objective:** a non-furnace station with input/fuel/output never gets processed by the legacy furnace ticker.
- **Prerequisites:** T01.
- **Files to inspect:** `mods/crafting_progression/StationRuntime.gd`, `mod.gd` furnace ID, `BlockEntityService.record`, `tests/CraftingStationsSmoke.gd`.
- **Files to modify:** `mods/crafting_progression/StationRuntime.gd`; `tests/CraftingStationsSmoke.gd`; `core/ui/InventoryUI.gd` to avoid querying the position of a detached test player.
- **Files to create:** none.
- **Implementation steps:** in the runtime loop check `record(id).block_id == "survival:furnace"`; add the same early return in `tick_furnace` so direct callers cannot bypass it. Keep save timer, recipe selection, filters, fuel duration and furnace UI unchanged. Add a fake non-furnace station with furnace-like containers to the existing isolated fixture; direct tick and normal dispatch must leave containers and state identical. The foundation run also exposed a detached inventory owner in InventoryFoundationSmoke; `InventoryUI._refresh_recipes` now waits until its player is inside the scene tree before querying world position.
- **Assets:** none.
- **Acceptance criteria:** real furnace still smelts iron; fake input station does not consume fuel/ingredients or gain furnace state through loop or direct tick.
- **Validation:** crafting station smoke and host furnace smoke via T01.
- **Recommended model / complexity:** Luna Light / low.
- **Completion evidence:** CraftingStationsSmoke passes both direct and `_process` calls on the fake station; real furnace cases and HostFurnaceSmoke pass. Foundation suite 3/3; detached-player recipe refresh no longer emits Godot engine errors.

### T08 — Recoverable shared station commands

- **Objective:** host-authoritative station opening/transfers become usable by clients, with revisions and recovery if a save fails between player and station persistence.
- **Prerequisites:** T02, T07.
- **Files to inspect:** `BlockEntityService.gd`, `InventoryCommandService.gd` station_transfer/receipts, `EntityRuntime.gd` join/inventory/profile saves, `SlotContainer.gd`, `mods/crafting_progression/mod.gd` lifecycle, existing network fixtures.
- **Files to modify:** those three core/runtime services and crafting lifecycle integration; `WorldSaveService.gd` catalog/deletion handling for the journal suffix.
- **Files to create (proposed):** `core/inventory/StationTransferJournal.gd`, `tests/StationNetworkSmoke.gd/.tscn`.
- **Implementation steps:** expose `view(id)` containing cell/kind/state and named `{revision,slots}` snapshots, and request_open/close routing through the existing authoritative runtime. Server resolves sender to its player and checks loaded cell, station kind, alive state and current reach; subscribers are removed on close/out-of-range/disconnect/break. Add station_transfer to the whitelist with operation/index/count only, preserving no-client-stack rule. For a transfer lock that player + station, capture before/after player inventory and station record; write pending journal atomically before mutations are persisted; flush station and authoritative player profile, then mark committed and publish both views. Failure restores before-state and preserves pending entry for retry/recovery; do not accept more station mutation while recovery is unresolved. On startup recover unfinished entries to recorded before-state in both stores before commands; recovery is idempotent. Existing data field formats stay intact. Use unique transaction ID, bounded/reaped committed entries, and existing request receipts to stop retries repeating a successful transfer. Pause processing on involved stations until unlocked. Publish state to all subscribers at ≤5 Hz; events/transfers can publish immediately. Implement only station transactions, not a universal world transaction system.
- **Assets:** none.
- **Acceptance criteria:** two clients cannot withdraw the same final item; unknown/out-of-range/stale requests fail; local and host transfers still work; both stores recover consistently after injected failure at each write boundary; late open sees correct contents.
- **Validation:** ENet fixture for transfer/contention/late-open; journal fixture simulates failures/restart using test roots; inventory, stations and host furnace regressions. Sol reviews invariants before completion.
- **Recommended model / complexity:** Sol / high.

The public lock query established here is `api.stations.is_locked(id)->bool`. T10 and T18 use it; locked station records do not process or accept a second mutation.

### T09 — Client station UI and live views

- **Objective:** the existing chest/furnace screen works on clients and displays authority-provided containers/status.
- **Prerequisites:** T08.
- **Files to inspect:** `mods/crafting_progression/{StationRuntime,StationUI,mod}.gd`, `mods/basic_survival/mod.gd` chest use hook, T08 station view/open/close API.
- **Files to modify:** those four mod scripts; no transaction implementation changes unless a precise integration bug is found.
- **Files to create (proposed):** `tests/StationUISmoke.gd/.tscn`.
- **Implementation steps:** replace host-only open rejection with request_open/pending view; one UI renders `api.stations.view(id)` rather than directly editing a local container. Keep existing click-to-select then transfer behavior. Every operation uses InventoryCommandService and server revisions. Render waiting/stale/unavailable states; close on removed station/death/out-of-range; unsubscribe on close; restore cursor and mouse using existing patterns. Do not add drag behavior to stations in this ticket or redesign the main inventory. Remote UIs do not start furnace processing.
- **Assets:** existing station icons/theme.
- **Acceptance criteria:** a client deposits ore/fuel, sees processing, retrieves ingot; two open screens converge; breaking the station closes both screens; Esc restores gameplay controls.
- **Validation:** StationNetworkSmoke; one actual host/client UI playtest; HostFurnaceSmoke and InventoryUISmoke.
- **Recommended model / complexity:** Luna Medium / medium.

### T10 — Generic machine registration and processing

- **Objective:** one processing runtime can run differently configured machines using existing station records, containers and recipes.
- **Prerequisites:** T02, T04, T07; T08–T09 additionally gate shared interaction.
- **Files to inspect:** `BlockEntityService.gd`, `SlotContainer.gd` exchange_to, `CraftingService.gd` method filtering, T08 transaction lock/view, old furnace tick, lifecycle wiring.
- **Files to modify:** `core/api/{GameAPI,ModAPI}.gd`, `core/modding/ModLoader.gd` additive machine registry wiring; StationUI only to show generic processing status/progress through views.
- **Files to create (proposed):** `core/machines/MachineRegistry.gd`, `mods/machines/{mod.json,mod.gd,MachineRuntime.gd}`, `tests/MachineSmoke.gd/.tscn`.
- **Implementation steps:** implement the shared T10 definition contract and validate definitions before finalization. Mod `industry:machines` depends `survival:crafting_progression`, `crafting:shaped`; register station kinds from machine definitions after all definitions are registered, create runtime at world_ready with a priority below existing station activation. Tick authority only every0.2s, loaded records only, and skip transfer-locked/disabled records. Match only recipe.method to definition.method with concrete ingredients; sort candidates by descending ingredient types then logical recipe ID. Reuse output trial/atomic `exchange_to`; advance progress only with valid recipe/capacity and applicable power; reset when recipe/input fingerprint changes. Budget at most four completions per record per tick; carry remaining progress. Store machine state under its own key; dirty-save via existing stations service. All-or-nothing completion, snapshot rollback and affected-feature pause on write failure. Unknown kind/state stays preserved. Registry accepts energy fields now but powered machines stall until T13 is present; never supply free fallback energy. Runtime startup/stop must not retain previous-world references. Existing furnace stays on its own ticker.
- **Assets:** no production models yet; fixture reuses a cube.
- **Acceptance criteria:** two fixture definitions run different recipe methods without custom scripts; full output pauses without ingredient loss; loaded/unloaded and flags affect ticking; state resumes after reload; a client cannot run production; furnace regression passes.
- **Validation:** MachineSmoke with multiple methods, progress reset, full output, pause/resume, failure rollback; T01 station/furnace and network smoke.
- **Recommended model / complexity:** Luna Medium / medium.

T10 may proceed before T08–T09 for solo play. Guard optional lock/view adapters and retain existing host/local station rendering; do not expose remote machine inventory until T09. Apply the network acceptance cases once T08–T09 are available.

### T11 — First manual crusher

- **Objective:** place and use one machine that crushes iron lumps into smeltable dust.
- **Prerequisites:** T06, T10.
- **Files to inspect:** T04 schema, T10 MachineRegistry contract, `mods/frontier_survival/mod.gd` iron/fuel IDs, `mods/crafting_progression/StationRuntime.gd` recipe method.
- **Files to modify:** `mods/industry_materials/content.json` for dust smelt recipe if not already present.
- **Files to create (proposed):** `mods/industry_devices/{mod.json,mod.gd,content.json,machines.json}`. Entry reads JSON and submits machine rows; no custom ticker.
- **Implementation steps:** mod ID `industry:devices`, dependencies `industry:materials`, `industry:machines`. Block `industry:manual_crusher`, hardness2, pickaxe level1; input4/output2, capability `crusher`, method `crush`, zero energy. Recipe one `frontier:iron_lump` → two `industry:iron_dust`, duration4s, method crush; one dust → one existing `frontier:iron_ingot`, method smelt/duration8s. Manual crusher recipe: frame in center, four stone cardinal neighbors. Register that explicit shaped pattern. Use all-face iron-block texture with gray tint and furnace-front icon fallback.
- **Assets:** existing iron/furnace PNGs.
- **Acceptance criteria:** ore → two dust → two ingots works; ordinary furnace does not crush; output-full machine stops; save/reload preserves dust and progress; client station access works.
- **Validation:** MachineSmoke and HostFurnaceSmoke plus one crusher-to-furnace cycle locally and in shared fixture.
- **Recommended model / complexity:** Luna Light / low.

### T12 — Energy ports and bounded connectivity

- **Objective:** register energy roles and find connected loaded devices through six-face cable adjacency.
- **Prerequisites:** T10.
- **Files to inspect:** `VoxelWorldService.gd` loaded access, `BlockEntityService.gd`, T10 MachineRuntime/lifecycle, `GameEvents.gd` edit events.
- **Files to modify:** API/loader composition for proposed `api.energy`; T10 machine tick ordering to reserve energy phase (no distribution yet).
- **Files to create (proposed):** `core/simulation/EnergyService.gd`, `mods/energy_framework/{mod.json,mod.gd,EnergyRuntime.gd}`, `tests/EnergySmoke.gd/.tscn`.
- **Implementation steps:** implement definition validation and stored/deposit/consume locally using station energy fields; mod `industry:energy` depends `industry:machines`. Register cable/device records sparsely on placement/loaded discovery, retain saved records while unloaded. Fixed face ordering, queue graph rebuild after edits or loaded state changes. Six-face BFS with ≤512 cells per graph; bounded work slices; incomplete graph reports size/unloaded status and transfers nothing. Cache membership and rebuild dirty graphs only. Initial cable is a cube definition `industry:cable`, no node per ordinary cable; register energy-only station kind. Reject incompatible faces and disconnected devices. No real voltage, resistance or physics wires.
- **Assets:** copper-block texture tinted for cable; no model dependency.
- **Acceptance criteria:** connected/disconnected/branched cables yield deterministic graph membership; unloaded cells and graph limit do not cause floods/freezes; breaking cable invalidates membership; state stays world-specific.
- **Validation:** EnergySmoke synthetic loaded-cell fixture, bounds/invalidation/compatibility/save fields; one placement check.
- **Recommended model / complexity:** Luna Medium / medium.

### T13 — Conserving energy allocation

- **Objective:** transfer energy once per 0.2s step with no duplication, negatives or order-dependent free power.
- **Prerequisites:** T12.
- **Files to inspect:** EnergyService/EnergyRuntime, station save/state mutation, T10 consumer fields.
- **Files to modify:** those proposed energy scripts and MachineRuntime's powered processing path.
- **Files to create (proposed):** additional allocation cases in `tests/EnergySmoke.gd`; no new framework.
- **Implementation steps:** allocation stages producer buffers → storage/consumer buffers in stable cell-key order, deterministic round-robin starting cursor persisted per network runtime; obey capacity and per-tick transfer limit. Compute debits/credits on copies and commit together; assert total stored change equals declared generation minus consumption. Validate finite bounded integer units; carry fractional rates. A powered machine consumes its configured rate only for productive elapsed time, stops on insufficient supply/full output/disabled state. Never transfer across incomplete graphs. State saves with station records; freeze affected graph on failed save, restore before-state. No path-distance electrical simulation.
- **Assets:** none.
- **Acceptance criteria:** generator/storage/two consumers cannot create energy; no double-transfer during graph rebuild; consumers get bounded fair service; missing power pauses progress; disabled flags preserve stored energy.
- **Validation:** deterministic allocation/conservation fixtures with 100 simulated ticks, split/reconnect, full battery and partial supply; MachineSmoke; no test per numerical data row.
- **Recommended model / complexity:** Sol / high.

Include the generic producer adapter in this ticket: definition fields `production_per_second` and `fuel_container`, item `fuel_seconds`, saved burn/remainder, valid fuel filter and pause when no buffer capacity. T14 must need only data registration. All transfer rates are units/second, converted to per-step amounts with remainder.

### T14 — Fuel generator

- **Objective:** coal/log/charcoal fuel produces bounded usable energy through the shared network.
- **Prerequisites:** T06, T13.
- **Files to inspect:** T12–T13 role/rate extension contract; existing furnace `fuel_seconds` properties.
- **Files to modify:** `mods/industry_devices/{content.json,machines.json,mod.gd}` only to register generator data through shared processor/energy producer behavior.
- **Files to create:** none unless T13 omitted the generic fuel producer adapter; that missing prerequisite must be repaired under T13, not a new per-generator loop.
- **Implementation steps:** `industry:coal_generator`, capacity200, production20units/s, transfer100units/s, fuel1 container. Shared producer converts one valid fuel item into existing `fuel_seconds`, burns only while buffer has room; carry saved burn remainder. Craft with one frame surrounded by eight stone. Capability `generator`; feature industry:energy. Never consume a whole fuel item while both timer and buffer are full.
- **Assets:** supplied furnace faces; lit status label initially sufficient.
- **Acceptance criteria:** valid fuel powers a connected consumer, invalid fuel rejected, blocked/full generator pauses, remaining burn survives reload.
- **Validation:** EnergySmoke producer integration + one generator/cable fixture; station UI fuel transfer.
- **Recommended model / complexity:** Luna Light / low.

### T15 — Battery block

- **Objective:** energy can be saved then used after the producer stops.
- **Prerequisites:** T13; industry_devices pack created T11.
- **Files to inspect:** energy storage role and station view status.
- **Files to modify:** `mods/industry_devices/{content.json,machines.json,mod.gd}` storage data only; generic UI uses energy state established T13.
- **Files to create:** none.
- **Implementation steps:** `industry:battery`, capacity2000, transfer100units/s, storage role, no item containers; craft one frame plus four wire in cardinal positions. Register sparse station kind; retain stored integer amount. Shared UI displays stored/capacity. Breaking drops the battery block and discards charge for this first version; never transfer saved charge into item metadata implicitly.
- **Assets:** iron-block texture with blue tint; frame icon acceptable.
- **Acceptance criteria:** battery charges, discharges within limit, survives world reload, cannot charge and discharge itself into net growth; disabled energy preserves charge.
- **Validation:** EnergySmoke storage/save/reconnect scenarios; one station view check.
- **Recommended model / complexity:** Luna Light / low.

### T16 — Electric furnace

- **Objective:** configured machine runs existing smelting recipes with electricity and no fuel slot.
- **Prerequisites:** T14, T15.
- **Files to inspect:** machine/energy definitions, concrete smelt recipes, T09 generic station UI.
- **Files to modify:** industry_devices content/machine/energy registration rows.
- **Files to create:** none.
- **Implementation steps:** `industry:electric_furnace`, input4/output2, method smelt, duration_scale0.5, energy_per_second10, consumer capacity100/transfer100units/s. Craft `[wire,furnace,wire] / [plate,frame,plate]` using existing furnace ID. No new tick code; generic processor checks energy. Preserve alloy prioritization established T10.
- **Assets:** furnace textures/icon.
- **Acceptance criteria:** connected power smelts existing iron and alloy recipes at configured duration; disconnect pauses; zero fuel needed; ordinary furnace remains fuel-based.
- **Validation:** machine/energy smoke plus local generator→battery→furnace recipe and shared station view.
- **Recommended model / complexity:** Luna Light / low.

### T17 — Electric crusher variant

- **Objective:** powered upgrade reuses crushing recipes and consumes energy to process faster.
- **Prerequisites:** T11, T14.
- **Files to inspect:** manual crusher rows and T10 processor configuration.
- **Files to modify:** industry_devices JSON/registration data.
- **Files to create:** none.
- **Implementation steps:** `industry:electric_crusher`, input4/output2, method crush, duration_scale0.5, energy20units/s, consumer capacity100. Craft manual crusher plus two wire horizontally. Use distinct tint/display name. Shared machine runtime only. Do not change manual recipe yield or existing mining speed.
- **Assets:** same crusher texture with copper tint.
- **Acceptance criteria:** exact same yield at half processing time with sufficient power; insufficient power pauses; manual crusher still runs without power.
- **Validation:** one shared machine fixture compares elapsed production and inventory totals; EnergySmoke.
- **Recommended model / complexity:** Luna Light / low.

### T18 — Adjacent item transfer

- **Objective:** one conveyor-like block moves real stacks from an adjacent output/storage to an adjacent input/storage.
- **Prerequisites:** T08, T10.
- **Files to inspect:** station containers/view/locks, `SlotContainer.transfer_to`, machine loaded ticking, WorldEditService events.
- **Files to modify:** industry_devices pack for `industry:item_pipe`; public `InventoryCommandService` only for validated orientation configuration.
- **Files to create (proposed):** `mods/machines/TransportRuntime.gd`, `tests/TransportSmoke.gd/.tscn`.
- **Implementation steps:** pipe has saved facing0–5, intake is opposite face and destination is facing face; right-click while holding same pipe cycles facing through a validated authority command within reach. Runtime at5Hz uses one source/destination pair per loaded pipe, amount at most4/tick; source output or storage, destination input or storage. Use existing filters/stack compatibility; no insertion into output. Lock involved station records, journal inventory changes using T08's recoverable record transaction adapter (extend it to station→station before enabling transfer). Full target leaves source identical. Clients see direction/status, never tick transfer. No visual item entities or long-distance graph routing yet.
- **Assets:** copper-block texture; arrow/direction text in station view.
- **Acceptance criteria:** chest→pipe→crusher→pipe→chest loop conserves items; output-full pauses; unloading or disconnecting stops transfer; reload preserves facing.
- **Validation:** TransportSmoke counts/full-target/filter/unloaded/recovery; one factory playtest; T08 transaction regressions.
- **Recommended model / complexity:** Luna Medium / medium.

### T19 — Filtered transfer pipe

- **Objective:** reusable transport restricts which items pass, without consuming the sample used to set a filter.
- **Prerequisites:** T18.
- **Files to inspect:** TransportRuntime filter/configuration contract and station command configuration added T18.
- **Files to modify:** TransportRuntime only for one generic filter predicate if not provided T18; industry_devices data for filtered variant; StationUI existing configuration affordance.
- **Files to create:** none.
- **Implementation steps:** `industry:filtered_pipe` shares pipe behavior, saved `filter_id` empty means all. Right-click holding an item assigns its logical ID; empty hand clears. Server reads actor's selected item, not supplied client stack data. Transport checks exact ID; tags/whitelists are deferred. Sample item stays in inventory. Recipe item_pipe plus iron plate.
- **Assets:** pipe texture with colored stripe/tint.
- **Acceptance criteria:** selected ore transfers while unrelated stacks remain; sample not consumed; cleared filter passes all; state reloads and clients agree.
- **Validation:** extend TransportSmoke with filtered/clear/persistence cases; one UI feedback check.
- **Recommended model / complexity:** Luna Light / low.

### T20 — Shared terrain replay and blast service

- **Objective:** farming, creepers, TNT and drills can reuse one authoritative cell-history and source-independent explosion contract.
- **Prerequisites:** T01, T02.
- **Files to inspect:** `mods/basic_survival/{SurvivalRuntime,ExplosionRuntime,CreeperAbility,mod}.gd`, `WorldEditService.gd`, `WorldSaveService.gd`, `CreeperNetworkSmoke.gd`, `BasicSurvivalNetworkSmoke.gd`.
- **Files to modify:** those basic-survival files and API/loader composition; WorldSaveService sidecar catalog/deletion for new replay file.
- **Files to create (proposed):** `core/world/TerrainChangeService.gd`, `mods/world_effects/{mod.json,mod.gd,TerrainChangeRuntime.gd,ExplosionService.gd}`, `tests/TerrainChangesSmoke.gd/.tscn`.
- **Implementation steps:** mod `world:effects` depends `entities:framework`; expose terrain_changes and explosions on ModAPI. Move existing reliable cell RPC, unloaded pending replay and late-join sync into world-owned runtime; bound/batch sync payloads. New `<world>.edits.json` version1 contains logical cell history. If absent, read legacy farming.cells into it without deleting/mutating the old file; avoid dual authoritative writes after migration. Growth still owns crop rules and calls generic change; compatibility wrappers retain change/save_state callers until updated. `change` authority-only, loaded checks and known ID; hook successful normal edits once. Extract blast(center/options) from existing explosion without changing default creeper balance; retain detonate wrapper committing creeper death first. Options radius≤4, damage, impulse, drops policy; remove station contents once via existing service and spawn existing loot receipts. No arbitrary client blast RPC. Register each public wrapper once and clear runtime pointer on world stop.
- **Assets:** reuse current synthesized blast/audio/particles.
- **Acceptance criteria:** old farm cells load; creeper behavior unchanged; late-join and loaded-later cells receive blast edits; standalone blast without crop/actor dependency works; malformed replay preserves original and disables edits.
- **Validation:** terrain migration/replay fixtures, CreeperSmoke/NetworkSmoke, BasicSurvivalSmoke/NetworkSmoke; save/reload blast crater. If migration authority is unclear, use Sol for that boundary rather than speculative edits.
- **Recommended model / complexity:** Luna Medium / medium.

### T21 — Output-safe mining drill

- **Objective:** powered machine mines one eligible nearby cell per second into its output container.
- **Prerequisites:** T17, T18, T20.
- **Files to inspect:** generic machine ability hook, mining profile/get_break_hits, WorldEditService, replay API, station transaction snapshots.
- **Files to modify:** industry_devices data, MachineRuntime for a small optional ability slot if absent.
- **Files to create (proposed):** `mods/machines/DrillAbility.gd`, `tests/DrillSmoke.gd/.tscn`.
- **Implementation steps:** `industry:mining_drill`, output4, consumer capacity200, cost20energy per successful cell; saved facing, cursor and mined count. Scan fixed 1×1×8 line in facing direction, one loaded eligible cell/sec. Use configured iron-pickaxe profile; skip air/water/unbreakable/stations/unsupported tool level. Trial output capacity for all returned drops before break; debit energy only for success. Mutate through api.edits and generic replay, insert real drops, flush station/replay; rollback failed ordinary operations, pause on persistence failure. Do not bypass hooks or reach into native VoxelTool. Mark experimental; disclose that sudden-crash atomic terrain+container commit is not yet guaranteed. No offline/unloaded mining.
- **Assets:** iron cube/furnace-front icon placeholder.
- **Acceptance criteria:** removes correct eligible terrain, stores drops, stops on full output/no power/unloaded cells and never mines a chest; pipes can extract output; progress is world-scoped.
- **Validation:** DrillSmoke loaded/full/ineligible/station/no-power cases and save/reopen output/cursor; factory playtest.
- **Recommended model / complexity:** Luna Medium / medium.

### T22 — Fused TNT block

- **Objective:** placed TNT can be primed and detonates once with existing terrain damage/audio/effect.
- **Prerequisites:** T06, T20; industry_devices pack from T11.
- **Files to inspect:** blast API, station state lifecycle, existing ITEM_USE hooks and selected-item access.
- **Files to modify:** industry_devices content/registration; world_effects runtime for generic armed-block scheduling if absent.
- **Files to create (proposed):** `mods/world_effects/FusedBlockAbility.gd`.
- **Implementation steps:** `sandbox:tnt`, hardness0.3/self drop, sparse record only after placement/arming. Right-click TNT with an existing torch item if registered; otherwise empty-hand right-click is the documented prototype control. Recipe four existing gunpowder items + five core sand in checkerboard, only if gunpowder ID is verified; omit survival recipe rather than invent its ID. Creative access always available. Save armed flag/remaining3s fuse, authority tick loaded cells, flag sandbox:explosives. Commit spent record/remove TNT before calling blast radius3/damage12; failed commit prevents detonation. No chain reactions yet. Disabled flag preserves fuse. Reuse T20 presentation without per-block custom particles.
- **Assets:** verified tnt_side/top/bottom PNGs; existing explosion audio/effect.
- **Acceptance criteria:** right-click primes, reload resumes fuse, one blast occurs, player can be hurt/launched and nearby terrain destroyed; remote clients cannot trigger a second blast; disabled worlds retain block.
- **Validation:** reuse Creeper/TerrainChanges test helpers for one TNT fuse/reload case; one audio/visual playtest.
- **Recommended model / complexity:** Luna Light / low.

Verified recipe IDs: `survival:gunpowder` and `core:sand`. Use four gunpowder + five sand in the checkerboard recipe; use empty-hand right-click as the initial documented priming control. T22 can now omit the conditional asset/ID choices in its steps. Declare `survival:basics` as a content dependency.

### T23 — Shared traveling projectiles

- **Objective:** bow, creature arrows and turret shots use one authority-driven projectile runtime.
- **Prerequisites:** T01, T02.
- **Files to inspect:** `SurvivalRuntime.gd` bow ray, `DamageReceiver.gd`, `EntityRuntime.gd` attacks/peers, `EntityActor.gd` ability hooks, existing ENet fixtures.
- **Files to modify:** basic-survival bow path to call proposed service; API/loader composition for projectiles.
- **Files to create (proposed):** `core/combat/ProjectileRegistry.gd`, `mods/projectiles/{mod.json,mod.gd,ProjectileRuntime.gd}`, `tests/ProjectileSmoke.gd/.tscn`.
- **Implementation steps:** mod `combat:projectiles`, depends entities:framework; definitions speed/damage/gravity/lifetime/hit effect/faction, registry shared public spawn contract. Integrate swept previous→next position ray each physics step; ignore source collision, deliver one hit then despawn. Authority validates finite origin/direction/source and count cap128/lifetime≤10s. Clients receive reliable spawn/hit/despawn and render interpolated primitive models; late join gets active records. Ammo/wear/cooldown stays server-owned in existing bow command path. No terrain destruction, piercing or bouncing now. Saved worlds need not persist projectiles; shutdown clears all.
- **Assets:** existing arrow icon stretched primitive or simple mesh, existing impact sound.
- **Acceptance criteria:** arrow visibly travels/gravity applies, walls stop it, target receives one hit, client cannot invent damage/ammo, cap bounds work and no projectile leaks across worlds.
- **Validation:** swept-hit/wall/miss/source/cap cases, host/client shot fixture and existing combat/basic-survival regressions; visual arrow playtest.
- **Recommended model / complexity:** Luna Medium / medium.

When `combat:projectiles` is disabled, the existing bow keeps its current hitscan behavior. The new traveling path is enabled by the flag; legacy worlds must not lose working bow attacks.

### T24 — Skeleton ranged ability

- **Objective:** the existing skeleton keeps navigation but fires arrows at visible targets.
- **Prerequisites:** T23.
- **Files to inspect:** existing skeleton definition in `mods/first_creatures/mod.gd`, EntityActor ability override contract, `CreeperAbility.gd` composition example, projectile service.
- **Files to modify:** first_creatures skeleton definition to attach ability and its `mod.json` to declare `combat:projectiles`; `mods/basic_survival/mod.gd` only to keep the final natural_spawn value false, honoring the user's earlier request; no cuboid/skin replacement.
- **Files to create (proposed):** `mods/first_creatures/RangedAbility.gd`.
- **Implementation steps:** reusable ability parameters range12, cooldown1.5s, keep_distance4, projectile existing arrow ID, damage defined in arrow definition. Authority uses existing target/LOS/pathing; suppress melee through established override, approach outside range, stop/shoot inside range, retreat within4 when passable. Save cooldown in ability record; replicas animate only. Do not reintroduce disabled natural skeleton spawning; explicit summons keep working.
- **Assets:** current skeleton skin/model; arrow primitive.
- **Acceptance criteria:** summoned skeleton shoots/approaches/avoids blocked LOS, does not melee and shoot in same tick; reload does not reset cooldown exploit; clients see projectiles.
- **Validation:** CreatureSmoke ability fixture plus ProjectileSmoke; console summon playtest.
- **Recommended model / complexity:** Luna Light / low.

Use the verified actor ability methods `setup(owner_actor, api)`, `tick(mob,delta)`, `decide(mob)->bool`, `restore(data)` and `save_state()`, as in CreeperAbility. When projectile flag is off, the ability yields to the original skeleton behavior.

### T25 — Powered defensive turret

- **Objective:** a powered block with ammunition defends a player base from hostile creatures.
- **Prerequisites:** T13, T23; industry_devices pack from T11.
- **Files to inspect:** machine ability attachment pattern, EntityRegistry definitions/actors, projectile and energy service, SlotContainer filters.
- **Files to modify:** industry_devices data/ability registration.
- **Files to create (proposed):** `mods/machines/TurretAbility.gd`.
- **Implementation steps:** `industry:arrow_turret`, ammo4, energy buffer100; fixed range12, fire interval1s, cost5energy and one existing arrow per successful spawn. Nearest alive hostile actor by distance then entity ID, use existing LOS. Reuse projectile service and machine scheduling; no new combat system. Exclude players/passive mobs, no friendly fire targeting. Persist cooldown; no power/ammo means no shot. Primitive top marker or status label sufficient; no tracking animation requirement.
- **Assets:** iron cube plus existing arrow icon/model; impact audio reused.
- **Acceptance criteria:** generator powers turret, hostile target loses HP through arrows, ammo/energy each consumed once, player/passive mob not targeted and wall blocks shots.
- **Validation:** shared projectile fixture with powered turret/ammo exhaustion/LOS; one creeper-versus-base playtest.
- **Recommended model / complexity:** Luna Medium / medium. It integrates targeting, a block record, ammunition, energy and projectile spawning; later turret variants can be Light data tasks.

### T26 — Sparse fluid tank and pump

- **Objective:** powered pump fills a saved tank from adjacent water without expensive terrain fluid simulation.
- **Prerequisites:** T10, T13.
- **Files to inspect:** station state/view, energy consumption, VoxelWorldService loaded/water logical IDs.
- **Files to modify:** API/loader composition for fluids, industry_devices definitions, station UI generic fluid display.
- **Files to create (proposed):** `core/simulation/FluidService.gd`, `mods/machines/PumpAbility.gd`, `tests/FluidSmoke.gd/.tscn`.
- **Implementation steps:** sparse tank state `{version:1,fluid_id:"fluid:water",amount:int}`; capacity1000, transfer validates matching/empty type and integer bounds, stages both station records and saves with existing recovery path. `industry:water_tank` stores, `industry:water_pump` faces water on intake and tank on output; move20units/s at2energy/s with remainder. Water terrain is an infinite source for this prototype and is not erased; describe that in UI. Pump ticks loaded/authority only, pauses on full/no source/no power/disabled. No pipes, buckets, mixing or terrain flowing liquids yet.
- **Assets:** glass/blue cube placeholders; quantity label.
- **Acceptance criteria:** pump fills tank, amount persists, full tank consumes no productive energy, transfer cannot mix fluids/create negative amounts; no terrain-wide scanning.
- **Validation:** FluidSmoke type/capacity/conservation/reload and powered pump fixture; UI quantity check.
- **Recommended model / complexity:** Luna Medium / medium.

### T27 — Sprinkler accelerates crops

- **Objective:** factory water has a direct farming benefit.
- **Prerequisites:** T26.
- **Files to inspect:** `mods/basic_survival/SurvivalRuntime.gd` grow scheduling, fluid service and machine ability contract.
- **Files to modify:** SurvivalRuntime for one additive, temporary growth multiplier query; industry_devices data.
- **Files to create (proposed):** `mods/machines/SprinklerAbility.gd`.
- **Implementation steps:** `industry:sprinkler` draws from adjacent tank, one water unit/s; marks loaded crop cells within3 blocks irrigated for2s. Growth checks this ephemeral mark for ×2 elapsed progression, not immediate stage skipping. Use same crop rules; mark only authority, no saved per-crop irrigation flags. No water means normal growth. One sprinkler applies one multiplier; overlapping sprinklers cannot multiply it repeatedly. UI says irrigating/no water.
- **Assets:** copper cube/tank placeholder; particle optional, not required.
- **Acceptance criteria:** irrigated crop matures faster while spending water; dry crop normal, overlap capped, removed sprinkler stops effect after2s; existing saved crop stages remain valid.
- **Validation:** timed basic-survival growth fixture with dry/wet/overlap counters and tank amount; no real-time15s waits required.
- **Recommended model / complexity:** Luna Light / low.

### T28 — One deterministic multiblock

- **Objective:** a small built structure modifies a controller's processing without spawning nodes for every component.
- **Prerequisites:** T10, T16.
- **Files to inspect:** machine registry/runtime, loaded edit hooks, station state and content tags.
- **Files to modify:** MachineRegistry for optional explicit structure pattern, industry_devices pack for casing/controller.
- **Files to create (proposed):** `mods/machines/MultiblockValidator.gd`, `tests/MultiblockSmoke.gd/.tscn`.
- **Implementation steps:** `industry:blast_furnace` controller requires eight `industry:machine_casing` in same-Y 3×3 ring; controller center. Validate only on relevant edits/loading or once/sec while incomplete; 9-cell constant bound. Missing/unloaded part gives incomplete status. Complete controller uses smelt method duration_scale0.25 and energy20units/s through same processor. Register explicit pattern `{offset:[x,0,z],selector:"industry:machine_casing"}`; tag selector support via existing matches optional. Inventory remains controller's station record; breaking a casing pauses, never erases inventory. No general assembly detection or moving structures.
- **Assets:** iron-block casing and furnace faces.
- **Acceptance criteria:** exact ring enables machine, missing piece pauses/resume, unloaded ring not assumed complete, one controller owns output and saves correctly.
- **Validation:** MultiblockSmoke complete/incomplete/unloaded/broken-restored + MachineSmoke energy consumption; one build playtest.
- **Recommended model / complexity:** Luna Medium / medium.

### T29 — Chunk-safe ruin blueprint stamps

- **Objective:** one small ruin blueprint can be placed deterministically through generation, creating exploration/building interest.
- **Prerequisites:** T02, T04; existing worldgen pipeline.
- **Files to inspect:** `WorldGenContext.gd`, `WorldNoise.gd`, `WorldGenerationPipeline.gd`, existing frontier/tree stage order and immutable snapshot use.
- **Files to modify:** `core/world/GenerationRuntime.gd`, `WorldGenContext.gd`, `WorldGenerationPipeline.gd`, `scenes/world/World.gd` only for optional frozen generation options; no terrain/noise algorithm rewrites.
- **Files to create (proposed):** `mods/ruins/{mod.json,mod.gd,blueprints/stone_ruin.json}`, `tests/StructureSmoke.gd/.tscn`.
- **Implementation steps:** mod `world:ruins`, dependency core:base. Blueprint list of relative cells/logical IDs, max16³, uses existing stone/cobble/glass IDs verified at registration. Cache validated immutable blueprint before worker generation. One anchor per128×128 world region from deterministic seed hash; sample height from existing pure terrain function. Each chunk checks intersecting region anchors including neighbors and stamps only local intersection so boundary pieces match. Order after terrain before trees, verify actual existing orders rather than choosing conflict. Feature world:structures is captured in immutable generation runtime; worker never reads profile/autoload/node. Existing worlds flag off by default; no retroactive edits, chest loot deferred until main-thread activation support exists.
- **Assets:** existing voxel block textures only.
- **Acceptance criteria:** same seed yields same full ruin across chunk boundaries/order; different seed can differ; no unsafe worker calls; disabling prevents new stamps without deleting old ruins.
- **Validation:** StructureSmoke generates neighboring chunks in reversed order and compares intersections; generation/thread diagnostics; one visual exploration.
- **Recommended model / complexity:** Luna Medium / medium.

The inspected context has no feature flags today. Add optional `options:Dictionary={}` to `create_runtime`, `GenerationRuntime.configure` and `WorldGenContext` construction without breaking existing callers. Capture a deep, read-only copy of flags on the main thread in World._configure_generator; propagate it to each job context. Blueprint and flag data read by callbacks are frozen for that runtime. Never read the live profile from a worker callback.

### T30 — Three configured creature variants

- **Objective:** inexpensive creature variety reuses existing visuals, movement and abilities.
- **Prerequisites:** T24.
- **Files to inspect:** first_creatures/basic_survival entity definitions and model texture paths; EntityRegistry registration validation; RangedAbility parameters.
- **Files to modify:** a new variants mod only; no default natural spawn table changes.
- **Files to create (proposed):** `mods/creature_variants/{mod.json,mod.gd,variants.json}`.
- **Implementation steps:** mod `creatures:variants`, dependencies creatures:first and combat:projectiles (verify creatures:first manifest before using). Three IDs: `creatures:fast_zombie` copies existing zombie visual/skin, speed×1.4/health×0.75; `creatures:large_zombie` scale×1.25/health×1.5/speed×0.8; `creatures:scout_skeleton` existing skeleton + ranged ability range16/cooldown2. Use copied definitions under new IDs and supported scale/collision fields; if scale is visual-only, leave collision baseline and document instead of editing actor physics. Drops use existing IDs. Explicit summon only; let natural spawning/population policy be a separate ticket.
- **Assets:** existing zombie/skeleton PNGs; no new art.
- **Acceptance criteria:** mobs list/summon discovers all three, visuals show, motion/attacks differ as configured, records reload and replicate; original mobs unchanged.
- **Validation:** existing CreatureSmoke/NetworkSmoke plus console summon and one persistence check for new IDs; no per-variant custom AI tests.
- **Recommended model / complexity:** Luna Light / low.

Verified dependency IDs are `creatures:first`, `survival:basics`, `combat:projectiles`. Declare all three so copied zombie definitions and final skeleton abilities exist before variant registration. Existing visual scaling uses `body_scale`; inspect its supported visual before applying it.

## First ten copy-paste implementation prompts

Run one prompt after its prerequisites are DONE, using its indicated model. Proposed files/APIs must be implemented by the named prerequisite, not assumed present. If a dependency is absent, report the exact gap; do not invent a replacement framework. Every prompt ends with validation and a short handoff. The following prompts are complete task instructions; relevant contracts are also retained above for later sessions.

### Prompt 01 — Luna Light — T01

```text
Implement only T01 in this Godot project:
C:/Users/Admin/Downloads/powered-by-go-vw-modular-steve-tools/powered-by-go-vw-modular
Read AGENTS.md and contributor guide once, then LUNA_TASKS.md T01. Preserve existing work. No gameplay changes or new testing dependency.

Inspect tools/ and completion/quit behavior in tests/InventoryFoundationSmoke.gd, WorldSaveCatalogSmoke.gd and CraftingStationsSmoke.gd. Create proposed tools/run_smoke.ps1 and tools/smoke_suites.json. Installed executable:
C:/Users/Admin/Downloads/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64_console.exe

Parameters: -GodotPath, -Suite (default foundation), -Scenes (override), -TimeoutSeconds (default60), -LogDirectory (optional). Root resolves relative to script. Launch each scene using --headless --path root res://tests/name.tscn in hidden child, redirect both streams, wait bounded time. Never launch editor. Fail for missing path, timeout, nonzero exit, SCRIPT ERROR/parser/assertion/load diagnostics or missing configured completion substring. Read real markers; some scenes print smoke passed or World save suite completed, not PASS. Print one short result per scene and a failure tail; exit1 if any fails. Terminate only owned timed-out child. Logs in temporary/chosen directory; no recursive cleanup or real-world edits.

Validate foundation, invalid executable/scene and timeout/diagnostic rejection via harmless temporary fixture if needed. Do not alter existing tests to make the runner pass. DONE requires reliable success/failure reporting and baseline results. Update T01 status and report files, commands/results, limitations in five short bullets.
```

### Prompt 02 — Luna Medium — T02

```text
Implement T02 only after T01 in:
C:/Users/Admin/Downloads/powered-by-go-vw-modular-steve-tools/powered-by-go-vw-modular
Read AGENTS.md and T02/shared profile contract. Preserve saves, hunger, terrain and existing gameplay.

Inspect core/world/WorldSaveService.gd, scenes/world/World.gd, core/ui/MainMenu.gd, core/api/GameAPI.gd, ModAPI.gd, core/modding/ModLoader.gd and tests/WorldSaves.gd. Create core/world/WorldProfileService.gd and tests/WorldProfileSmoke.gd/.tscn; modify only listed files for additive profile/menu/metadata integration.

Methods activate(config), clear(), mode(), enabled(id), snapshot(), set_replica(config). Schema: profile_version1; game_mode survival|creative; feature_flags bool values industry:machines, industry:energy, sandbox:explosives, combat:projectiles, industry:fluids, world:structures. Missing/invalid values default survival/false. Preserve unknown metadata without overriding trusted save_name/valid/seed. Same service object reaches every ModAPI context. World activates before WORLD_READY and clears after runtimes stop. Client defaults survival until trusted host snapshot; no client RPC mode setting.

New-world menu: mode choice and one checkbox enabling six experimental flags, defaults survival/off. Flags gate new behavior, never definitions. No live toggle UI. Preserve compatibility signatures and refusal to recreate corrupt/default worlds.

Isolated fixture covers old metadata, creative A→survival B switching, unknown fields, invalid values and clearing. Run T01 catalog regressions/profile scene, parse scripts, check menu creation. DONE requires world-specific state and compatible old saves. Update T02; report files/effect/exact checks concisely.
```

### Prompt 03 — Luna Medium — T03

```text
Implement only T03 creative catalog after T02 in:
C:/Users/Admin/Downloads/powered-by-go-vw-modular-steve-tools/powered-by-go-vw-modular
Read AGENTS.md and T03. Preserve ten hotbar slots, cursor/equipment and existing controls.

Inspect core/ui/InventoryUI.gd; core/inventory/Inventory.gd, InventoryCommandService.gd, ItemInstanceService.gd; core/player/VoxelInteractor.gd; mods/debug_console/mod.gd; EntityRuntime.gd join/inventory paths and project.godot inputs. Create mods/creative_catalog/mod.json, mod.gd, CreativeCatalog.gd and tests/CreativeCatalogSmoke.gd/.tscn. ID sandbox:creative_catalog, dependencies core:base/entities:framework. Allowed core edits: command service, GameAPI profile injection, EntityRuntime whitelist/profile snapshot; minimal generic UI guard if existing blocking pattern lacks it.

F6 named action toggles player-owned CanvasLayer in creative worlds. Catalog uses content.get_item_ids/get_item, icons/name/ID, searches name/ID/tags, scrolls and closes on Esc/world exit. Reuse current inventory mouse/cursor/blocking pattern; mining/placing cannot happen through UI. Missing icon uses text.

creative_grant request carries only item_id. Authority checks world creative, resolves limit, prepares one fresh unique condition item through item_instances, inserts all-or-nothing. Full/unknown/survival requests fail clearly. Host resolves sender in existing inventory adapter, saves before publish/rolls back on failure. Send authority-only reliable profile on join before enabling client catalog. Clients cannot supply mode, quantity or item metadata. No flight, invulnerability or unlimited placement.

Validate local grant/full/distinct instances/survival rejection, host-client grant and survival rejection, F6/E/Esc mouse/control playtest. Use existing ENet fixtures. DONE requires catalog accessible and server-owned grants. Update T03 and report files/gameplay/checks/limits briefly.
```

### Prompt 04 — Luna Medium — T04

```text
Implement only T04 optional schema-v1 packs after T01 in:
C:/Users/Admin/Downloads/powered-by-go-vw-modular-steve-tools/powered-by-go-vw-modular
Read AGENTS.md and T04/shared schema. No migration of old mods, new autoload, arbitrary behavior interpreter or native upgrade.

Inspect ModAPI.gd, ContentRegistry.gd, VoxelWorldService.gd, cube/atlas helper in basic_survival/mod.gd and GridCrafting.gd. Create core/content/ContentPackLoader.gd, docs/CONTENT_PACK_SCHEMA.md, tests/ContentPackSmoke.gd/.tscn and tiny tests/fixtures/content_pack/ JSONs. Add ModAPI.register_content_pack(path)->{success,errors,registered}. Generic native cube building belongs in VoxelWorldService using verified installed APIs. Optional commented template example only.

Schema arrays blocks/items/recipes. Block fields id/display_name/hardness/solid/transparent/tags/drops/preferred_tool/required_tool/mining_level/textures{side,top?,bottom?,front?}/tint[r,g,b,a]. Item id/display_name/icon/stack_size/tags/properties/place_block optional. Recipe id/output/count/ingredients/station/method/duration and optional pattern rows of logical IDs/#tags/empty strings. One output, no new entities/machines/scripts.

Validate entire pack before mutations: types/finite numeric bounds/IDs/duplicates/existing+pending refs and tags/assets/pattern grid requirement. Stage resources first. Register blocks→explicit items→recipes; explicit item replaces only this pack's generated block item. Use api.asset/load_asset, nearest filtering and existing transparent culling. Delegate cube/face atlas to adapter; register patterns through grid_service when present. Pattern pack depends crafting:shaped. Return precise structured errors; invalid pack adds nothing.

Test successful textured block/item/tag recipe/pattern; missing asset/duplicate/unresolved tag leave registry unchanged. Run shaped/transparent smoke and cube preview. DONE includes matching schema doc and legacy mods still load. Update T04; summarize files/checks in five bullets.
```

### Prompt 05 — Luna Light — T05

```text
Implement data-only T05 after T03/T04 in:
C:/Users/Admin/Downloads/powered-by-go-vw-modular-steve-tools/powered-by-go-vw-modular
Read AGENTS.md, docs/CONTENT_PACK_SCHEMA.md and T05. No core, loader, original stone or crafting UI edits.

Create mods/building_catalog/mod.json, mod.gd, content.json. ID building:catalog, dependencies core:base/crafting:shaped; entry calls api.register_content_pack. Eight IDs in building namespace: polished_granite, polished_diorite, polished_andesite, mossy_stone_bricks, chiseled_stone_bricks, smooth_sandstone, cut_sandstone, quartz_bricks. Check collisions. Verify same-name PNGs in supplied block folder; missing uses stone_bricks.png with distinct tint and recorded fallback.

Inspection confirmed seven exact-name PNGs. smooth_sandstone uses verified sandstone_top.png on all faces; do not search/download a nonexistent smooth_sandstone.png or select a different fallback.

Each hardness1.5, required/preferred pickaxe, mining_level1, tags block/stone/building:decorative, self-drop, texture and HUD icon. Four core:stone in2×2→four variants, workbench. If existing shaped UI cannot choose multiple recipes with identical patterns, ship creative access and report survival recipe deferral; do not redesign crafting.

Use established data schema/asset helpers; no generated/downloaded art. Validate JSON/dependencies/assets, content/mining smoke via T01, visually place at least two variants and check world/HUD texture. DONE: eight accessible distinct blocks with current mining behavior. Update T05 and report IDs/fallbacks/recipe availability/checks briefly.
```

### Prompt 06 — Luna Light — T06

```text
Implement data-only T06 after T04 in:
C:/Users/Admin/Downloads/powered-by-go-vw-modular-steve-tools/powered-by-go-vw-modular
Read AGENTS.md/content schema/T06. Inspect frontier resource IDs and GridCrafting patterns; preserve existing ore, tool and smelting systems.

Create mods/industry_materials/mod.json, mod.gd, content.json. ID industry:materials, dependencies frontier:survival/crafting:shaped. Use register_content_pack. Items industry:copper_wire, iron_plate, machine_frame, iron_dust, stack64, tags resource/industry:material; dust also industry:ore_dust. Verify supplied copper_ingot/iron_ingot/iron_nugget item textures and iron_block frame icon through api.asset helper.

Workbench shaped recipes: two frontier:copper_ingot horizontally→four wire; two frontier:iron_ingot horizontally→two plates; frame rows [plate,wire,plate], [plate,empty,plate], [plate,plate,plate]→one frame, exactly seven plates/one wire. Dust no hand recipe. Explicit rows/counts must agree; existing plank tags unchanged. No parallel metals, tools or smelting changes.

Validate schema/refs/tags, craft each new pattern once, check quantities/station requirement, run shaped smoke. DONE: four items and three recipes work with old content. Update T06; report files/IDs/recipes/checks in five short bullets. Avoid tests merely duplicating all JSON rows.
```

### Prompt 07 — Luna Light — T07

```text
Implement only T07 furnace kind guard after T01 in:
C:/Users/Admin/Downloads/powered-by-go-vw-modular-steve-tools/powered-by-go-vw-modular
Read AGENTS.md/T07. Narrow repair; no furnace rewrite.

Inspect mods/crafting_progression/StationRuntime.gd, mod.gd (FURNACE survival:furnace), BlockEntityService.record and CraftingStationsSmoke.gd. Current loop ticks any station with input. Require record.block_id==survival:furnace in both _process dispatch and start of tick_furnace. Leave recipe/alloy selection, fuel/progress, filters, save timer and UI unchanged.

Existing isolated crafting fixture gets one non-furnace station with input/fuel/output populated like a furnace. Direct tick and normal dispatch leave containers/state identical. No new test framework/assets. Real furnace still smelts iron.

Parse changed scripts, run CraftingStationsSmoke/HostFurnaceSmoke using T01. DONE: non-furnace cannot process and real furnace passes. Update T07; report two guards/regression/exact checks briefly. No other gameplay changes.
```

### Prompt 08 — Sol — T08

```text
Implement only T08 station authority/recovery after T02/T07 in:
C:/Users/Admin/Downloads/powered-by-go-vw-modular-steve-tools/powered-by-go-vw-modular
Read AGENTS.md/T08. This crosses save boundaries and belongs to Sol; no wholesale delegation to Light.

Inspect BlockEntityService, InventoryCommandService station_transfer/revisions/receipts, SlotContainer, EntityRuntime join/request_inventory/profiles/save_inventory, crafting lifecycle, WorldSaveService catalog/delete and ENet fixtures. Create core/inventory/StationTransferJournal.gd and tests/StationNetworkSmoke.gd/.tscn. Existing edits confined to named integration files.

view(id) returns cell/block_id/state/named {revision,slots}. request_open/close uses existing host runtime. Resolve RPC sender→player; check alive/reach/loaded/kind; subscribers removed on close/range/disconnect/break. Add station_transfer with operation/indices/count/revisions, no client replacement stacks; output collection only. Reliable views on changes or bounded5Hz; clients never mutate production.

Lock player/station; atomically journal unique transaction with before/after player and station snapshots before persistence. Apply validated transfer, save both station and authoritative player profile, mark committed, then publish. Failure restores before-state and blocks mutation until pending recovery resolves. Recover pending before-state to both stores idempotently before accepting commands; preserve unknown fields/file shapes. Duplicate successful request cannot repeat transfer. Processing skips locked station. Safely add journal suffix to catalog/delete. Scope only stations, no universal terrain/drop transaction refactor or unrelated duplication checks.

Validate two-client last-item contention, stale/out-of-range/unknown, late open, local/host, injected failures at every write boundary and restart recovery in isolated roots. Run inventory/station/host furnace regressions. DONE requires authority/conservation/recovery invariants. Update T08; concise interface/files/test/limitation summary.
```

### Prompt 09 — Luna Medium — T09

```text
Implement only T09 after T08 in:
C:/Users/Admin/Downloads/powered-by-go-vw-modular-steve-tools/powered-by-go-vw-modular
Read AGENTS.md/T09 and actual T08 view/open/close interfaces. No inventory redesign, station dragging or transaction rewrite.

Inspect crafting_progression/StationRuntime.gd, StationUI.gd, mod.gd and basic_survival/mod.gd chest ITEM_USE. Edit those four mod files only. Create tests/StationUISmoke.gd/.tscn if existing fixture cannot cover open/close.

Replace host-only open rejection with request_open/pending view. One UI renders containers/state/revisions from api.stations.view, keeping select-inventory then click-transfer interaction. All operations submit InventoryCommandService station_transfer with server revisions; no local client container writes. Refresh while subscribed, show waiting/stale/unavailable; close on station removal/range/death/disconnect. request_close unsubscribes, cursor/mouse return uses existing pattern. Client screen never starts furnace ticking; main inventory/shaped behavior unchanged.

Run StationNetworkSmoke/HostFurnaceSmoke/InventoryUISmoke; playtest client ore+fuel deposit→ingot retrieval, two views converge, broken station closes screens, Esc/E restore mouse/controls. Parse scripts. DONE: remote chest/furnace usable through authority views. Update T09 and summarize files/behavior/exact checks briefly.
```

### Prompt 10 — Luna Medium — T10

```text
Implement only T10 after T02/T04/T07 in:
C:/Users/Admin/Downloads/powered-by-go-vw-modular-steve-tools/powered-by-go-vw-modular
Read AGENTS.md/T10/shared contract. No new inventory/save framework, per-machine custom ticker or legacy furnace migration.

Inspect BlockEntityService, SlotContainer.exchange_to, CraftingService method filtering, furnace algorithm/lifecycle, plus T08 locks/views if available. Create core/machines/MachineRegistry.gd, mods/machines/mod.json/mod.gd/MachineRuntime.gd, tests/MachineSmoke.gd/.tscn. Wire additive api.machines in GameAPI/ModAPI/ModLoader. ID industry:machines, dependencies survival:crafting_progression/crafting:shaped. Minimal StationUI edit may show generic progress; keep local rendering if T09 is not done and remote interaction disabled until T09.

Registry register(definition)->bool, definition(block_id), ids(). Definition block_id/capabilities[]/slots{input:4,output:2}/method/duration_scale>0/energy_per_second>=0/feature. Validate fields/block. Register station kinds after definitions exist and run world startup below old station activation. One authority runtime ticks loaded records each0.2s, skipping locks/disabled/unknown/survival:furnace. Expose tick_record(id,delta) for fixtures.

Concrete recipe inputs and matching method only; priority descending ingredient types then recipeID. Trial output before progress; reset on recipe/input fingerprint change. Nested station machine{version:1,recipe,input_fingerprint,progress_seconds,status} preserves other keys. Duration=recipe.duration*duration_scale with positive minimum; maxfour completions/tick/carry remainder. Use exchange_to, station dirty/save, snapshot rollback/freeze on failed persistence. Powered definitions stall until T13; no free fallback. Energy-only devices can omit processing method. Stop/unsubscribe at world exit.

Test two methods/full output/no ingredient loss/reset/loaded-unloaded-flags/reload/failure rollback/client no production/old furnace. Run T01 station/furnace checks, network tests once T08–T09 exist, and parse scripts. DONE: reusable processing preserving furnace. Update T10 and report contract/files/checks/limits concisely.
```


## Execution evidence (2026-10-08)

- T02: WorldProfileService is wired through world lifecycle and all ModAPI contexts; world metadata preserves unknown keys while canonical fields remain safe. WorldSaveCatalogSmoke passed 15 tests.
- T03: sandbox:creative_catalog loads as a mod; F6 catalog filters item names, IDs, and tags. Trusted grants verify mode and persist before inventory publication. CreativeCatalogSmoke covers survival rejection, fixed stack size, unique durable instance, and full inventory.
- T04: schema-v1 JSON packs stage textures/models and preflight definitions before registry mutation. ContentPackSmoke covers valid block/item/recipe registration, missing-texture/tag atomicity, and duplicate rejection.

- T10: industry:machines registers and ticks shared station-backed machines; MachineSmoke covers registry validation, tag recipes, priority, progress reset, multi-completion, output-full pause, save/reload, failed-save rollback, feature gating and legacy furnace isolation. No networked shared-station playtest until Sol ticket T08.
- T12: api.energy and industry:energy add validated six-face cable/device roles, sparse station records, integer local storage, bounded 64-node rebuild slices and a 512-cell graph ceiling. EnergySmoke covers deterministic connection, incompatibility, disconnection, unloaded and oversized networks, invalidation, local storage and reload. Loaded-state adapters can call notify_loaded_state_changed; the existing event bus has no chunk-stream event wired.

- T05: building:catalog registers eight decorative voxel blocks and eight shaped workbench recipes from the supplied texture folder. Startup loaded the pack without errors (GameAPI: 116 blocks, 233 items, 129 recipes total). smooth_sandstone uses the verified sandstone_top texture fallback.
- T06: industry:materials registers copper wire, iron plate, machine frame and iron dust plus three shaped recipes. Startup loaded the pack without errors after correcting machine-frame icon to block/iron_block.png. Static script checks passed; live crafting/visual placement remains a manual check.
- Placement guard: WorldEditService rejects placement whose voxel cell overlaps the placing actor's collision shape; PlayerPlacementGuardSmoke passed overlap, adjacent-cell, and feet-support cases.
- Chest interaction: Shift no longer suppresses opening the survival:chest, avoiding conflict with Shift sprint. Remote chest UI remains unavailable until T08 implements shared station authority.
