class_name VoxelWorldService
extends RefCounted

## The only service that directly touches VoxelTerrain/VoxelTool.
## Player code and mods should use this abstraction instead.

var content: ContentRegistry
var events: EventBus = null
var terrain: VoxelTerrain = null
var tool: VoxelTool = null
var _display_meshes: Dictionary = {}

## Presentation clients can display blocks without knowing voxel IDs or meshers.
func get_block_display_mesh(block_id: String) -> Mesh:
	if _display_meshes.has(block_id):
		return _display_meshes[block_id] as Mesh
	var model: VoxelBlockyModel = content.get_block(block_id).get("model") as VoxelBlockyModel
	if model == null:
		return null
	var library: VoxelBlockyLibrary = VoxelBlockyLibrary.new()
	library.models = [VoxelBlockyModelEmpty.new(), model]
	library.bake()
	var mesher: VoxelMesherBlocky = VoxelMesherBlocky.new()
	mesher.library = library
	var buffer: VoxelBuffer = VoxelBuffer.new()
	buffer.create(3, 3, 3)
	buffer.set_voxel(1, 1, 1, 1, VoxelBuffer.CHANNEL_TYPE)
	var mesh: Mesh = mesher.build_mesh(buffer, library.get_materials())
	_display_meshes[block_id] = mesh
	return mesh


func _init(p_content: ContentRegistry, p_events: EventBus = null) -> void:
	content = p_content
	events = p_events


func attach(new_terrain: VoxelTerrain) -> void:
	terrain = new_terrain
	tool = terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE


func detach() -> void:
	tool = null
	terrain = null


func is_ready() -> bool:
	return terrain != null and tool != null


func get_voxel(pos: Vector3i) -> int:
	if tool == null:
		return content.get_voxel_id(ContentRegistry.AIR_ID)
	return int(tool.get_voxel(pos))


func get_block_id(pos: Vector3i) -> String:
	return content.get_block_id_from_voxel(get_voxel(pos))


func set_voxel(pos: Vector3i, voxel_id: int) -> bool:
	if tool == null:
		return false

	tool.channel = VoxelBuffer.CHANNEL_TYPE
	tool.set_voxel(pos, voxel_id)
	return true


func set_block(pos: Vector3i, block_id: String) -> bool:
	if not content.has_block(block_id):
		return false
	return set_voxel(pos, content.get_voxel_id(block_id))


func raycast(origin: Vector3, direction: Vector3, max_distance: float = 10.0):
	if tool == null:
		return null

	tool.channel = VoxelBuffer.CHANNEL_TYPE
	return tool.raycast(origin, direction.normalized(), max_distance)
