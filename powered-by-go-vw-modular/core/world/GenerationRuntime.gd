class_name GenerationRuntime
extends Resource

## Frozen generation configuration installed into a VoxelGeneratorScript.
##
## Zylann may invoke generation on worker threads. No method here may access
## GameAPI, SceneTree, Nodes, multiplayer state, or mutable registries.

var world_seed: int = 1337
var content: ContentSnapshot
var stages: Array = []


func configure(
	p_world_seed: int,
	p_content: ContentSnapshot,
	p_stages: Array
) -> GenerationRuntime:
	world_seed = p_world_seed
	content = p_content
	stages = p_stages.duplicate()
	return self


func generate(buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	if content == null:
		return

	var noise := WorldNoise.new(world_seed)
	var context := WorldGenContext.new(
		buffer,
		origin,
		lod,
		world_seed,
		noise,
		content
	)

	for stage_variant in stages:
		var stage: Dictionary = stage_variant
		var callback: Callable = stage.get("callback", Callable())
		if callback.is_valid():
			callback.call(context)
