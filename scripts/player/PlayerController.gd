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

## Safety settings
@export_group("Safety")
@export var enable_auto_unstuck: bool = true
@export var unstuck_check_interval: float = 0.25
@export var unstuck_max_search_height: int = 12

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var voxel_tool: VoxelTool = null

# Multiplayer sync settings
var sync_timer: float = 0.0
var sync_delay: float = 0.05
var spawn_grace_timer: float = 1.0
var unstuck_timer: float = 0.0

@onready var camera: Camera3D = $Camera3D
@onready var inventory: Inventory = $Inventory

# Hand animation
@onready var hand_anim: AnimationPlayer = $Camera3D/Hand/AnimationPlayer


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	if not is_multiplayer_authority():
		if camera:
			camera.current = false

		var voxel_viewer = get_node_or_null("VoxelViewer")
		if voxel_viewer:
			voxel_viewer.queue_free()

		return

	if camera:
		camera.current = true

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	call_deferred("_initialize_voxel_tool")


func _initialize_voxel_tool() -> void:
	if Global.active_terrain != null:
		voxel_tool = Global.active_terrain.get_voxel_tool()
		_log("Successfully acquired VoxelTool from Global.active_terrain.")
	else:
		_log_warning("Global.active_terrain is NULL during _ready(). Will attempt dynamic fetch on interaction.")


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseButton:

		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			inventory.set_selected_slot(inventory.selected_slot - 1)
			return

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			inventory.set_selected_slot(inventory.selected_slot + 1)
			return

		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				return

			interact_with_voxels(true)

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				interact_with_voxels(false)

	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			return

		rotate_y(-event.relative.x * mouse_sensitivity)

		if camera:
			camera.rotate_x(-event.relative.y * mouse_sensitivity)
			camera.rotation.x = clamp(
				camera.rotation.x,
				deg_to_rad(-89.0),
				deg_to_rad(89.0)
			)

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if spawn_grace_timer > 0.0:
		spawn_grace_timer -= delta

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

		move_and_slide()
		_auto_unstuck(delta)
		_send_movement_sync(delta)
		return

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	var direction: Vector3 = (
		transform.basis * Vector3(input.x, 0.0, input.y)
	).normalized()

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()
	_auto_unstuck(delta)
	_send_movement_sync(delta)


func _send_movement_sync(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	if spawn_grace_timer > 0.0:
		return

	if camera == null:
		return

	sync_timer += delta

	if sync_timer < sync_delay:
		return

	sync_timer = 0.0

	var game := get_tree().current_scene

	if game == null:
		return

	var my_id := multiplayer.get_unique_id()

	if multiplayer.is_server():
		game.request_player_sync(
			my_id,
			global_position,
			rotation.y,
			camera.rotation.x
		)
	else:
		game.request_player_sync.rpc_id(
			1,
			my_id,
			global_position,
			rotation.y,
			camera.rotation.x
		)


func interact_with_voxels(is_destroying: bool) -> void:
	if not is_multiplayer_authority():
		return

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

	var hit: VoxelRaycastResult = voxel_tool.raycast(
		origin,
		forward,
		reach_distance
	)

	if !hit:
		return

	play_hand_swing()

	voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE

	if is_destroying:
		var block_id := voxel_tool.get_voxel(hit.position)

		if block_id != Block.AIR:
			if inventory.add_block(block_id):
				send_voxel_change(hit.position, Block.AIR)
				_log("Collected block ID: " + str(block_id))
			else:
				_log("Inventory is full.")

	else:
		var block_id := inventory.get_selected_block()

		if block_id != Block.AIR:
			var place_position: Vector3i = hit.previous_position

			if can_place_block(place_position):
				send_voxel_change(place_position, block_id)
				inventory.remove_selected_block()
				_log("Placed block ID: " + str(block_id))
			else:
				_log("Cannot place block inside player.")


func send_voxel_change(pos: Vector3i, block_id: int) -> void:
	var game := get_tree().current_scene

	if game == null:
		_log_warning("Cannot send voxel change. Current scene is null.")
		return

	if not multiplayer.has_multiplayer_peer():
		if Global.active_terrain != null:
			var tool := Global.active_terrain.get_voxel_tool()
			tool.channel = VoxelBuffer.CHANNEL_TYPE
			tool.set_voxel(pos, block_id)
		return

	if multiplayer.is_server():
		game.request_voxel_change(pos, block_id)
	else:
		game.request_voxel_change.rpc_id(1, pos, block_id)


func can_place_block(block_pos: Vector3i) -> bool:
	var game := get_tree().current_scene

	if game == null:
		return can_place_block_against_player(block_pos, self)

	var players_node := game.get_node_or_null("Players")

	if players_node == null:
		return can_place_block_against_player(block_pos, self)

	for child in players_node.get_children():
		if child is CharacterBody3D:
			if can_place_block_against_player(block_pos, child) == false:
				return false

	return true


func can_place_block_against_player(block_pos: Vector3i, player: CharacterBody3D) -> bool:
	var block_center := Vector3(
		float(block_pos.x) + 0.5,
		float(block_pos.y) + 0.5,
		float(block_pos.z) + 0.5
	)

	var player_feet := player.global_position
	var player_head := player.global_position + Vector3(0.0, 1.8, 0.0)

	var horizontal_distance := Vector2(
		block_center.x - player.global_position.x,
		block_center.z - player.global_position.z
	).length()

	var overlaps_vertically := (
		block_center.y > player_feet.y - 0.2
		and block_center.y < player_head.y + 0.2
	)

	if horizontal_distance < 0.85 and overlaps_vertically:
		return false

	return true


func _auto_unstuck(delta: float) -> void:
	if not enable_auto_unstuck:
		return

	if not is_multiplayer_authority():
		return

	unstuck_timer += delta

	if unstuck_timer < unstuck_check_interval:
		return

	unstuck_timer = 0.0

	if voxel_tool == null:
		if Global.active_terrain != null:
			voxel_tool = Global.active_terrain.get_voxel_tool()
		else:
			return

	voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE

	if is_body_inside_solid(global_position):
		_log_warning("Player is inside solid voxel. Attempting unstuck.")

		for i in range(1, unstuck_max_search_height + 1):
			var test_position := global_position + Vector3(0.0, float(i), 0.0)

			if is_body_inside_solid(test_position) == false:
				global_position = test_position
				velocity = Vector3.ZERO
				_log("Player unstuck to: " + str(global_position))
				return


func is_body_inside_solid(test_position: Vector3) -> bool:
	if voxel_tool == null:
		return false

	var y_offsets := [
		0.2,
		0.9,
		1.6
	]

	var xz_offsets := [
		Vector2(0.0, 0.0),
		Vector2(0.35, 0.35),
		Vector2(-0.35, 0.35),
		Vector2(0.35, -0.35),
		Vector2(-0.35, -0.35)
	]

	for y_offset in y_offsets:
		for xz_offset in xz_offsets:
			var sample_position := Vector3(
				test_position.x + xz_offset.x,
				test_position.y + y_offset,
				test_position.z + xz_offset.y
			)

			var voxel_pos := Vector3i(
				floori(sample_position.x),
				floori(sample_position.y),
				floori(sample_position.z)
			)

			var block_id := voxel_tool.get_voxel(voxel_pos)

			if block_id != Block.AIR:
				return true

	return false


func play_hand_swing() -> void:
	if hand_anim == null:
		_log_warning("Hand AnimationPlayer not found.")
		return

	if hand_anim.has_animation("HandSwing") == false:
		_log_warning("Animation 'HandSwing' does not exist.")
		return

	if hand_anim.is_playing():
		hand_anim.stop()

	hand_anim.play("HandSwing")


func _log(message: String) -> void:
	if enable_debug_logs:
		print("[PlayerController] ", message)


func _log_warning(message: String) -> void:
	if enable_debug_logs:
		push_warning("[PlayerController] " + message)
