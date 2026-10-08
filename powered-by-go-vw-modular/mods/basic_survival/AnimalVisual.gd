extends "../first_creatures/HumanoidVisual.gd"

## Dimensions/UV origins follow Mojang's bedrock-samples entity models.
var kind := "pig"
var rest_rotations: Array[Vector3] = []
var wings: Array[Node3D] = []
var legs: Array[Node3D]:
	get: return limbs

func setup(definition: Dictionary) -> void:
	material = StandardMaterial3D.new()
	material.albedo_texture = definition.skin as Texture2D
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var image_size := material.albedo_texture.get_size()
	atlas_size = Vector2(64,64 * image_size.y / image_size.x)
	body = Node3D.new()
	add_child(body)
	kind = str(definition.get("animal_kind","pig"))
	match kind:
		"spider": _spider()
		"chicken": _chicken()
		_: _quadruped()
	for limb in limbs: rest_rotations.append(limb.rotation)

func part(label: String, size: Vector3, uv: Vector2, center: Vector3) -> Node3D:
	return _part(label,size,uv,center,Vector3.ZERO,Vector3.ONE)

func _quadruped() -> void:
	var cow := kind == "cow"
	var sheep := kind == "sheep"
	var height := 12.0 if cow or sheep else 6.0
	var torso_size := Vector3(12,18,10) if cow else Vector3(8,16,6) if sheep else Vector3(10,16,8)
	var torso_uv := Vector2(18,4) if cow else Vector2(28,8)
	var torso := part("Torso",torso_size,torso_uv,Vector3(0,17 if cow else 15 if sheep else 10,1 if cow else 2))
	torso.rotation.x = PI * 0.5
	var head_size := Vector3(8,8,6) if cow else Vector3(6,6,8) if sheep else Vector3(8,8,8)
	var head_center := Vector3(0,20,-11) if cow else Vector3(0,19,-10) if sheep else Vector3(0,12,-10)
	head = part("Head",head_size,Vector2.ZERO,head_center)
	var spread := 4.0 if cow else 3.0
	for x in [-spread,spread]:
		for z in [7.0,-5.0 if not cow else -6.0]:
			limbs.append(_part("Leg",Vector3(4,height,4),Vector2(0,16),Vector3(x,height,z),Vector3(0,-height/2,0),Vector3.ONE,x>0))
	if cow:
		part("LeftHorn",Vector3(1,3,1),Vector2(22,0),Vector3(-4.5,23.5,-11.5))
		part("RightHorn",Vector3(1,3,1),Vector2(22,0),Vector3(4.5,23.5,-11.5))
		var udder := part("Udder",Vector3(4,6,1),Vector2(52,0),Vector3(0,11.5,7))
		udder.rotation.x = PI * 0.5
	elif not sheep:
		part("Snout",Vector3(4,3,1),Vector2(16,16),Vector3(0,10.5,-14.5))
	if sheep:
		var fleece := material.duplicate() as StandardMaterial3D
		fleece.albedo_texture = load("res://assets/minecraft-inspired-textures-free/entity/sheep/sheep_fur.png")
		var old_atlas := atlas_size
		var fleece_size := fleece.albedo_texture.get_size()
		atlas_size = Vector2(64,64*fleece_size.y/fleece_size.x)
		_wool(torso,torso_size,Vector2(28,8),Vector3.ZERO,1.75,fleece)
		_wool(head,Vector3(6,6,6),Vector2.ZERO,Vector3(0,0,1),0.6,fleece)
		for limb in limbs: _wool(limb,Vector3(4,6,4),Vector2(0,16),Vector3(0,-3,0),0.5,fleece)
		atlas_size = old_atlas

func _wool(joint: Node3D, size: Vector3, uv: Vector2, center: Vector3, inflate: float, fleece: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _cube(size,uv,false)
	mesh.scale = (size + Vector3.ONE * inflate * 2) / size
	mesh.position = center / 16
	mesh.material_override = fleece
	joint.add_child(mesh)

func _chicken() -> void:
	var torso := part("Torso",Vector3(6,8,6),Vector2(0,9),Vector3(0,8,0))
	torso.rotation.x = PI * 0.5
	head = part("Head",Vector3(4,6,3),Vector2.ZERO,Vector3(0,12,-4.5))
	part("Beak",Vector3(4,2,2),Vector2(14,0),Vector3(0,12,-7))
	part("Wattle",Vector3(2,2,2),Vector2(14,4),Vector3(0,10,-6))
	for x in [-1.5,1.5]:
		limbs.append(_part("Leg",Vector3(3,5,3),Vector2(26,0),Vector3(x,5,-0.5),Vector3(0,-2.5,0),Vector3.ONE))
	for x in [-3.5,3.5]: wings.append(part("Wing",Vector3(1,4,6),Vector2(24,13),Vector3(x,9,0)))

func _spider() -> void:
	part("Thorax",Vector3(6,6,6),Vector2.ZERO,Vector3(0,9,0))
	part("Abdomen",Vector3(10,8,12),Vector2(0,12),Vector3(0,9,9))
	head = part("Head",Vector3(8,8,8),Vector2(32,4),Vector3(0,9,-7))
	for side in [-1,1]:
		for i in range(4):
			var leg := _part("Leg",Vector3(16,2,2),Vector2(18,0),Vector3(side*4,9,2-i),Vector3(side*7,0,0),Vector3.ONE,side>0)
			leg.rotation = Vector3(0,side*[-0.65,-0.3,0.3,0.65][i],-side*0.55)
			limbs.append(leg)

func animate(state: String, time: float, hurt: float) -> void:
	var moving := state in ["wander","chase","flee","return"]
	for i in range(limbs.size()):
		limbs[i].rotation = rest_rotations[i]
		var swing := sin(time*8+(PI if i%2 else 0))*0.45 if moving else 0.0
		if kind == "spider": limbs[i].rotation.y += swing*0.35
		else: limbs[i].rotation.x += swing
	for i in range(wings.size()): wings[i].rotation.z = sin(time*12)*0.3*(1 if i==0 else -1) if moving else 0
	body.rotation.z = PI*0.5 if state == "dead" else sin(time*30)*0.08 if hurt > 0 else 0
