# Basic creature AI

GridPath uses a bounded destination-prioritized grid search, with supported
ground cells and one-block up/down transitions. It avoids unloaded terrain
and rechecks route cells after edits. Actors jump with speed 8 under gravity
22, sufficient for a full block, and retry routes when stuck.

Hostile definitions roam without a target, chase detected players, wind up,
attack within reach and line of sight, and recover on cooldown. Add
`flee_health_ratio` (0..1) to opt into low-health fleeing; `flee_duration`
defaults to 4 seconds. Escape destinations must have walkable support.
Skeletons flee at 20%; prototype zombies and creepers flee at 25%. Prototype
creepers use melee attacks; explosions are not implemented. Slimes remain
passive and flee when hit. Skeleton natural spawning remains disabled.

Successful new spawns commit immediately to the active world's existing
entity snapshot; periodic saves also capture movement/health. Single-player
uses the combined entities snapshot, while multiplayer uses creatures JSON.
Frontier hunger now uses world player-data rather than global mod storage,
with final vitals flushed as the player is removed. Existing world survival
snapshots are retained; the old global hunger value is no longer consulted.
