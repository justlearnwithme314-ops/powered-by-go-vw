extends CharacterBody3D

@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var camera: Camera3D = $Camera3D
@onready var block_ray: RayCast3D = $Camera3D/BlockRay
@onready var world: Node3D = get_tree().get_first_node_in_group("world")

func _ready() -> void:
	if not is_multiplayer_authority():
		camera.current = false
		set_process_unhandled_input(false)
		set_physics_process(false)
		return

	camera.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
@rpc("authority", "unreliable")
func sync_transform(new_transform: Transform3D) -> void:
	if is_multiplayer_authority():
		return
	global_transform = new_transform
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	if event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if event is InputEventMouseButton and event.pressed:

		if event.button_index == MOUSE_BUTTON_LEFT:
			try_break_block()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			try_place_block()
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()
	if is_multiplayer_authority():
		sync_transform.rpc(global_transform)
func try_break_block():

	if !block_ray.is_colliding():
		return

	var collider = block_ray.get_collider()

	if collider == null:
		return

	var pos := Vector3i(collider.global_position.round())

	world.break_block(pos)
	
	
func try_place_block():

	if !block_ray.is_colliding():
		return

	var hit := block_ray.get_collision_point()

	var normal := block_ray.get_collision_normal()

	var pos := Vector3i((hit + normal * 0.5).floor())

	world.place_block(pos)
