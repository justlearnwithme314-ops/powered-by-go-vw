# Player Actions (core:player_actions)

Depends on core:base. Movement and pistol behavior are mod-owned child nodes
created from ModAPI's player_spawned event **after inventory restoration**. Player
despawn removes them; freeing a player frees its components. Movement remains
locally controlled. Core snapshots replicate posture/roll, height, grounded
state, velocity and animation phase; remote peers do not run input extensions.
See docs/ARCHITECTURE.md for the multiplayer presentation contract.

## Controls and safety

C crouches, Q dashes, V rolls, Z lies down, X sits. Jump retains the existing
wall/extra-jump behavior. Roll and sit/lie require grounding; dash and roll cannot
overlap. Roll has a duration plus 0.3 second recovery cooldown. Losing mouse
capture cancels dash/roll and clears held crouch; no ability starts with free
mouse input. Roll lowers the collision capsule and rotates only the model, not
the first-person camera. Standing requires full-capsule clearance. Sit and lie
stop locomotion/shooting. The prone collider remains an upright low capsule:
limb/art poses are approximations, not separate physical limb colliders.

Pistol remains core:pistol, ammunition remains core:pistol_ammo. Shooting is
semi-auto with the existing range, impulse, flash, audio, recoil, fire-rate,
magazine HUD and timed R reload. Loaded rounds remain part of total inventory;
only firing removes one round. Inventory changes clamp loaded ammunition without
adding items or reassigning slots. Magazine state is runtime-only, as before;
on spawn it initializes to min(magazine capacity, owned ammunition).

No free pistol or forced hotbar replacement occurs on inventory change.
For development only, set this mod's storage key debug_starting_inventory to
true. It seeds an **empty** inventory once at spawn; it never replaces restored
items or runs continuously. The legacy controller debug export is retained for
scene compatibility but no longer grants items.

## Generic controller extension contract

PlayerController.add_movement_extension(node) registers a mod-owned child.
remove_movement_extension(node) must be called on exit. Optional hooks:

- movement_input(event: InputEvent) -> bool: unhandled, captured input; return
  true to consume it.
- movement_prepare(delta: float): runs before collision posture/gravity/jumping.
- movement_jump() -> bool: return true to override the default floor jump.
- movement_apply(delta: float): runs after acceleration, before move_and_slide.

All hooks execute only for local authority, in registration order. Prepare may
set requested_height, movement_scale, movement_blocked and visual_pose. These
movement request fields reset every tick (visual_pose persists until changed).
Mods must gate input with gameplay_input_enabled() and unregister on exit.
PlayerController owns gravity, clearance, feet-anchored capsule resizing,
collision movement and generic unstuck logic. Existing tuning exports remain as
a compatibility bridge for scene overrides; concrete behavior is in this mod.
PlayerVisual consumes the pose dictionary; no camera is reparented or rolled.

## Damage receiver contract

Attach a DamageReceiver child **named DamageReceiver** directly beneath a hit
physics collider to opt into damage. See core/combat/DamageReceiver.gd:
receive_damage(amount: float, context: Dictionary) subtracts health, emits
`damaged(applied_amount, context)` and emits `depleted(context)` at zero health.
An entity mod can subclass this typed contract and decide death/despawn behavior.
Context contains source (player), item_id, hit position and shot direction.
DamageReceiver.deliver safely ignores absent/incompatible receivers; it never
calls arbitrary methods on terrain/props. A rigid body still receives knockback.

The supplied world has no authored DamageReceiver targets. Terrain/trees do not
silently gain health, and shots do not damage network players. Actual health
reduction on a compatible receiver is covered by the deterministic test suite.
Adding targets and multiplayer damage authority is deliberately out of scope.

## Verification

Run tests/AuditFixes.gd with run_tests: seven tests cover capsule bounds,
once-only shape ownership/feet anchoring, typed damage delivery, model-only roll
transforms, manifest dependencies, and static architecture/debug contracts.
Native-backend startup smoke succeeded in Godot 4.7.1; this is not a full gameplay
playtest. Assets were moved here and imported without regenerating their art.
Existing save mismatch warnings are intentional (the mod signature changed);
voxel IDs, inventory IDs, save files and save metadata were not migrated/reset.
