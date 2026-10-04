extends Node3D

func _ready() -> void:
	var mapping: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/block_textures/mapping.json"))
	var library: VoxelBlockyLibrary = VoxelBlockyLibrary.new()
	var models: Array[VoxelBlockyModel] = [VoxelBlockyModelEmpty.new()]
	var index: int = 0
	for path: String in mapping:
		var model: VoxelBlockyModelCube = load("res://" + path) as VoxelBlockyModelCube
		assert(model != null, path)
		assert(model.atlas_size_in_tiles == Vector2i(8, 8), path)
		var material: StandardMaterial3D = model.get_material_override(0) as StandardMaterial3D
		assert(material != null and material.albedo_texture != null, path)
		assert(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, path)
		for side: int in range(6):
			var tile: Vector2i = model.get_tile(side)
			assert(tile.x >= 0 and tile.x < 8 and tile.y >= 0 and tile.y < 8, path)
		models.append(model)
		index += 1
	library.models = models
	library.bake()
	var mesher: VoxelMesherBlocky = VoxelMesherBlocky.new()
	mesher.library = library
	for number: int in range(index):
		var buffer: VoxelBuffer = VoxelBuffer.new()
		buffer.create(3, 3, 3)
		buffer.set_voxel(number + 1, 1, 1, 1, VoxelBuffer.CHANNEL_TYPE)
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.mesh = mesher.build_mesh(buffer, library.get_materials())
		assert(mesh.mesh != null and mesh.mesh.get_surface_count() > 0)
		mesh.position = Vector3((number % 8) * 1.5 - 5.75, 0.0, (number / 8) * 1.5 - 4.5)
		add_child(mesh)
	var grass: VoxelBlockyModelCube = load("res://content/core/models/grass.tres")
	assert(grass.get("tile_top") != grass.get("tile_front"))
	assert(grass.get("tile_bottom") != grass.get("tile_top"))
	print("Block texture validation PASS: ", index, " models, atlas faces, nearest filtering and voxel library bake")
	if "--validate-only" in OS.get_cmdline_user_args():
		get_tree().quit()
	elif "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://assets/block_textures/preview.png")
		get_tree().quit()
