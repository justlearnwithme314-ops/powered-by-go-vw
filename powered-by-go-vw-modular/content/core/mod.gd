extends GameMod

const AIR := "core:air"
const GRASS := "core:grass"
const DIRT := "core:dirt"
const STONE := "core:stone"
const LOG := "core:log"
const LEAVES := "core:leaves"
const IRON := "core:iron_ore"
const COAL := "core:coal_ore"
const GOLD := "core:gold_ore"
const DIAMOND := "core:diamond_ore"
const SAND := "core:sand"
const SANDSTONE := "core:sandstone"
const WATER := "core:water"
const SNOW := "core:snow"
const GRAVEL := "core:gravel"
const BEDROCK := "core:bedrock"
const FLOWER_RED := "core:red_flower"
const FLOWER_YELLOW := "core:yellow_flower"
const TALL_GRASS := "core:tall_grass"
const CACTUS := "core:cactus"
const ICE := "core:ice"


func register(api: ModAPI) -> void:
	_register_block(api, "core:air", "Air", "air", 0, false, true, 0.0)
	_register_block(api, "core:grass", "Grass", "grass", 1, true, false, 1.0)
	_register_block(api, "core:dirt", "Dirt", "dirt", 2, true, false, 1.0)
	_register_block(api, "core:stone", "Stone", "stone", 3, true, false, 3.0)
	_register_block(api, "core:log", "Wood", "log", 4, true, false, 2.0)
	_register_block(api, "core:leaves", "Leaves", "leaves", 5, true, true, 0.5)
	_register_block(api, "core:iron_ore", "Iron Ore", "iron", 6, true, false, 3.5)
	_register_block(api, "core:coal_ore", "Coal Ore", "coal", 7, true, false, 3.0)
	_register_block(api, "core:gold_ore", "Gold Ore", "gold", 8, true, false, 3.5)
	_register_block(api, "core:diamond_ore", "Diamond Ore", "diamond", 9, true, false, 4.0)
	_register_block(api, "core:sand", "Sand", "sand", 10, true, false, 0.8)
	_register_block(api, "core:sandstone", "Sandstone", "sandstone", 11, true, false, 2.0)
	_register_block(api, "core:water", "Water", "water", 12, false, true, 100.0)
	_register_block(api, "core:snow", "Snow", "snow", 13, true, false, 0.2)
	_register_block(api, "core:gravel", "Gravel", "gravel", 14, true, false, 0.9)
	_register_block(api, "core:bedrock", "Bedrock", "bedrock", 15, true, false, 999999.0)
	_register_block(api, "core:red_flower", "Red Flower", "flower_red", 16, false, true, 0.2)
	_register_block(api, "core:yellow_flower", "Yellow Flower", "flower_yellow", 17, false, true, 0.2)
	_register_block(api, "core:tall_grass", "Tall Grass", "tall_grass", 18, false, true, 0.1)
	_register_block(api, "core:cactus", "Cactus", "cactus", 19, true, false, 1.0)
	_register_block(api, "core:ice", "Ice", "ice", 20, true, true, 1.0)

	for name: String in ["dirt", "stone"]:
		api.register_item({
			"id": "core:" + name,
			"display_name": name.capitalize(),
			"stack_size": 64,
			"place_block": "core:" + name,
			"tags": ["block"],
			"icon": api.asset("res://assets/minecraft-inspired-textures-free/block/%s.png" % name),
		})

	api.register_item({
		"id": "core:stick",
		"display_name": "Stick",
		"stack_size": 64,
		"tags": ["resource", "tool"],
		"properties": {"break_power": 2.0},
	})

	api.register_item({
		"id": "core:pistol",
		"display_name": "Pistol",
		"stack_size": 1,
		"tags": ["tool"],
		"properties": {
			"damage": 25.0,
			"range": 50.0,
			"fire_rate": 0.15,
			"knockback": 2.0,
		},
		"icon": api.asset("res://assets/generated/pistol.png"),
	})

	api.register_item({
		"id": "core:pistol_ammo",
		"display_name": "Pistol Ammo",
		"stack_size": 64,
		"tags": ["ammo"],
		"icon": api.asset("res://assets/generated/pistol_ammo.png"),
	})

	api.register_recipe(
		"core:pistol_ammo_from_iron",
		"core:pistol_ammo",
		4,
		{"core:iron_ore": 1}
	)

	api.register_recipe(
		"core:stick_from_wood",
		"core:stick",
		4,
		{"core:log": 2}
	)

	api.register_worldgen_stage(
		"core:terrain",
		100,
		Callable(self, "_stage_terrain")
	)
	api.register_worldgen_stage(
		"core:caves",
		200,
		Callable(self, "_stage_caves")
	)
	api.register_worldgen_stage(
		"core:ores",
		300,
		Callable(self, "_stage_ores")
	)
	# Voxel trees are supplied by core:tree_props at order 400.
	# Keep this legacy stage unregistered to avoid duplicate generation.

	print("[CoreMod] Registered core content.")


func _register_block(
	api: ModAPI,
	block_id: String,
	display_name: String,
	model_name: String,
	voxel_id: int,
	solid: bool,
	transparent: bool,
	hardness: float
) -> void:
	api.register_block({
		"id": block_id,
		"display_name": display_name,
		"model": api.load_asset("models/%s.tres" % model_name),
		"voxel_id": voxel_id,
		"solid": solid,
		"transparent": transparent,
		"hardness": hardness,
		"breakable": block_id not in [AIR, WATER, BEDROCK],
		"preferred_tool": _mining_tool(block_id),
		"required_tool": "pickaxe" if _mining_tool(block_id) == "pickaxe" else "",
		"mining_level": 3 if block_id in [GOLD, DIAMOND] else (2 if block_id == IRON else 1),
		"drops": [] if block_id == AIR else [{"item": block_id, "count": 1}],
		"tags": ["block"],
	})


# ------------------------------------------------------------------
# Core world generation
# ------------------------------------------------------------------

func _stage_terrain(ctx: WorldGenContext) -> void:
	var size := ctx.buffer.get_size()
	for z in range(size.z):
		for x in range(size.x):
			var wx := ctx.origin.x + x
			var wz := ctx.origin.z + z
			var temperature := ctx.noise.temperature.get_noise_2d(wx, wz)
			var surface := int(
				ctx.noise.terrain.get_noise_2d(wx, wz) * 24.0
			) + 32

			for y in range(size.y):
				var wy := ctx.origin.y + y
				if wy > surface:
					continue

				var depth := surface - wy
				var block_id := STONE

				if depth <= 3:
					if temperature > 0.45 and ctx.noise.humidity.get_noise_2d(wx, wz) < 0:
						block_id = SAND
					elif temperature < -0.15:
						block_id = SNOW
					elif depth == 0:
						block_id = GRASS
					else:
						block_id = DIRT

				ctx.set_voxel_local(Vector3i(x, y, z), block_id)


func _stage_caves(ctx: WorldGenContext) -> void:
	var size := ctx.buffer.get_size()
	var tunnels_a := ctx.noise.get_custom_3d("core:cave_tunnel_a", 0.035, 1)
	var tunnels_b := ctx.noise.get_custom_3d("core:cave_tunnel_b", 0.035, 1)
	var chambers := ctx.noise.get_custom_3d("core:cave_chambers", 0.045, 2)
	var entrances := ctx.noise.get_custom_2d("core:cave_entrances", 0.025, 1)
	for z in range(size.z):
		for x in range(size.x):
			var wx := ctx.origin.x + x
			var wz := ctx.origin.z + z
			var surface := int(ctx.noise.terrain.get_noise_2d(wx, wz) * 24.0) + 32
			var allow_entrance := entrances.get_noise_2d(wx, wz) > 0.45
			for y in range(size.y):
				var wy := ctx.origin.y + y
				if wy < 4 or wy > 120:
					continue

				var local := Vector3i(x, y, z)
				var block_id := ctx.get_block_id_local(local)
				if block_id == AIR or block_id == BEDROCK or surface - wy < 0:
					continue

				var depth := surface - wy
				if depth < 5 and not allow_entrance:
					continue
				# Intersecting noise bands form connected tubes across chunk boundaries.
				var tunnel := absf(tunnels_a.get_noise_3d(wx, wy * 1.35, wz)) < 0.13 and absf(tunnels_b.get_noise_3d(wx, wy * 1.35, wz)) < 0.13
				var chamber := depth >= 8 and chambers.get_noise_3d(wx, wy * 1.4, wz) > 0.48
				if tunnel or chamber:
					ctx.set_voxel_local(local, AIR)


func _stage_ores(ctx: WorldGenContext) -> void:
	var size := ctx.buffer.get_size()

	for z in range(size.z):
		for x in range(size.x):
			for y in range(size.y):
				var local := Vector3i(x, y, z)
				if ctx.get_block_id_local(local) != STONE:
					continue

				var wx := ctx.origin.x + x
				var wy := ctx.origin.y + y
				var wz := ctx.origin.z + z
				var value := ctx.noise.ores.get_noise_3d(wx, wy, wz)
				var ore := STONE

				if wy >= 4 and wy < 12 and value > 0.70:
					ore = DIAMOND
				elif wy < 22 and value > 0.60:
					ore = GOLD
				elif wy < 48 and value > 0.48:
					ore = IRON
				elif value > 0.38:
					ore = COAL

				ctx.set_voxel_local(local, ore)


func _stage_trees(ctx: WorldGenContext) -> void:
	# Keep trees simple and deterministic for now. Mods can register
	# their own structure stages with any order they need.
	var size := ctx.buffer.get_size()

	for z in range(2, size.z - 2):
		for x in range(2, size.x - 2):
			var wx := ctx.origin.x + x
			var wz := ctx.origin.z + z

			if ctx.noise.trees.get_noise_2d(wx, wz) < 0.72:
				continue

			var ground := -1
			for y in range(size.y - 1, -1, -1):
				if ctx.get_voxel_local(Vector3i(x, y, z)) == ctx.content.get_voxel_id(GRASS):
					ground = y
					break

			if ground < 0:
				continue

			var height := 4 + absi(hash(Vector2i(wx, wz))) % 3

			for i in range(height):
				var local := Vector3i(x, ground + 1 + i, z)
				if ctx.inside(local) and ctx.get_block_id_local(local) == AIR:
					ctx.set_voxel_local(local, LOG)

			var top := ground + 1 + height
			for ly in range(-1, 2):
				var radius := 2 if ly <= 0 else 1
				for lx in range(-radius, radius + 1):
					for lz in range(-radius, radius + 1):
						if lx * lx + lz * lz > radius * radius:
							continue
						var leaf_pos := Vector3i(x + lx, top + ly, z + lz)
						if (
							ctx.inside(leaf_pos)
							and ctx.get_block_id_local(leaf_pos) == AIR
						):
							ctx.set_voxel_local(leaf_pos, LEAVES)


func _mining_tool(block_id: String) -> String:
	if block_id in [STONE, IRON, COAL, GOLD, DIAMOND, SANDSTONE, ICE]:
		return "pickaxe"
	if block_id == LOG:
		return "axe"
	if block_id in [GRASS, DIRT, SAND, SNOW, GRAVEL]:
		return "shovel"
	return ""
