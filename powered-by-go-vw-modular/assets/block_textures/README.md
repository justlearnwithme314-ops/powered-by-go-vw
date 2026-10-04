# Block texture mapping

43 existing core and Frontier block models use the supplied
`assets/minecraft-inspired-textures-free/block` artwork through an 8×8 atlas.
Grass, logs, sandstone and cactus have separate top/side/bottom mappings.
Grass and foliage receive the color tint their source images require.
Filtering is nearest-neighbor; no mipmaps are needed for this small atlas.

Frontier's tin/silver ores use tinted iron ore, mese uses gold ore, murexium uses
tinted diamond ore/amethyst, and its building materials use matching plank and
brick textures. `mapping.json` records every source and tint. Water currently
uses the first frame of the source animation strip, with blue tint and alpha.
Plant blocks keep their existing cube geometry and receive cutout textures.

Regenerate with `python tools/build_block_textures.py` (Pillow required).
The pack's source files, block IDs, drops, collision rules and world generation
are unchanged. Existing saved terrain receives the new appearance when loaded.
