extends Node3D

func _ready() -> void:
	var environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12,0.16,0.22)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.5
	add_child(environment)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-25,0)
	light.light_energy = 0.8
	light.shadow_enabled = true
	add_child(light)
	var floor_mesh = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(23,20)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(5,-0.02,2)
	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.25,0.3,0.22)
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)
	var camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(13,9,18)
	camera.look_at(Vector3(5,1,2))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16
	var kinds = ["pig","cow","sheep","chicken","zombie","skeleton","creeper","spider"]
	for i in range(kinds.size()):
		var definition = GameAPI.entities.definition("creatures:"+kinds[i])
		var visual = definition.visual.new()
		add_child(visual)
		visual.setup(definition)
		visual.position = Vector3((i%4)*3.4,0,(i/4)*4)
		visual.rotation.y = PI
		visual.animate("idle",0,0)
		var label = Label3D.new()
		label.text = kinds[i]
		label.font_size = 32
		label.pixel_size = 0.008
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = visual.position+Vector3(0,2.5,0)
		add_child(label)
	var runtime = load("res://mods/basic_survival/ExplosionRuntime.gd").new()
	add_child(runtime)
	runtime.api = ModAPI.new(GameAPI.content,GameAPI.events,GameAPI.world_generation,GameAPI.world,GameAPI.edits,GameAPI.crafting,"preview:test","1","res://mods/basic_survival")
	runtime.api.entities = EntityRegistry.new()
	var mock = Node.new()
	mock.set_script(load("res://tests/PreviewEntityRecords.gd"))
	add_child(mock)
	runtime.api.entities.runtime = mock
	runtime.blast_sound = runtime.make_blast_sound()
	runtime.show_blast(Vector3(11,1,7))
	await get_tree().create_timer(0.12).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/mob-explosion-preview.png")
	get_tree().quit()
