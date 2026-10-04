# Steve-like player and tool sprites

The player model was replaced with a lightweight block-built character using rectangular BoxMesh parts:

- cube head with simple hair/face details
- blue shirt torso
- skin-tone arms and hands
- dark blue pants
- brown shoes
- walking limb swing driven by PlayerVisual.gd

Selected tools use the registered item icon as a Sprite3D attached to the right hand. The local camera also has a first-person hand + tool sprite so tools remain visible while playing.

The inventory hotbar now renders item icons and stack counts instead of text-only slots.

Remote clients receive the selected held-item ID during the existing movement synchronization, so another player's held tool can also be shown.
