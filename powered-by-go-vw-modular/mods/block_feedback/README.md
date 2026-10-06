# Block interaction feedback

This mod attaches to the local player's VoxelInteractor on player_spawned.
It renders eight 16x16 crack stages on all six faces of the damaged voxel,
with nearest filtering, alpha transparency and no shadows. The shell is slightly
larger than the voxel to avoid depth flicker. It clears when mining resets.
The stage is zero at no damage and ceil(progress * 7) for accepted damage.

Material sounds select wood for axe-preferred blocks, earth for shovel-preferred
blocks, and stone otherwise. Hits are quieter than successful breaking/placement;
one-shot spatial players free themselves when playback finishes. Assets come from
the supplied Kenney Impact Sounds pack (CC0). Crack frames come from the generated
assets/block_breaking textures. All runtime assets are mod-local.

Sounds and crack progress are local interaction feedback. They are not broadcast
to other peers. Held arm swings use the existing multiplayer presentation timer.
The generic interaction component owns input and cooldowns; this mod owns effects.

Run tests/BlockFeedbackSmoke.tscn in native Godot (mouse capture required) for held
input, cooldown, cancellation, acknowledgement, reset and effect checks. Pass
--capture as a user argument to export tests/block-feedback-preview.png.
