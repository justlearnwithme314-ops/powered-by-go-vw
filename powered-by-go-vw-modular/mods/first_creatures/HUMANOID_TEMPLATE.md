# Box humanoid template

`HumanoidVisual.gd` builds six boxes with named joint pivots, skin UVs and
walk/chase/attack/death animations through the entity framework's visual API.
It faces -Z and is 2 world units tall with its feet at the origin.

Register a definition with `visual: api.load_asset("HumanoidVisual.gd")`
and `skin: api.load_asset("textures/your_skin.png")`. The included
`creatures:humanoid_template` definition can be spawned explicitly with
`api.entities.spawn("creatures:humanoid_template", position)`; it never spawns naturally.

Supported textures: 64x32 classic skins and 64x64 modern skins (including
integer-scaled equivalents). Modern skins use separate left limb regions;
classic skins mirror the right limb regions. Set `arm_width: 3` for slim skins.
This first template renders the base skin layer, without hat/jacket overlays.

Optional Vector3 proportions: `body_scale`, `head_scale`, `torso_scale`,
`arm_scale`, `leg_scale`. Set the entity's `height` and `radius` separately
to match its collision body. Thin limb scales can form skeleton-like bodies;
short body scale makes small variants. Non-humanoid mobs such as pigs need
their own geometry and UV layout; their texture atlases are not player skins.

Skeleton natural spawning is currently disabled. Existing saved skeletons
are preserved. Tree spawning threshold was lowered from 0.72 to 0.30;
this affects newly generated terrain only.
