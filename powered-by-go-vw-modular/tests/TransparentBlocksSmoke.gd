extends Node

func _ready() -> void:
	var library := GameAPI.content.build_voxel_library()
	library.bake()
	var mesher := VoxelMesherBlocky.new()
	mesher.library = library
	for id in ["core:leaves","core:water","core:ice","building:glass"]:
		var model := library.get_model(GameAPI.content.get_voxel_id(id))
		assert(not model.culls_neighbors and model.transparency_index > 0)
	# Inspect actual native mesh triangles: the opaque neighbour's shared face
	# must survive, rather than merely checking the model's configuration.
	var opaque := face_count(mesher,"core:dirt")
	for id in ["core:leaves","building:glass"]:
		assert(face_count(mesher,id) == opaque + 1)
	var glass := GameAPI.content.get_block("building:glass")
	assert(glass.solid and glass.transparent)
	var leaf_ids = ["core:leaves"]
	for wood in ["oak","spruce","birch","jungle","acacia","dark_oak","mangrove"]:
		leaf_ids.append("survival:"+wood+"_leaves")
	for id in leaf_ids + ["building:glass"]:
		var model = GameAPI.content.get_block(id).model
		var material = model.get_material_override(0) as StandardMaterial3D
		assert(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA)
		assert(material.albedo_color.a > 0 and material.albedo_color.a < 1)
		assert(model.atlas_size_in_tiles == Vector2i(1,1))
		var texture_name = "oak_leaves" if id == "core:leaves" else id.get_slice(":",1)
		assert(material.albedo_texture.resource_path.ends_with("/block/"+texture_name+".png"))
	assert(GameAPI.content.get_recipe("building:glass_from_sand").method == "smelt")
	print("Transparent blocks PASS: actual neighbour faces preserved for leaves/glass, opaque culling retained, glass registered and smeltable")
	get_tree().quit()

func face_count(mesher: VoxelMesherBlocky, neighbour: String) -> int:
	var buffer := VoxelBuffer.new()
	buffer.create(6,6,6)
	buffer.set_voxel(GameAPI.content.get_voxel_id("core:dirt"),2,2,2)
	buffer.set_voxel(GameAPI.content.get_voxel_id(neighbour),3,2,2)
	var materials: Array[Material] = []
	var mesh := mesher.build_mesh(buffer,materials)
	var indices := 0
	for surface in range(mesh.get_surface_count()):
		indices += mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size()
	return indices / 6
