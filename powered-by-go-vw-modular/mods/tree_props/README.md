# Voxel Block Trees (2.0.0)

The manifest retains `core:tree_props` so existing dependencies remain valid.
The entry `mod.gd` now registers only `core:tree_props:trees` at order 400,
after core terrain/caves/ores and before Frontier's biome repaint at 450.
Trees consist of ordinary `core:log` and `core:leaves` blocks and use the
existing block interaction/drop system. No prop lifecycle, mesh spawning,
custom tree-hit handler, visibility timers, debug telemetry, or trunk clearing
is registered. `legacy_prop_spawner.gd.txt` is a non-executable historical copy;
all imported model assets are retained and no longer loaded by this mod.

Generation uses seed-dependent jittered world-space grid roots (minimum five
blocks apart), the shared tree-noise threshold 0.72, and 4–6-block trunks.
Roots are scanned with two blocks of canopy padding; all writes are clipped to
the current buffer and replace air only. Core terrain temperature/humidity,
surface-height and surface cave rules select supported grass roots even when
the surface is in another vertical chunk. Frontier may subsequently repaint
that grass; tree eligibility therefore works for its grass variants without
requiring Frontier as a dependency. This assumes the current core height/cave
rules; a future mod changing terrain heights must provide a matching policy.

## Existing worlds

No save files or mod storage are deleted, reset, migrated, or rewritten.
Persisted chunks are loaded unchanged; voxel trees appear only in newly
generated chunks (or a separately created new world). Previously pinned/felled
prop positions are no longer used. At borders with old saved treeless chunks,
a new tree canopy can be partial; retrofitting those chunks would risk player
edits and is intentionally not done automatically.

## Verification

`tests/VoxelTrees.gd` covers real voxel generation with remapped logical IDs,
repeat determinism, negative coordinates and split X/Y/Z chunk equivalence,
non-air protection/clipped writes, surface rules, spacing, seed variation,
and manifest/runtime isolation. Run with the native voxel extension present.
