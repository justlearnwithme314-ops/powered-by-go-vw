class_name TerrainGenerator

const TERRAIN_HEIGHT := 24
const TERRAIN_OFFSET := 32

const TOP_SOIL_DEPTH := 3


static func generate(
	buffer: VoxelBuffer,
	origin: Vector3i,
	noise: WorldNoise
) -> void:

	var size := buffer.get_size()

	for z in range(size.z):
		for x in range(size.x):

			var wx := origin.x + x
			var wz := origin.z + z

			var surface := get_surface_height(wx, wz, noise)

			generate_column(
				buffer,
				origin,
				noise,
				x,
				z,
				surface
			)


static func get_surface_height(
	wx: int,
	wz: int,
	noise: WorldNoise
) -> int:

	return int(
		noise.terrain.get_noise_2d(wx, wz) * TERRAIN_HEIGHT
	) + TERRAIN_OFFSET


static func generate_column(
	buffer: VoxelBuffer,
	origin: Vector3i,
	noise: WorldNoise,
	x: int,
	z: int,
	surface: int
) -> void:

	var size := buffer.get_size()

	for y in range(size.y):

		var world_y := origin.y + y

		if world_y > surface:
			continue

		var block := get_block_for_depth(
			surface - world_y,
			origin.x + x,
			origin.z + z,
			noise
		)

		buffer.set_voxel(
			block,
			x,
			y,
			z,
			VoxelBuffer.CHANNEL_TYPE
		)


static func get_block_for_depth(
	depth: int,
	wx: int,
	wz: int,
	noise: WorldNoise
) -> int:

	if depth == 0:

		match BiomeGenerator.get_biome(wx, wz, noise):

			Biome.Type.DESERT:
				return Block.SAND # Replace with Block.SAND later

			Biome.Type.SNOW:
				return Block.SNOW # Replace with Block.SNOW later

			Biome.Type.MOUNTAINS:
				return Block.GRASS

			Biome.Type.FOREST:
				return Block.GRASS

			Biome.Type.PLAINS:
				return Block.GRASS

	if depth <= TOP_SOIL_DEPTH:
		return Block.DIRT

	return Block.STONE
