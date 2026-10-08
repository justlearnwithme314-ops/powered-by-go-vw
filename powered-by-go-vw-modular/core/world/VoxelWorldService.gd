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


## Construct the standard six-sided cube model used by JSON content packs.
## Face keys: side (required), top, bottom and front (optional, default side).
func build_cube_model(textures: Dictionary, tint: Color = Color.WHITE, transparent: bool = false) -> VoxelBlockyModelCube:
	if not textures.get("side") is Texture2D:
		return null
	var side: Image = textures.side.get_image()
	if side == null or side.is_empty():
		return null
	side.convert(Image.FORMAT_RGBA8)
	var atlas := Image.create(side.get_width() * 4, side.get_height(), false, Image.FORMAT_RGBA8)
	var tiles: Dictionary = {"side": side, "top": side, "bottom": side, "front": side}
	for face: String in textures:
		var texture := textures[face] as Texture2D
		if texture == null:
			return null
		var image := texture.get_image()
		if image == null or image.is_empty():
			return null
		image.convert(Image.FORMAT_RGBA8)
		if image.get_size() != side.get_size():
			return null
		tiles[face] = image
	var face_names := ["side", "top", "bottom", "front"]
	for index in range(face_names.size()):
		var face_name: String = face_names[index]
		atlas.blit_rect(tiles[face_name], Rect2i(Vector2i.ZERO, side.get_size()), Vector2i(side.get_width() * index, 0))
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(atlas)
	material.albedo_color = tint
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 1.0
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var model := VoxelBlockyModelCube.new()
	model.atlas_size_in_tiles = Vector2i(4, 1)
	model.tile_top = Vector2i(1, 0)
	model.tile_bottom = Vector2i(2, 0)
	model.tile_front = Vector2i(3, 0)
	model.set_material_override(0, material)
	return model


func attach(new_terrain: VoxelTerrain) -> void:
	terrain = new_terrain
	tool = terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE


func detach() -> void:
	tool = null
	terrain = null


func is_ready() -> bool:
	return terrain != null and tool != null

## Air from an unloaded area is not traversable terrain.
func is_loaded(position: Vector3i) -> bool:
	return tool != null and tool.is_area_editable(AABB(Vector3(position), Vector3.ONE))

func is_solid(position: Vector3i) -> bool:
	return bool(content.get_block(get_block_id(position)).get("solid", false))

func can_stand(position: Vector3i, height: int = 2) -> bool:
	if not is_loaded(position + Vector3i.DOWN) or not is_solid(position + Vector3i.DOWN):
		return false
	for y in range(height):
		var cell := position + Vector3i(0, y, 0)
		if not is_loaded(cell) or is_solid(cell) or get_block_id(cell) == "core:water":
			return false
	return true

## Authority-side terrain loading for remote actors, without exposing the backend.
func track_actor(actor: Node3D, distance: int = 64) -> Node3D:
	if actor.has_node("AuthorityWorldViewer"):
		return actor.get_node("AuthorityWorldViewer") as Node3D
	var viewer := VoxelViewer.new()
	viewer.name = "AuthorityWorldViewer"
	viewer.view_distance = clampi(distance, 16, 64)
	actor.add_child(viewer)
	return viewer


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
	return int(tool.get_voxel(pos)) == voxel_id


func set_block(pos: Vector3i, block_id: String) -> bool:
	if not content.has_block(block_id):
		return false
	return set_voxel(pos, content.get_voxel_id(block_id))


func raycast(origin: Vector3, direction: Vector3, max_distance: float = 10.0):
	if tool == null:
		return null

	tool.channel = VoxelBuffer.CHANNEL_TYPE
	return tool.raycast(origin, direction.normalized(), max_distance)
