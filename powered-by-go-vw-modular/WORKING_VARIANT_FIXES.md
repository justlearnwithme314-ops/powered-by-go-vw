# Working Variant Fixes

This build is intentionally gameplay-first and client-authoritative for inventory, crafting, food, and movement.

## Fixed

- Removed Markdown code fences from `core/inventory/Inventory.gd`.
- Rebuilt inventory stacking so `stack_size` is respected and multi-stack items work.
- Removed the duplicated/unreachable second `_on_player_spawned()` block from Frontier Survival.
- Restored typed `Inventory` usage now that the class parses correctly.
- Fixed the multiplayer connection race by waiting for ENet `connected_to_server`.
- Fixed player lifecycle replication: the server creates every player's node and broadcasts joins to all clients.
- Fixed server-side player position syncing so gameplay checks use the current client position.
- Kept inventory/crafting client-authoritative for low-friction gameplay.
- Added local inventory persistence at `user://player_state.json`.
- Preserved saved inventory instead of resetting the starter kit every spawn.
- Preserved Frontier hunger locally with `hunger_local`.
- Bounded in-memory voxel replication history to 50,000 changed positions.
- Added cleanup for the interactor's edit-result signal connection.
- Removed stale `.godot` editor cache files so Godot reindexes the corrected scripts.

## Runtime model

- The server remains responsible for applying voxel changes and broadcasting them.
- Clients own their movement and inventory state.
- Block edit requests are relayed through the server so all peers see the same world edits.
- No anti-cheat inventory validation was added because this variant prioritizes simple cooperative gameplay.


Follow-up fix: corrected `_record_voxel_change()` in `core/network/GameManager.gd`; the previous generated variant had an orphaned `else:` after `_voxel_change_order.append(key)`.
