class_name CaveGenerator

const CAVE_THRESHOLD := 0.62
const MIN_HEIGHT := 4
const MAX_HEIGHT := 120


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

				# Never carve air
				if block == Block.AIR:
					continue

				var wx := origin.x + x
				var wy := origin.y + y
				var wz := origin.z + z

				if wy < MIN_HEIGHT:
					continue

				if wy > MAX_HEIGHT:
					continue

				if should_carve(wx, wy, wz, noise):
					buffer.set_voxel(
						Block.AIR,
						x,
						y,
						z,
						VoxelBuffer.CHANNEL_TYPE
					)
static func should_carve(
	wx: int,
	wy: int,
	wz: int,
	noise: WorldNoise
) -> bool:

	var value := noise.caves.get_noise_3d(
		wx,
		wy,
		wz
	)

	return value > CAVE_THRESHOLD
