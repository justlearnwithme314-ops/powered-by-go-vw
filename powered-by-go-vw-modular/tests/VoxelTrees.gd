@tool
extends Node

const TREE_SCRIPT = preload("res://mods/tree_props/mod.gd")
const CORE_SCRIPT = preload("res://content/core/mod.gd")
const FRONTIER_SCRIPT = preload("res://mods/frontier_survival/mod.gd")

func suite_name() -> String:
	return "voxel_trees"

func _snapshot() -> ContentSnapshot:
	# Deliberately non-production IDs prove the stage uses logical IDs.
	var result := ContentSnapshot.new()
	var ids := ["core:air", "core:grass", "core:dirt", "core:stone", "core:log", "core:leaves", "core:snow", "core:sand", "core:iron_ore", "core:coal_ore", "core:gold_ore", "core:diamond_ore", "frontier:japanese_grass", "frontier:prairie_grass", "frontier:bamboo_grass"]
	for i in range(ids.size()):
		var number := 0 if i == 0 else 50 + i
		result._block_to_voxel[ids[i]] = number
		result._voxel_to_block[number] = ids[i]
	return result

func _context(origin: Vector3i, size: Vector3i, seed_value: int = 1337) -> WorldGenContext:
	var buffer := VoxelBuffer.new()
	buffer.create(size.x, size.y, size.z)
	return WorldGenContext.new(buffer, origin, 0, seed_value, WorldNoise.new(seed_value), _snapshot())

func _generate(origin: Vector3i, size: Vector3i) -> WorldGenContext:
	var ctx := _context(origin, size)
	var core := CORE_SCRIPT.new()
	core._stage_terrain(ctx)
	core._stage_caves(ctx)
	core._stage_ores(ctx)
	TREE_SCRIPT.new()._generate_trees(ctx)
	FRONTIER_SCRIPT.new()._generate_biomes(ctx)
	return ctx

func _find_tree() -> Vector3i:
	var mod := TREE_SCRIPT.new()
	var ctx := _context(Vector3i.ZERO, Vector3i.ONE)
	for z in range(-64, 0):
		for x in range(-64, 0):
			var root: Vector2i = mod._root_for_cell(x, z, ctx.world_seed)
			var ground: int = mod._ground_for(ctx, root)
			if ground >= 0 and ctx.noise.trees.get_noise_2d(root.x, root.y) >= mod.TREE_THRESHOLD:
				return Vector3i(root.x, ground, root.y)
	assert(false, "Natural negative-coordinate tree fixture not found")
	return Vector3i.ZERO

func test_generation_matches_split_chunks_and_repeat() -> void:
	var root := _find_tree()
	var origin := root - Vector3i(16, 12, 16)
	var full := _generate(origin, Vector3i(32, 32, 32))
	var repeat := _generate(origin, Vector3i(32, 32, 32))
	var logs := 0
	var leaves := 0
	for cz in range(2):
		for cy in range(2):
			for cx in range(2):
				var offset := Vector3i(cx, cy, cz) * 16
				var chunk := _generate(origin + offset, Vector3i(16, 16, 16))
				for z in range(16):
					for y in range(16):
						for x in range(16):
							var p := Vector3i(x, y, z)
							var expected := full.get_block_id_local(p + offset)
							assert(chunk.get_block_id_local(p) == expected, "XYZ chunk seam mismatch")
							assert(repeat.get_block_id_local(p + offset) == expected, "Non-deterministic generation")
							logs += 1 if expected == "core:log" else 0
							leaves += 1 if expected == "core:leaves" else 0
	assert(logs >= 4 and leaves > 20, "No actual voxel tree generated")

func test_clipped_writes_preserve_non_air() -> void:
	var ctx := _context(Vector3i(-1, 30, -1), Vector3i(4, 4, 4))
	ctx.set_voxel_local(Vector3i(1, 1, 1), "core:stone")
	TREE_SCRIPT.new()._emit_tree(ctx, Vector3i(0, 30, 0), 6)
	assert(ctx.get_block_id_local(Vector3i(1, 1, 1)) == "core:stone")
	assert(ctx.get_block_id_local(Vector3i(1, 2, 1)) == "core:log")

func test_seed_spacing_and_surface_rules() -> void:
	var mod := TREE_SCRIPT.new()
	var ctx := _context(Vector3i.ZERO, Vector3i.ONE)
	var rejected := 0
	for z in range(-16, 16):
		for x in range(-16, 16):
			var a: Vector2i = mod._root_for_cell(x, z, 1337)
			var b: Vector2i = mod._root_for_cell(x + 1, z, 1337)
			assert(b.x - a.x >= 5)
			assert(a == mod._root_for_cell(x, z, 1337))
			var temperature := ctx.noise.temperature.get_noise_2d(a.x, a.y)
			var humidity := ctx.noise.humidity.get_noise_2d(a.x, a.y)
			var surface := int(ctx.noise.terrain.get_noise_2d(a.x, a.y) * 24.0) + 32
			var unsuitable := temperature < -0.15 or (temperature > 0.45 and humidity < 0.0) or ctx.noise.caves.get_noise_3d(a.x, surface, a.y) > 0.62
			assert(mod._ground_for(ctx, a) == (-1 if unsuitable else surface))
			rejected += 1 if unsuitable else 0
	assert(rejected > 0)
	assert(mod._root_for_cell(-8, -4, 1337) != mod._root_for_cell(-8, -4, 42))

func test_manifest_and_no_runtime_props() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://mods/tree_props/mod.json"))
	assert(manifest.id == "core:tree_props" and manifest.version == "2.0.0")
	assert("core:base" in manifest.dependencies and manifest.entry == "mod.gd")
	var source := FileAccess.get_file_as_string("res://mods/tree_props/mod.gd")
	for forbidden in ["api.on(", "GameAPI", "Node3D", "VoxelTool", "VoxelTerrain", "storage", "print(", "load_asset"]:
		assert(not source.contains(forbidden), "Runtime/backend dependency: " + forbidden)
	assert(source.contains('"core:tree_props:trees", 400'))
