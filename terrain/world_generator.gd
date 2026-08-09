@tool
extends VoxelGeneratorScript

var noise := WorldNoise.new()


func _init() -> void:
	print("[WorldGenerator] Generator initialized.")


func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_TYPE


func _generate_block(buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	if lod != 0:
		return

	TerrainGenerator.generate(buffer, origin, noise)
	OreGenerator.generate(buffer, origin, noise)
	CaveGenerator.generate(buffer, origin, noise)
	TreeGenerator.generate(buffer, origin, noise)
