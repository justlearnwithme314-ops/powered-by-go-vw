extends Node3D

## Six cuboids with classic 64x32 / modern 64x64 Minecraft skin UVs.
## definition: skin (Texture2D), body_scale (Vector3), arm_width (3 or 4),
## head_scale, torso_scale, arm_scale, leg_scale (Vector3).
var limbs: Array[Node3D] = []
var head: Node3D
var body: Node3D
var material: StandardMaterial3D
var atlas_size := Vector2(64, 64)

func setup(definition: Dictionary) -> void:
	material = StandardMaterial3D.new()
	material.albedo_texture = definition.get("skin") as Texture2D
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if material.albedo_texture != null:
		# UV rectangles use logical skin pixels, even for enlarged HD atlases.
		var texture_size := material.albedo_texture.get_size()
		atlas_size = Vector2(64, 64 * texture_size.y / texture_size.x)
	scale = definition.get("body_scale", Vector3.ONE)
	body = Node3D.new()
	add_child(body)
	_part("Torso", Vector3(8, 12, 4), Vector2(16, 16), Vector3(0, 24, 0), Vector3(0, -6, 0), definition.get("torso_scale", Vector3.ONE))
	head = _part("Head", Vector3(8, 8, 8), Vector2.ZERO, Vector3(0, 24, 0), Vector3(0, 4, 0), definition.get("head_scale", Vector3.ONE))
	var skeleton := bool(definition.get("skeleton_layout", false))
	var width := 2 if skeleton else clampi(int(definition.get("arm_width", 4)), 3, 4)
	var arm_pixels := Vector3(width, 12, 2 if skeleton else 4)
	var leg_pixels := Vector3(2 if skeleton else 4, 12, 2 if skeleton else 4)
	var modern := atlas_size.y >= 64 and not bool(definition.get("classic_limbs", false))
	limbs.append(_part("RightArm", arm_pixels, Vector2(40, 16), Vector3(-4 - width * 0.5, 24, 0), Vector3(0, -6, 0), definition.get("arm_scale", Vector3.ONE)))
	limbs.append(_part("LeftArm", arm_pixels, Vector2(32, 48) if modern else Vector2(40, 16), Vector3(4 + width * 0.5, 24, 0), Vector3(0, -6, 0), definition.get("arm_scale", Vector3.ONE), not modern))
	limbs.append(_part("RightLeg", leg_pixels, Vector2(0, 16), Vector3(-2, 12, 0), Vector3(0, -6, 0), definition.get("leg_scale", Vector3.ONE)))
	limbs.append(_part("LeftLeg", leg_pixels, Vector2(16, 48) if modern else Vector2(0, 16), Vector3(2, 12, 0), Vector3(0, -6, 0), definition.get("leg_scale", Vector3.ONE), not modern))
	if modern and bool(definition.get("skin_layers", false)):
		_overlay(head, Vector3(8,8,8), Vector2(32,0), Vector3(0,4,0))
		_overlay(body.get_node("Torso"), Vector3(8,12,4), Vector2(16,32), Vector3(0,-6,0))
		_overlay(limbs[0], Vector3(width,12,4), Vector2(40,32), Vector3(0,-6,0))
		_overlay(limbs[1], Vector3(width,12,4), Vector2(48,48), Vector3(0,-6,0))
		_overlay(limbs[2], Vector3(4,12,4), Vector2(0,32), Vector3(0,-6,0))
		_overlay(limbs[3], Vector3(4,12,4), Vector2(0,48), Vector3(0,-6,0))

func _overlay(joint: Node3D, size: Vector3, uv: Vector2, offset: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _cube(size, uv, false)
	mesh.material_override = material
	mesh.position = offset / 16.0
	mesh.scale = (size + Vector3.ONE * 0.5) / size
	joint.add_child(mesh)

func _part(label: String, size: Vector3, uv: Vector2, pivot: Vector3, offset: Vector3, proportions: Vector3, mirror: bool = false) -> Node3D:
	var joint := Node3D.new()
	joint.name = label
	joint.position = pivot / 16.0
	body.add_child(joint)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _cube(size, uv, mirror)
	mesh.material_override = material
	mesh.position = offset / 16.0
	mesh.scale = proportions
	joint.add_child(mesh)
	return joint

func _cube(size: Vector3, origin: Vector2, mirror: bool) -> ArrayMesh:
	var s := size / 32.0
	var w := size.x
	var h := size.y
	var d := size.z
	# Face order: front (-Z), back (+Z), right (-X), left (+X), top, bottom.
	var faces := [
		[Vector3(s.x,s.y,-s.z),Vector3(-s.x,s.y,-s.z),Vector3(-s.x,-s.y,-s.z),Vector3(s.x,-s.y,-s.z)],
		[Vector3(-s.x,s.y,s.z),Vector3(s.x,s.y,s.z),Vector3(s.x,-s.y,s.z),Vector3(-s.x,-s.y,s.z)],
		[Vector3(-s.x,s.y,-s.z),Vector3(-s.x,s.y,s.z),Vector3(-s.x,-s.y,s.z),Vector3(-s.x,-s.y,-s.z)],
		[Vector3(s.x,s.y,s.z),Vector3(s.x,s.y,-s.z),Vector3(s.x,-s.y,-s.z),Vector3(s.x,-s.y,s.z)],
		[Vector3(-s.x,s.y,s.z),Vector3(-s.x,s.y,-s.z),Vector3(s.x,s.y,-s.z),Vector3(s.x,s.y,s.z)],
		[Vector3(-s.x,-s.y,-s.z),Vector3(-s.x,-s.y,s.z),Vector3(s.x,-s.y,s.z),Vector3(s.x,-s.y,-s.z)]]
	var rects := [Rect2(d,d,w,h),Rect2(2*d+w,d,w,h),Rect2(0,d,d,h),Rect2(d+w,d,d,h),Rect2(d,0,w,d),Rect2(d+w,0,w,d)]
	var normals := [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT,Vector3.UP,Vector3.DOWN]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in range(6):
		var rect: Rect2 = rects[face]
		var coords := [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
		for corner in [0,1,2,0,2,3]:
			var coord: Vector2 = coords[corner]
			if mirror:
				coord.x = 1.0 - coord.x
			surface.set_normal(normals[face])
			surface.set_uv((origin + rect.position + coord * rect.size) / atlas_size)
			surface.add_vertex(faces[face][corner])
	return surface.commit()

func animate(state: String, time: float, hurt: float) -> void:
	var moving := state in ["wander", "flee", "return", "chase"]
	for i in range(limbs.size()):
		limbs[i].rotation.x = sin(time * 8.0 + (PI if i in [1,2] else 0.0)) * 0.55 if moving else 0.0
	if state in ["windup", "attack"]:
		limbs[0].rotation.x = -1.6
	body.rotation.z = PI * 0.5 if state == "dead" else sin(time * 30.0) * 0.08 if hurt > 0 else 0.0
