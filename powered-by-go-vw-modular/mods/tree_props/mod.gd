class_name VoxelBlockTreesMod
extends GameMod
## Voxel trees; legacy mod ID retained for dependency/save compatibility.
## Pure worldgen: no runtime props, input interception, or save migration.

const AIR := "core:air"
const LOG := "core:log"
const LEAVES := "core:leaves"
const CELL_SIZE := 8
const CANOPY_RADIUS := 2
const TREE_THRESHOLD := 0.30

func register(api: ModAPI) -> void:
	# After terrain/caves/ores, before Frontier's grass repaint (450).
	api.register_worldgen_stage("core:tree_props:trees", 400,
		Callable(self, "_generate_trees"))

func _root_for_cell(cell_x: int, cell_z: int, seed_value: int) -> Vector2i:
	# Jitter restricted to 0..3: roots remain at least five blocks apart.
	var value: int = hash(Vector3i(cell_x, seed_value, cell_z))
	return Vector2i(cell_x * CELL_SIZE + posmod(value, 4),
		cell_z * CELL_SIZE + posmod(value >> 8, 4))

func _ground_for(ctx: WorldGenContext, root: Vector2i) -> int:
	# Reproduce core terrain and cave rules even when the supporting voxel
	# belongs to another chunk. Never decide roots from chunk-local scans.
	var temperature := ctx.noise.temperature.get_noise_2d(root.x, root.y)
	if temperature < -0.15:
		return -1
	if temperature > 0.45 and ctx.noise.humidity.get_noise_2d(root.x, root.y) < 0.0:
		return -1
	var ground := int(ctx.noise.terrain.get_noise_2d(root.x, root.y) * 24.0) + 32
	if ctx.noise.caves.get_noise_3d(root.x, ground, root.y) > 0.62:
		return -1
	return ground

func _generate_trees(ctx: WorldGenContext) -> void:
	var size := ctx.buffer.get_size()
	# Core surface is 8..56; tallest crown reaches ground + 8.
	if ctx.origin.y >= 65 or ctx.origin.y + size.y <= 9:
		return
	var min_x := floori(float(ctx.origin.x - CANOPY_RADIUS) / CELL_SIZE)
	var max_x := floori(float(ctx.origin.x + size.x - 1 + CANOPY_RADIUS) / CELL_SIZE)
	var min_z := floori(float(ctx.origin.z - CANOPY_RADIUS) / CELL_SIZE)
	var max_z := floori(float(ctx.origin.z + size.z - 1 + CANOPY_RADIUS) / CELL_SIZE)
	for cell_z in range(min_z, max_z + 1):
		for cell_x in range(min_x, max_x + 1):
			var root := _root_for_cell(cell_x, cell_z, ctx.world_seed)
			if ctx.noise.trees.get_noise_2d(root.x, root.y) < TREE_THRESHOLD:
				continue
			var ground := _ground_for(ctx, root)
			if ground < 0:
				continue
			var height := 4 + posmod(hash(Vector3i(root.x, ctx.world_seed, root.y)), 3)
			_emit_tree(ctx, Vector3i(root.x, ground, root.y), height)

func _emit_tree(ctx: WorldGenContext, base: Vector3i, height: int) -> void:
	var species: Array[String] = []
	for id in ctx.content.blocks:
		if "survival:tree_log" in ctx.content.blocks[id].tags: species.append(str(id))
	species.sort()
	var log_id := LOG
	var leaves_id := LEAVES
	if not species.is_empty():
		log_id = species[posmod(hash(Vector3i(base.x,ctx.world_seed,base.z)),species.size())]
		leaves_id = log_id.replace("_log","_leaves")
	for dy in range(1, height + 1):
		_write_air(ctx, base + Vector3i(0, dy, 0), log_id)
	for dy in range(height - 1, height + 3):
		var radius := CANOPY_RADIUS if dy <= height else 1
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dz * dz <= radius * radius:
					_write_air(ctx, base + Vector3i(dx, dy, dz), leaves_id)

func _write_air(ctx: WorldGenContext, world_pos: Vector3i, block_id: String) -> void:
	var local := world_pos - ctx.origin
	if ctx.inside(local) and ctx.get_block_id_local(local) == AIR:
		ctx.set_voxel_local(local, block_id)
