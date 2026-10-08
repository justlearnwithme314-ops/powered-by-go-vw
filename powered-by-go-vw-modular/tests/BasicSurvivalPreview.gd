extends Node3D

func _ready() -> void:
	var env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.12,0.16,0.22)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.6
	env.environment = environment
	add_child(env)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-25,0)
	light.shadow_enabled = true
	add_child(light)
	var floor_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(28,20)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(10,-0.02,2)
	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.25,0.3,0.22)
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)
	var camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(10,10,22)
	camera.look_at(Vector3(10,0.8,1))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 25
	var kinds = ["pig","cow","sheep","chicken","zombie","skeleton","creeper","spider"]
	for i in range(kinds.size()):
		var definition = GameAPI.entities.definition("creatures:"+kinds[i])
		var visual = definition.visual.new()
		add_child(visual)
		visual.setup(definition)
		visual.position = Vector3(i*3,0,-2)
		visual.animate("idle",0,0)
		caption(kinds[i],visual.position+Vector3(0,2.5,0))
	var ids = ["survival:oak_log","survival:spruce_log","survival:birch_log","survival:jungle_log","survival:acacia_log","survival:dark_oak_log","survival:mangrove_log","survival:chest"]
	for i in range(ids.size()):
		var instance = MeshInstance3D.new()
		instance.mesh = GameAPI.world.get_block_display_mesh(ids[i])
		instance.position = Vector3(i*3-0.5,0,3)
		add_child(instance)
		caption(ids[i].get_slice(":",1),Vector3(i*3,1.8,3))
	for i in range(8):
		var instance = MeshInstance3D.new()
		instance.mesh = GameAPI.world.get_block_display_mesh("survival:wheat_crop_"+str(i))
		instance.position = Vector3(i*3-0.5,0,6)
		add_child(instance)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/basic-survival-preview.png")
	print("Basic survival preview saved")
	get_tree().quit()

func caption(text: String, position: Vector3) -> void:
	var label = Label3D.new()
	label.text = text
	label.font_size = 35
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = position
	add_child(label)
