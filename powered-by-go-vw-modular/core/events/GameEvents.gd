class_name GameEvents
extends RefCounted

## Canonical event names. Mods should use these constants instead of
## repeating string literals throughout their own code.

const GAME_STARTED := "game_started"
const GAME_STOPPING := "game_stopping"
const WORLD_READY := "world_ready"
const WORLD_STOPPING := "world_stopping"
const PLAYER_SPAWNED := "player_spawned"
const PLAYER_DESPAWNED := "player_despawned"

const ITEM_USE := "item_use"
const PRIMARY_ACTION := "primary_action"
const PLAYER_DIED := "player_died"
const PLAYER_RESPAWNED := "player_respawned"
const BLOCK_HIT := "block_hit"
const BEFORE_BLOCK_BREAK := "before_block_break"
const AFTER_BLOCK_BREAK := "after_block_break"
const BEFORE_BLOCK_PLACE := "before_block_place"
const AFTER_BLOCK_PLACE := "after_block_place"

const BEFORE_CRAFT := "before_craft"
const AFTER_CRAFT := "after_craft"
