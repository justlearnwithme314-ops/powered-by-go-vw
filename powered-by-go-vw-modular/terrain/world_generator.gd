@tool
extends VoxelGeneratorScript

## Thin adapter between Zylann VoxelTerrain and our world-generation runtime.
##
## IMPORTANT: _generate_block may run on worker threads. Never access
## GameAPI, SceneTree, nodes, autoloads, or mutable registries here.

@export var runtime: GenerationRuntime


func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_TYPE


func _generate_block(buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	if lod != 0 or Engine.is_editor_hint():
		return
	if runtime == null:
		return

	runtime.generate(buffer, origin, lod)
