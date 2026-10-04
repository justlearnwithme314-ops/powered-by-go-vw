class_name WorldGenContext
extends RefCounted

## Context passed to generation stages. All operations are thread-safe in the
## sense required by Zylann's worker-thread generator: no SceneTree access,
## no nodes, and no mutable global services.

var buffer: VoxelBuffer
var origin: Vector3i
var lod: int
var world_seed: int
var noise: WorldNoise
var content: ContentSnapshot


func _init(
	p_buffer: VoxelBuffer,
	p_origin: Vector3i,
	p_lod: int,
	p_world_seed: int,
	p_noise: WorldNoise,
	p_content: ContentSnapshot
) -> void:
	buffer = p_buffer
	origin = p_origin
	lod = p_lod
	world_seed = p_world_seed
	noise = p_noise
	content = p_content


func set_voxel_local(pos: Vector3i, block_id: String) -> void:
	buffer.set_voxel(
		content.get_voxel_id(block_id),
		pos.x,
		pos.y,
		pos.z,
		VoxelBuffer.CHANNEL_TYPE
	)


func get_voxel_local(pos: Vector3i) -> int:
	return buffer.get_voxel(
		pos.x,
		pos.y,
		pos.z,
		VoxelBuffer.CHANNEL_TYPE
	)


func get_block_id_local(pos: Vector3i) -> String:
	return content.get_block_id_from_voxel(get_voxel_local(pos))


func world_position(local_pos: Vector3i) -> Vector3i:
	return origin + local_pos


func inside(local_pos: Vector3i) -> bool:
	var size := buffer.get_size()
	return (
		local_pos.x >= 0 and local_pos.x < size.x
		and local_pos.y >= 0 and local_pos.y < size.y
		and local_pos.z >= 0 and local_pos.z < size.z
	)
