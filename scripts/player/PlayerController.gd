extends CharacterBody3D

## Movement parameters
@export_group("Movement")
@export var speed: float = 6.0
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.002

## Voxel interaction parameters
@export_group("Voxel Settings")
@export var reach_distance: float = 8.0

## Debug settings
@export_group("Debug")
@export var enable_debug_logs: bool = true

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var voxel_tool: VoxelTool = null

@onready var camera: Camera3D = $Camera3D
@onready var inventory: Inventory = $Inventory


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	call_deferred("_initialize_voxel_tool")


func _initialize_voxel_tool() -> void:
	if Global.active_terrain != null:
		voxel_tool = Global.active_terrain.get_voxel_tool()
		_log("Successfully acquired VoxelTool from Global.active_terrain.")
	else:
		_log_warning("Global.active_terrain is NULL during _ready(). Will attempt dynamic fetch on interaction.")


func _unhandled_input(event: InputEvent) -> void:

	if event is InputEventMouseButton:

		# Scroll hotbar
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			inventory.selected_slot = wrapi(inventory.selected_slot - 1, 0, 4)
			return

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			inventory.selected_slot = wrapi(inventory.selected_slot + 1, 0, 4)
			return

		# Break block
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				return
			else:
				interact_with_voxels(true)

		# Place block
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				interact_with_voxels(false)

	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			return

		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
		move_and_slide()
		return

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()


func interact_with_voxels(is_destroying: bool) -> void:

	if voxel_tool == null:
		if Global.active_terrain != null:
			voxel_tool = Global.active_terrain.get_voxel_tool()
		else:
			_log_warning("Interaction failed: Global.active_terrain is NULL!")
			return

	if camera == null:
		_log_warning("Interaction failed: Camera3D node not found.")
		return

	var origin: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_transform.basis.z.normalized()

	var hit: VoxelRaycastResult = voxel_tool.raycast(origin, forward, reach_distance)

	if !hit:
		return

	voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE

	if is_destroying:

		var block_id := voxel_tool.get_voxel(hit.position)

		if block_id != 0:

			if inventory.add_block(block_id):

				voxel_tool.set_voxel(hit.position, 0)

				_log("Collected block ID: " + str(block_id))
			else:
				_log("Inventory is full.")

	else:

		var block_id := inventory.get_selected_block()

		if block_id != 0:

			voxel_tool.set_voxel(hit.previous_position, block_id)
			inventory.remove_selected_block()

			_log("Placed block ID: " + str(block_id))


func _log(message: String) -> void:
	if enable_debug_logs:
		print("[PlayerController] ", message)


func _log_warning(message: String) -> void:
	if enable_debug_logs:
		push_warning("[PlayerController] ", message)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
