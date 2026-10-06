extends "../first_creatures/HumanoidVisual.gd"

var phase := 0.0
var socket: Node3D
var view_rig: Node3D
var state: StringName = &"idle"

func _ready() -> void:
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	setup({"skin": ImageTexture.create_from_image(image), "body_scale": Vector3.ONE * 0.95, "skin_layers": true})
	body.name = "Rig"
	socket = Node3D.new()
	socket.name = "RightHand"
	socket.position.y = -0.65
	limbs[0].add_child(socket)
	for label in ["HeldTool", "Pistol"]:
		var sprite := Sprite3D.new()
		sprite.name = label
		sprite.visible = false
		socket.add_child(sprite)
	add_to_group("minecraft_player_body")
	call_deferred("_bind_skin")

func _bind_skin() -> void:
	if not is_in_group("minecraft_player_body"):
		return
	var service := get_node_or_null("/root/SkinService")
	if service != null:
		service.bind_body(self)

func apply_skin(bytes: PackedByteArray) -> void:
	var image := Image.new()
	if image.load_png_from_buffer(bytes) == OK and image.get_size() == Vector2i(64,64):
		material.albedo_texture = ImageTexture.create_from_image(image)
		if view_rig != null:
			view_rig.material.albedo_texture = material.albedo_texture

func get_item_socket() -> Node3D:
	return socket

func get_animation_phase() -> float:
	return fposmod(phase / TAU, 1.0)

func update_visual(pose: Dictionary, height: float, speed: float, _airborne: bool) -> void:
	state = &"jump" if _airborne else &"walk" if speed > 0.15 else &"idle"
	if bool(pose.get("sitting",false)) or bool(pose.get("lying",false)) or bool(pose.get("rolling",false)):
		state = &"idle"
	phase = float(pose.animation_phase) * TAU if pose.has("animation_phase") else phase + get_process_delta_time() * maxf(2.0, speed * 1.8)
	for i in range(limbs.size()):
		limbs[i].rotation.x = sin(phase + (PI if i in [1,2] else 0.0)) * 0.55 if speed > 0.15 else 0.0
	head.rotation.x = float(pose.get("look_pitch",0))
	body.position.y = -(1.9 - height) * 0.7
	if bool(pose.get("sitting",false)):
		limbs[2].rotation.x = -PI * 0.5
		limbs[3].rotation.x = -PI * 0.5
	if bool(pose.get("crouching",false)):
		body.get_node("Torso").rotation.x = 0.25
	else:
		body.get_node("Torso").rotation.x = 0.0
	if bool(pose.get("holding_item",false)):
		limbs[0].rotation.x -= 0.35
	limbs[0].rotation.x -= float(pose.get("swing",0)) * 1.1

func create_first_person_rig(camera: Camera3D) -> Node3D:
	view_rig = get_script().new()
	camera.add_child(view_rig)
	view_rig.remove_from_group("minecraft_player_body")
	view_rig.position = Vector3(0.7,-1.45,-0.55)
	view_rig.material.albedo_texture = material.albedo_texture
	for child in view_rig.body.get_children():
		child.visible = child == view_rig.limbs[0]
	for mesh in view_rig.find_children("*","GeometryInstance3D",true,false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return view_rig

func update_first_person(swing: float, _holding: bool) -> void:
	limbs[0].rotation.x = -0.45 - swing * 0.9
