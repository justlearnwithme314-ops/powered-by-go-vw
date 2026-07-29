@tool
extends VoxelGeneratorScript

@export var terrain_height := 24
@export var terrain_offset := 32
@export var frequency := 0.008

var noise := FastNoiseLite.new()

func _init():
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0

func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_TYPE

func _generate_block(buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	if lod != 0:
		return

	var size := buffer.get_size()

	for z in size.z:
		for x in size.x:

			var wx = origin.x + x
			var wz = origin.z + z

			var height = int(noise.get_noise_2d(wx, wz) * terrain_height) + terrain_offset

			for y in size.y:
				var wy = origin.y + y

				var block = get_block(height, wy)
				buffer.set_voxel(block, x, y, z, VoxelBuffer.CHANNEL_TYPE)


func get_block(surface: int, y: int) -> int:
	if y > surface:
		return 0 # Air

	var depth = surface - y

	if depth == 0:
		return 1 # Grass

	if depth <= 3:
		return 2 # Dirt

	return 3 # Stone
