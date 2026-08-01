@tool
extends VoxelGeneratorScript

var noise := WorldNoise.new()

func _init():
	print("Generator initialized")

func _generate_block(buffer, origin, lod):
	print("Generating:", origin)

	if lod != 0:
		return

	TerrainGenerator.generate(buffer, origin, noise)
	CaveGenerator.generate(buffer, origin, noise)
	OreGenerator.generate(buffer, origin, noise)
	TreeGenerator.generate(buffer, origin, noise)
