class_name TreeGenerator

const TREE_THRESHOLD := 0.72


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

			if noise.trees.get_noise_2d(wx, wz) < TREE_THRESHOLD:
				continue

			var ground := find_surface(buffer, x, z)

			if ground == -1:
				continue

			generate_tree(
				buffer,
				x,
				ground + 1,
				z,
				wx,
				wz
			)


static func find_surface(
	buffer: VoxelBuffer,
	x: int,
	z: int
) -> int:

	var size := buffer.get_size()

	for y in range(size.y - 1, -1, -1):

		if buffer.get_voxel(
			x,
			y,
			z,
			VoxelBuffer.CHANNEL_TYPE
		) == Block.GRASS:

			return y

	return -1


static func generate_tree(
	buffer: VoxelBuffer,
	x: int,
	y: int,
	z: int,
	wx: int,
	wz: int
) -> void:

	var height: int = 4 + int(abs(hash(Vector2i(wx, wz))) % 3)

	for i in range(height):
		set_log(buffer, x, y + i, z)

	var top := y + height

	for ly in range(-2, 2):

		var radius := 2

		if ly == 1:
			radius = 1

		for lx in range(-radius, radius + 1):
			for lz in range(-radius, radius + 1):

				if lx * lx + lz * lz > radius * radius:
					continue

				set_leaf(
					buffer,
					x + lx,
					top + ly,
					z + lz
				)

	set_leaf(buffer, x, top + 2, z)


static func set_log(
	buffer: VoxelBuffer,
	x: int,
	y: int,
	z: int
) -> void:

	if !inside(buffer, x, y, z):
		return

	if buffer.get_voxel(
		x,
		y,
		z,
		VoxelBuffer.CHANNEL_TYPE
	) == Block.AIR:

		buffer.set_voxel(
			Block.LOG,
			x,
			y,
			z,
			VoxelBuffer.CHANNEL_TYPE
		)


static func set_leaf(
	buffer: VoxelBuffer,
	x: int,
	y: int,
	z: int
) -> void:

	if !inside(buffer, x, y, z):
		return

	if buffer.get_voxel(
		x,
		y,
		z,
		VoxelBuffer.CHANNEL_TYPE
	) == Block.AIR:

		buffer.set_voxel(
			Block.LEAVES,
			x,
			y,
			z,
			VoxelBuffer.CHANNEL_TYPE
		)


static func inside(
	buffer: VoxelBuffer,
	x: int,
	y: int,
	z: int
) -> bool:

	var size := buffer.get_size()

	return (
		x >= 0 and x < size.x
		and y >= 0 and y < size.y
		and z >= 0 and z < size.z
	)
