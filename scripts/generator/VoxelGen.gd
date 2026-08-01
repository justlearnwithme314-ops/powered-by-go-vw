extends VoxelGeneratorScript

@export var terrain_height := 24
@export var terrain_offset := 32

var terrain_noise := FastNoiseLite.new()
var ore_noise := FastNoiseLite.new()
var tree_noise := FastNoiseLite.new()

func _init():
	# Terrain
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	terrain_noise.frequency = 0.008
	terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	terrain_noise.fractal_octaves = 4

	# Ores
	ore_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ore_noise.frequency = 0.03

	# Trees
	tree_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	tree_noise.frequency = 0.025

func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_TYPE


func _generate_block(buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	if lod != 0:
		return

	var size := buffer.get_size()

	for z in range(size.z):
		for x in range(size.x):

			var wx := origin.x + x
			var wz := origin.z + z

			var surface := int(
				terrain_noise.get_noise_2d(wx, wz) * terrain_height
			) + terrain_offset

			# Terrain
			for y in range(size.y):

				var wy := origin.y + y

				if wy > surface:
					buffer.set_voxel(0, x, y, z, VoxelBuffer.CHANNEL_TYPE)
					continue

				var depth := surface - wy

				if depth == 0:
					buffer.set_voxel(1, x, y, z, VoxelBuffer.CHANNEL_TYPE)

				elif depth <= 3:
					buffer.set_voxel(2, x, y, z, VoxelBuffer.CHANNEL_TYPE)

				else:
					var ore := ore_noise.get_noise_3d(wx, wy, wz)

				var ore := ore_noise.get_noise_3d(wx, wy, wz)

				if depth > 4 and ore > 0.65:
					buffer.set_voxel(6, x, y, z, VoxelBuffer.CHANNEL_TYPE) # Iron ore
				else:
					buffer.set_voxel(3, x, y, z, VoxelBuffer.CHANNEL_TYPE) # Stone

			# Trees
			if tree_noise.get_noise_2d(wx, wz) > 0.72:

				var local_surface := surface - origin.y + 1

				if local_surface > 0 and local_surface + 8 < size.y:
					generate_tree(buffer, x, local_surface, z)



func generate_tree(buffer: VoxelBuffer, x: int, y: int, z: int) -> void:
	var size := buffer.get_size()

	# Random trunk height
	var trunk_height := randi_range(4, 6)

	# Trunk
	for i in range(trunk_height):
		if y + i < size.y:
			buffer.set_voxel(4, x, y + i, z, VoxelBuffer.CHANNEL_TYPE)

	var top := y + trunk_height

	# Bottom leaf layer (5x5 with corners removed)
	for lx in range(-2, 3):
		for lz in range(-2, 3):
			if abs(lx) == 2 and abs(lz) == 2:
				continue

			if x + lx < 0 or x + lx >= size.x:
				continue
			if z + lz < 0 or z + lz >= size.z:
				continue
			if top - 2 < 0 or top - 2 >= size.y:
				continue

			buffer.set_voxel(5, x + lx, top - 2, z + lz, VoxelBuffer.CHANNEL_TYPE)

	# Middle leaf layer (5x5)
	for lx in range(-2, 3):
		for lz in range(-2, 3):
			if x + lx < 0 or x + lx >= size.x:
				continue
			if z + lz < 0 or z + lz >= size.z:
				continue
			if top - 1 < 0 or top - 1 >= size.y:
				continue

			buffer.set_voxel(5, x + lx, top - 1, z + lz, VoxelBuffer.CHANNEL_TYPE)

	# Upper leaf layer (3x3)
	for lx in range(-1, 2):
		for lz in range(-1, 2):
			if x + lx < 0 or x + lx >= size.x:
				continue
			if z + lz < 0 or z + lz >= size.z:
				continue
			if top < 0 or top >= size.y:
				continue

			buffer.set_voxel(5, x + lx, top, z + lz, VoxelBuffer.CHANNEL_TYPE)

	# Small crown
	if top + 1 < size.y:
		buffer.set_voxel(5, x, top + 1, z, VoxelBuffer.CHANNEL_TYPE)
