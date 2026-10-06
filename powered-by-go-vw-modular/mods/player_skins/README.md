# Player skins

The player uses the box humanoid, with a white default 64x64 skin. Main menu
"Select player skin" or console `/skin set` opens a PNG picker. Exactly 64x64
pixels are required. The classic four-pixel arm layout and outer hat/jacket/
sleeve/trouser layers are supported. Slim three-pixel player arms are not
selected automatically because PNG dimensions cannot identify that layout.

Selected skins are saved as `user://player_skin.png`, separately from worlds.
The mod-owned `/root/SkinService` validates PNG dimensions and packet size,
assigns uploads to their actual sender peer ID, relays them reliably through
the server, and sends current skin data to late joiners. No external uploads
or services are used. Skin changes also update the first-person arm.

PlayerBody implements the generic PlayerVisual adapter methods and item
socket, preserving network pose phases, head pitch, held items and swings.
The old Rogue assets remain available but are no longer the player scene body.

The skeleton now uses the skeleton atlas and two-pixel box limbs. Natural
skeleton spawning remains disabled; `/summon skeleton` explicitly tests it.
