"""Build the voxel atlas from the supplied pack; keep source artwork untouched."""
from pathlib import Path
import json
import re
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/minecraft-inspired-textures-free/block"
OUTPUT = ROOT / "assets/block_textures"
OUTPUT.mkdir(exist_ok=True)
tiles = {}
images = []
mapping = {}


def tile(name, tint=None, overlay=None):
    key = (name, tint, overlay)
    if key not in tiles:
        image = Image.open(SOURCE / f"{name}.png").convert("RGBA").crop((0, 0, 16, 16))
        if tint:
            image = ImageChops.multiply(image, Image.new("RGBA", image.size, (*tint, 255)))
        if overlay:
            layer = Image.open(SOURCE / "grass_block_side_overlay.png").convert("RGBA")
            layer = ImageChops.multiply(layer, Image.new("RGBA", layer.size, (*overlay, 255)))
            image = Image.alpha_composite(image, layer)
        tiles[key] = len(images)
        images.append(image)
    return tiles[key]


def block(folder, name, side, top=None, bottom=None, tint=None, grass=False, water=False):
    s = tile(side, None if grass else tint, tint if grass else None)
    t = tile(top or side, tint)
    b = tile(bottom or side, None if grass else tint)
    path = ROOT / folder / f"{name}.tres"
    old = path.read_text()
    uid = re.search(r'uid="([^"]+)"', old)
    resource_name = re.search(r'resource_name = "([^"]+)"', old)
    header = '[gd_resource type="VoxelBlockyModelCube" load_steps=2 format=3'
    if uid:
        header += f' uid="{uid[1]}"'
    material = "water" if water else "blocks"
    text = header + ']\n\n'
    text += f'[ext_resource type="Material" path="res://assets/block_textures/{material}.tres" id="1"]\n\n'
    text += '[resource]\nmaterial_override_0 = ExtResource("1")\natlas_size_in_tiles = Vector2i(8, 8)\n'
    text += f'resource_name = "{resource_name[1] if resource_name else name}"\n'
    for face, index in [("left", s), ("right", s), ("front", s), ("back", s), ("top", t), ("bottom", b)]:
        text += f'tile_{face} = Vector2i({index % 8}, {index // 8})\n'
    path.write_text(text)
    mapping[str(path.relative_to(ROOT)).replace("\\", "/")] = {"side": side, "top": top or side, "bottom": bottom or side, "tint": tint}
    if folder.startswith("mods/"):
        images[t].save(ROOT / "mods/frontier_survival/textures" / f"{name}.png")


CORE = "content/core/models"
for name in ["dirt", "stone", "sand", "snow", "gravel", "bedrock", "ice"]:
    block(CORE, name, name)
for name in ["iron", "coal", "gold", "diamond"]:
    block(CORE, name, name + "_ore")
block(CORE, "grass", "grass_block_side", "grass_block_top", "dirt", (125, 182, 70), grass=True)
block(CORE, "log", "oak_log", "oak_log_top", "oak_log_top")
block(CORE, "leaves", "oak_leaves", tint=(94, 156, 59))
block(CORE, "sandstone", "sandstone", "sandstone_top", "sandstone_bottom")
block(CORE, "cactus", "cactus_side", "cactus_top", "cactus_bottom")
block(CORE, "flower_red", "poppy")
block(CORE, "flower_yellow", "dandelion")
block(CORE, "tall_grass", "grass", tint=(125, 182, 70))
block(CORE, "water", "water_still", tint=(64, 130, 225), water=True)

FRONTIER = "mods/frontier_survival/models"
for name, source, tint in [
    ("copper_ore", "copper_ore", None),
    ("tin_ore", "iron_ore", (195, 225, 239)),
    ("silver_ore", "iron_ore", (220, 232, 255)),
    ("mese_ore", "gold_ore", None),
    ("murexium_ore", "diamond_ore", (217, 153, 255)),
    ("copper_block", "copper_block", None),
    ("tin_block", "iron_block", (195, 225, 239)),
    ("bronze_block", "copper_block", (230, 205, 139)),
    ("steel_block", "iron_block", (157, 168, 181)),
    ("silver_block", "iron_block", None),
    ("mese_block", "gold_block", None),
    ("murexium_block", "amethyst_block", None),
    ("obsidian_brick", "polished_blackstone_bricks", (190, 170, 225)),
    ("granite_brick", "stone_bricks", (224, 185, 166)),
    ("dark_plank", "spruce_planks", None),
    ("weathered_plank", "oak_planks", (185, 182, 171)),
    ("cherry_plank", "birch_planks", (255, 181, 188)),
    ("ebony_plank", "dark_oak_planks", None),
]:
    block(FRONTIER, name, source, tint=tint)
for name, tint in [("badland_grass", (181, 155, 74)), ("prairie_grass", (150, 191, 78)), ("japanese_grass", (91, 167, 71)), ("bamboo_grass", (94, 194, 91))]:
    block(FRONTIER, name, "grass_block_side", "grass_block_top", "dirt", tint, grass=True)
block(FRONTIER, "frost_grass", "grass_block_snow", "snow", "dirt")

assert len(images) <= 64, len(images)
atlas = Image.new("RGBA", (128, 128))
for index, image in enumerate(images):
    atlas.paste(image, ((index % 8) * 16, (index // 8) * 16))
atlas.save(OUTPUT / "atlas.png")
for name, transparent in [("blocks", False), ("water", True)]:
    text = '[gd_resource type="StandardMaterial3D" load_steps=2 format=3]\n\n'
    text += '[ext_resource type="Texture2D" path="res://assets/block_textures/atlas.png" id="1"]\n\n[resource]\n'
    text += 'albedo_texture = ExtResource("1")\ntexture_filter = 0\nroughness = 1.0\n'
    # Cutout texels preserve leaf/flower silhouettes without alpha sorting.
    text += 'transparency = 1\nalbedo_color = Color(1, 1, 1, 0.75)\n' if transparent else 'transparency = 2\nalpha_scissor_threshold = 0.5\n'
    (OUTPUT / f"{name}.tres").write_text(text)
(OUTPUT / "mapping.json").write_text(json.dumps(mapping, indent=2) + "\n")
print(f"Updated {len(mapping)} block models with {len(images)} atlas tiles.")
