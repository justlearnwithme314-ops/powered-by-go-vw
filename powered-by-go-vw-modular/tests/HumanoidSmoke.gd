extends SceneTree

func _initialize() -> void:
	var script := load("res://mods/first_creatures/HumanoidVisual.gd") as Script
	for height in [32, 64]:
		var image := Image.create(64, height, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		var visual := script.new() as Node3D
		root.add_child(visual)
		visual.setup({"skin": ImageTexture.create_from_image(image), "arm_width": 3 if height == 64 else 4})
		assert(visual.limbs.size() == 4 and visual.body.get_child_count() == 6)
		for joint in visual.body.get_children():
			var mesh: ArrayMesh = joint.get_child(0).mesh
			var arrays := mesh.surface_get_arrays(0)
			assert(arrays[Mesh.ARRAY_VERTEX].size() == 36)
			for uv in arrays[Mesh.ARRAY_TEX_UV]:
				assert(uv.x >= 0 and uv.y >= 0 and uv.x <= 1 and uv.y <= 1)
		for state in ["idle", "wander", "chase", "attack", "dead"]:
			visual.animate(state, 1.0, 0.0)
		visual.free()
	for kind in ["creeper", "slime"]:
		var visual := load("res://mods/first_creatures/BoxMobVisual.gd").new() as Node3D
		root.add_child(visual)
		visual.setup({"skin": load("res://mods/first_creatures/textures/" + kind + ".png"), "box_shape": kind})
		assert(visual.body.get_child_count() == (1 if kind == "slime" else 6))
		visual.animate("wander", 1.0, 0.0)
		visual.animate("dead", 2.0, 0.0)
		visual.free()
	var zombie := script.new() as Node3D
	root.add_child(zombie)
	var skin := load("res://mods/first_creatures/textures/zombie.png") as Texture2D
	assert(skin != null)
	zombie.setup({"skin": skin, "classic_limbs": true})
	assert(zombie.material.albedo_texture == skin)
	assert(zombie.atlas_size == Vector2(64,64))
	var uv: Vector2 = Vector2(12,12) / zombie.atlas_size
	var pixels := skin.get_image()
	assert(pixels.get_pixel(int(uv.x * pixels.get_width()), int(uv.y * pixels.get_height())).a > 0.5)
	print("Zombie skin assigned: ", skin.get_size(), "; logical UV atlas: ", zombie.atlas_size)
	zombie.free()
	print("Humanoid and box mobs PASS: skin UVs, geometry and animations")
	quit()
