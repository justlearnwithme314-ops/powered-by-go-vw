# Pigs and melee skeletons

Enabled automatically with the normal mod loader. Walk away from your spawn to
encounter creatures on loaded terrain. Defaults: up to eight pigs and six skeletons
near a player, spawn candidates 24–48 metres away, sampled every three seconds.
The smaller maximum fits the existing 64-metre terrain loading range.

Pigs have 10 health, wander and flee for four seconds when hurt. They drop two raw
pork items. Cook pork in a fuelled furnace (six seconds); the existing food system
consumes raw/cooked pork. Skeletons have 20 health, pursue living players within
16 metres, leash to their territory, and attack for three damage after a 0.4-second
wind-up, with a 1.2-second cooldown. Walls obstruct attacks. They drop two bones;
one bone hand-crafts into two sticks. Primary input attacks using your selected
tool or fists. Death drops are world pickups and remain when inventory is full.

The pig model, gait and SVG item icons are original code/vector assets. The skeleton
uses the uploaded CC0 KayKit Minion and matching movement/general animation files;
the hit sound uses the uploaded CC0 Kenney Impact Sounds. License files are copied
beside the bundled assets. The original procedural skeleton strike uses its real
arm bone, so no extra download is required. No Minecraft animal texture is used.

See entity_framework/README.md for persistence, extension hooks, multiplayer scope
and verification. Initial balance and the animation style can be tuned during play.
