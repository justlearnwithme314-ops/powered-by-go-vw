# Model geometry references

Research uses Mojang's published Bedrock sample geometry (accessed 2026-10-07).
These references specify cuboid dimensions, UV origins and attachment positions.
The existing cuboid builder uses sixteen logical texture pixels per world block;
UVs stay in logical 64-pixel atlas coordinates even for higher-resolution skins.

| Mob | Main reference dimensions (width × height × depth, model pixels) | Source |
| --- | --- | --- |
| Pig | Body 10×16×8; head 8×8×8; legs 4×6×4; snout 4×3×1 | [Mojang pig](https://github.com/Mojang/bedrock-samples/blob/main/resource_pack/models/entity/pig.geo.json) |
| Cow | Body 12×18×10; head 8×8×6; legs 4×12×4; horns 1×3×1 | [Mojang cow](https://github.com/Mojang/bedrock-samples/blob/main/resource_pack/models/entity/cow.geo.json) |
| Sheep | Body 8×16×6; head 6×6×8; legs 4×12×4 | [Mojang sheep](https://github.com/Mojang/bedrock-samples/blob/main/resource_pack/models/entity/sheep.geo.json) |
| Chicken | Body 6×8×6; head 4×6×3; legs 3×5×3; wings 1×4×6 | [Mojang chicken](https://github.com/Mojang/bedrock-samples/blob/main/resource_pack/models/entity/chicken.geo.json) |
| Spider | Thorax 6×6×6; abdomen 10×8×12; head 8×8×8; legs 16×2×2 | [Mojang spider](https://github.com/Mojang/bedrock-samples/blob/main/resource_pack/models/entity/spider.geo.json) |
| Creeper | Body 8×12×4; head 8×8×8; legs 4×6×4 at Z ±4 | [Mojang creeper](https://github.com/Mojang/bedrock-samples/blob/main/resource_pack/models/entity/creeper.geo.json) |

`AnimalVisual.gd` corrects these dimensions and each species' texture rectangles,
adds missing parts, and keeps the existing shared animation API. Separate Java
sheep-fur textures in this pack use the 64×32 layout, so their UV origins use that
layout rather than the Bedrock combined atlas. Creeper geometry was already the
correct size; its foot spacing now follows the sample. Existing humanoid zombie
and thin-limb skeleton geometry already matches their skin layouts.

This is an adaptation to existing collision/navigation and procedural animations,
not an import of Minecraft's renderer or gameplay code.
