# Crafting progression and stations

Current release: single-player and host recipe/station foundation. Expandable
arrangement-based crafting is supplied by the shaped_crafting mod. Durability and survival are supplied by the equipment_condition and
player_survival mods. Remote-client station interactions return an explicit
unavailable result; existing network movement and block presentation remain.

New empty inventories no longer receive a free starter kit. Saved items are kept.
Gather wood, hand-craft planks/sticks and a workbench. Tool recipes require a
workbench within three blocks. Connected workbenches expand the crafting grid.
Craft a furnace from eight stone arranged around an empty centre at the bench.
Smelt ore lumps into ingots with wood, planks, coal or charcoal as fuel. Refining
recipes cannot run through the instant crafting menu. Shift-right-click against
a station places a block rather than opening its interface.

Right-click a workbench to open inventory crafting. Right-click a furnace to
open its input/fuel/output interface. Select a carried stack, then left-click
an input/fuel slot to transfer it; right-click transfers one. With no stack
selected, click a station slot to retrieve its contents. Output always retrieves.
Esc/Close closes the furnace; processing continues while the world is running.

Input/fuel are filtered; output is collection only. Four input slots support
multi-ingredient alloy recipes. Full output stops processing and new fuel use;
already-lit fuel keeps burning. Input changes reset recipe progress. No progress
or fuel use occurs while the game is closed. Station destruction sends contents
once to the breaking player's inventory/recovery, following the existing mining
reward policy. Authoritative world loot remains planned.

The world .entities.json stores station records, containers, burn/progress state,
unknown mod records/recovery and the matching local inventory in one versioned
snapshot. Once present it is the local inventory source of truth; .player.json
continues as a compatibility snapshot. Writes use .tmp and a .bak of the previous
state. Corrupt/newer data disables writes. World deletion includes these sidecars.
This does not make terrain SQLite and the separate world-drop sidecar one
crash-atomic transaction; that broader authority/persistence work remains planned.

BlockEntityService is exposed as api.stations; InventoryCommandService is exposed
as api.inventory_commands. Commands validate revisions, station access and slot
indices and deduplicate bounded request receipts; expired IDs cannot replay after
receipt eviction. Callers supply a trusted actor, never a replacement stack.
Inventory and crafting grid commands also use the entity framework's server-authoritative
network inventory route. Remote furnace interfaces remain unavailable.

Textures are copied from the supplied Minecraft-inspired pack and assembled into
mod-local three-tile atlases. Definitions and behavior live in this mod; terrain
access uses api.world. Run tests/CraftingStationsSmoke.tscn for progression,
smelting, transfers, persistence, destruction and UI verification.

