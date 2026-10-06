# Reusable world entities

Content mods register definitions through `api.entities.register`. Runtime nodes
belong to this mod and are installed at WorldReady; no feature mod touches Zylann.
`api.entities.spawn(id, position)` manually creates an authority-owned entity.
Natural spawning requires `natural_spawn: true`; NPCs default to manual spawning.

Definitions supply namespaced id, health, visual Script, faction, speed, collision
height/radius, attack damage/reach/windup/cooldown/detection and loot records.
Visual scripts implement `setup(definition)` and `animate(state, time, hurt)`.
Models and animation sources are resources supplied by the content mod, loaded
with its own `api.load_asset` before registration.

Optional `abilities: [Script, ...]` create composed Nodes. Supported methods:
`setup(actor, api)`, `tick(actor, delta)`, `decide(actor)` (return true to override
default decisions), `interact(player)`, `save_state()` and `restore(data)`.
Ability ticking stops on death and never runs on client replicas. A boss can own
phase timers/attacks in an ability; an NPC can use interaction events for dialogue
or a shop. `interactive: true` enables right-click interaction with reach/LOS checks.
Actual bosses, shops, dialogue and breeding are future content, as specified by
the plan, rather than built into the first two creatures.

Events: entity_spawned, entity_damaged, entity_died, entity_despawned,
entity_interact. Despawn is independent of death and never creates loot.
`api.entities.spawn_loot(receipt, stack, position)` supplies a generic world reward
operation. Use a stable namespaced receipt per reward; repeated receipts do not
create another drop. Stack contents come from trusted mod code, never an RPC.

Movement uses gravity/collision and bounded local grid search (128 cells per
search, four searches per physics frame). Waypoints are revalidated after edits.
Paths avoid water, unsupported drops and unloaded terrain; blocked actors retry
and return home rather than teleporting through obstacles. Sensing runs roughly
three times per second. Saved distant actors become dormant and still count toward
population limits. Known committed deaths are compacted without reusing their IDs;
unknown mod definitions/records are retained.

## Persistence

Single-player creatures, loot and receipts use the entities:world namespace in the
existing .entities.json snapshot. Accepted death and its loot are saved together;
pickup saves inventory and the consumed/reduced drop together. Save failure rolls
back the pickup. Unreadable/newer records disable writes instead of replacing them.

Network hosts use a versioned .creatures.json ledger containing actors, loot,
profiles, credential ownership and reward outbox. Files use temporary writes and
a backup. Server-owned profile inventory plus loot reservation share one commit.
Client delivery saves an inventory snapshot/receipt before acknowledgment; retries
do not grant again. World deletion includes .creatures.json and its temp/backup.
This does not make voxel SQLite or the older manually dropped-item sidecar one
crash-atomic transaction with the new ledger.

## Multiplayer scope

The host simulates creatures and validates attack distance, obstruction, cooldown,
damage and equipment. Clients interpolate full entity snapshots at 5 Hz and reject
stale sequences; later joiners receive current actors and loot. Network creature
combat has server health, armor wear, death locking and validated respawn. Health
and inventory survive reconnect under a private random bearer credential, stored
locally as creature_identity.json; the host keeps only its hash as the profile key.

Remote players receive server-owned inventories. Selection, slot/cursor operations,
equipment and validated craft/repair commands execute on the server; clients cannot
grant tools or nominate their damage stats. First-time network profiles begin empty;
old local multiplayer inventory is preserved in a .pre_authority.json backup in
user://network_profiles before the world-scoped client mirror replaces it.
Matching mod/content signatures continue to be enforced by the game handshake.

Shared furnace/chest interactions, manual network item dropping, fully authoritative
mining hit accumulation, hunger/environmental simulation and general multiplayer
food/healing remain separate integration work. Server-authoritative creature
rewards/combat and normal inventory moves are implemented; this is not a claim
that every previous survival/progression feature is now networked. The existing
movement protocol remains client-authoritative.

Tests: CreatureSmoke, CreatureWorldSmoke and CreatureNetworkSmoke cover component
hooks, rig clips, movement/edited terrain, spawning, saved health/identity, atomic
loot rollback, full inventories, physics attacks, stale snapshots, authoritative
tool wear, cursor transfers, duplicate delivery and real ENet reconnect.

Remote players also receive authority-side terrain viewers through the generic world adapter, so server creatures can simulate around them when they leave the host's immediate area.
