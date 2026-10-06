extends "HumanoidVisual.gd"

## Prototype geometry for non-player texture atlases; shares the cuboid UV builder.
var shape_kind := "creeper"

func setup(definition: Dictionary) -> void:
	shape_kind = str(definition.get("box_shape", "creeper"))
	material = StandardMaterial3D.new()
	material.albedo_texture = definition.get("skin") as Texture2D
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	if material.albedo_texture != null:
		var texture_size := material.albedo_texture.get_size()
		atlas_size = Vector2(64, 64 * texture_size.y / texture_size.x)
	body = Node3D.new()
	add_child(body)
	scale = definition.get("body_scale", Vector3.ONE)
	if shape_kind == "slime":
		_part("Cube", Vector3(8,8,8), Vector2.ZERO, Vector3(0,4,0), Vector3.ZERO, Vector3.ONE)
	else:
		head = _part("Head", Vector3(8,8,8), Vector2.ZERO, Vector3(0,18,0), Vector3(0,4,0), Vector3.ONE)
		_part("Torso", Vector3(8,12,4), Vector2(16,16), Vector3(0,18,0), Vector3(0,-6,0), Vector3.ONE)
		for x in [-2,2]:
			for z in [-3,3]:
				limbs.append(_part("Foot", Vector3(4,6,4), Vector2(0,16), Vector3(x,6,z), Vector3(0,-3,0), Vector3.ONE))

func animate(state: String, time: float, hurt: float) -> void:
	var moving := state in ["wander", "flee", "return", "chase"]
	if shape_kind == "slime":
		var bounce := absf(sin(time * 6.0)) if moving else 0.0
		body.position.y = bounce * 0.2
		body.scale = Vector3(1.0 - bounce * 0.1, 1.0 + bounce * 0.2, 1.0 - bounce * 0.1)
	else:
		for i in range(limbs.size()):
			limbs[i].rotation.x = sin(time * 8.0 + (PI if i in [1,2] else 0.0)) * 0.45 if moving else 0.0
	body.rotation.z = PI * 0.5 if state == "dead" else sin(time * 30.0) * 0.08 if hurt > 0 else 0.0
