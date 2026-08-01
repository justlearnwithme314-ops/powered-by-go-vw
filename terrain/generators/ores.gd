class_name OreGenerator

const IRON_THRESHOLD := 0.65

const COAL_THRESHOLD := 0.55

const GOLD_THRESHOLD := 0.72

const DIAMOND_THRESHOLD := 0.82


static func generate(
	buffer: VoxelBuffer,
	origin: Vector3i,
	noise: WorldNoise
) -> void:

	var size := buffer.get_size()

	for z in range(size.z):
		for x in range(size.x):
			for y in range(size.y):

				var block := buffer.get_voxel(
					x,
					y,
					z,
					VoxelBuffer.CHANNEL_TYPE
				)

				if block != Block.STONE:
					continue

				var wx := origin.x + x
				var wy := origin.y + y
				var wz := origin.z + z

				var ore := get_ore(wx, wy, wz, noise)

				if ore != Block.STONE:
					buffer.set_voxel(
						ore,
						x,
						y,
						z,
						VoxelBuffer.CHANNEL_TYPE
					)
static func get_ore(
	wx:int,
	wy:int,
	wz:int,
	noise:WorldNoise
) -> int:

	var value := noise.ores.get_noise_3d(wx, wy, wz)

	# Diamonds

	if wy < 5 and value > DIAMOND_THRESHOLD:
		return Block.DIAMOND

	# Gold

	if wy < 16 and value > GOLD_THRESHOLD:
		return Block.GOLD

	# Iron

	if wy < 48 and value > IRON_THRESHOLD:
		return Block.IRON

	# Coal

	if value > COAL_THRESHOLD:
		return Block.COAL

	return Block.STONE
