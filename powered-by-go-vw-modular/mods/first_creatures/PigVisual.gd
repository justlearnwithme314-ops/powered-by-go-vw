extends Node3D

## Original cuboid pig, using colored materials rather than third-party textures.
var legs: Array[Node3D] = []
var body: Node3D
var head: Node3D

func setup(_definition: Dictionary) -> void:
	body = Node3D.new()
	add_child(body)
	_box(body, Vector3(0.7, 0.5, 1.05), Vector3(0, 0.6, 0), Color("dc929e"))
	head = Node3D.new()
	head.position = Vector3(0, 0.66, -0.64)
	body.add_child(head)
	_box(head, Vector3(0.52, 0.45, 0.4), Vector3.ZERO, Color("e8a6af"))
	_box(head, Vector3(0.3, 0.18, 0.13), Vector3(0, -0.04, -0.25), Color("d68194"))
	for x in [-1, 1]:
		_box(head, Vector3(0.06, 0.08, 0.025), Vector3(x * 0.19, 0.1, -0.21), Color("202125"))
		_box(head, Vector3(0.035, 0.045, 0.025), Vector3(x * 0.07, -0.04, -0.325), Color("9c5168"))
		_box(head, Vector3(0.13, 0.18, 0.12), Vector3(x * 0.2, 0.28, 0), Color("d68194"))
		for z in [-1, 1]:
			var leg := Node3D.new()
			leg.position = Vector3(x * 0.24, 0.4, z * 0.35)
			body.add_child(leg)
			_box(leg, Vector3(0.18, 0.28, 0.18), Vector3(0, -0.14, 0), Color("d68c9a"))
			_box(leg, Vector3(0.18, 0.09, 0.18), Vector3(0, -0.32, 0), Color("71515c"))
			legs.append(leg)
	_box(body, Vector3(0.09, 0.09, 0.18), Vector3(0, 0.7, 0.6), Color("d68194"))

func _box(parent: Node3D, size: Vector3, position: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	mesh.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1
	mesh.material_override = material
	parent.add_child(mesh)

func animate(state: String, time: float, hurt: float) -> void:
	var moving := state in ["wander", "flee", "return"]
	var phase := time * (14 if state == "flee" else 8)
	for i in range(legs.size()):
		legs[i].rotation.x = sin(phase + (PI if i in [1, 2] else 0)) * 0.45 if moving else 0
	body.rotation.z = lerp_angle(body.rotation.z, PI * 0.5 if state == "dead" else 0.08 * sin(time * 30) if hurt > 0 else 0, 0.2)
	body.position.y = -0.3 if state == "dead" else 0
	head.rotation.y = sin(time * 0.7) * 0.1
