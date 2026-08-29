extends CharacterBody3D

## Movement parameters
@export_group("Movement")
@export var speed: float = 6.0
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.002

## Voxel interaction parameters
@export_group("Voxel Settings")
@export var reach_distance: float = 8.0

## Character animation settings
@export_group("Character Animations")
@export var idle_animation: StringName = &"idle"
@export var walk_animation: StringName = &"walk"
@export var jump_animation: StringName = &"jump"
@export var break_animation: StringName = &"break"
@export var block_animation: StringName = &"block"
@export var walk_animation_speed: float = 1.0

## Debug settings
@export_group("Debug")
@export var enable_debug_logs: bool = true

## Safety settings
@export_group("Safety")
@export var enable_auto_unstuck: bool = true
@export var unstuck_check_interval: float = 0.25
@export var unstuck_max_search_height: int = 12

var gravity: float = float(
	ProjectSettings.get_setting("physics/3d/default_gravity")
)

var voxel_tool: VoxelTool = null

# Multiplayer sync settings
var sync_timer: float = 0.0
var sync_delay: float = 0.05
var spawn_grace_timer: float = 1.0
var unstuck_timer: float = 0.0

# Character animation state
var model_action_locked: bool = false
var last_grounded: bool = false

@onready var camera: Camera3D = $Camera3D
@onready var inventory: Inventory = $Inventory

@onready var hand_anim: AnimationPlayer = (
	get_node_or_null("Camera3D/Hand/AnimationPlayer") as AnimationPlayer
)

@onready var model_anim: AnimationPlayer = (
	get_node_or_null("AnimationPlayer") as AnimationPlayer
)


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	if model_anim != null:
		if not model_anim.animation_finished.is_connected(
			_on_model_animation_finished
		):
			model_anim.animation_finished.connect(
				_on_model_animation_finished
			)

	if not is_multiplayer_authority():
		if camera:
			camera.current = false

		var remote_voxel_viewer := get_node_or_null("VoxelViewer")

		if remote_voxel_viewer:
			remote_voxel_viewer.queue_free()

		return

	if camera:
		camera.current = true

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	last_grounded = is_on_floor()

	call_deferred("_initialize_voxel_tool")
	call_deferred("_update_model_animation")


func _initialize_voxel_tool() -> void:
	if Global.active_terrain != null:
		voxel_tool = Global.active_terrain.get_voxel_tool()

		_log(
			"Successfully acquired VoxelTool from "
			+ "Global.active_terrain."
		)
	else:
		_log_warning(
			"Global.active_terrain is NULL during initialization. "
			+ "Will attempt dynamic fetch on interaction."
		)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseButton:
		if (
			event.button_index == MOUSE_BUTTON_WHEEL_UP
			and event.pressed
		):
			inventory.set_selected_slot(
				inventory.selected_slot - 1
			)
			return

		if (
			event.button_index == MOUSE_BUTTON_WHEEL_DOWN
			and event.pressed
		):
			inventory.set_selected_slot(
				inventory.selected_slot + 1
			)
			return

		if (
			event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
		):
			if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				return

			interact_with_voxels(true)
			return

		if (
			event.button_index == MOUSE_BUTTON_RIGHT
			and event.pressed
		):
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				interact_with_voxels(false)

			return

	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			return

		rotate_y(-event.relative.x * mouse_sensitivity)

		if camera:
			camera.rotate_x(
				-event.relative.y * mouse_sensitivity
			)

			camera.rotation.x = clampf(
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
		velocity.x = move_toward(
			velocity.x,
			0.0,
			speed * delta * 8.0
		)

		velocity.z = move_toward(
			velocity.z,
			0.0,
			speed * delta * 8.0
		)

		move_and_slide()

		_update_model_animation()
		_auto_unstuck(delta)
		_send_movement_sync(delta)

		last_grounded = is_on_floor()
		return

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_vector := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	var direction := (
		transform.basis
		* Vector3(input_vector.x, 0.0, input_vector.y)
	).normalized()

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(
			velocity.x,
			0.0,
			speed * delta * 8.0
		)

		velocity.z = move_toward(
			velocity.z,
			0.0,
			speed * delta * 8.0
		)

	move_and_slide()

	_update_model_animation()
	_auto_unstuck(delta)
	_send_movement_sync(delta)

	last_grounded = is_on_floor()


func _update_model_animation() -> void:
	if model_anim == null:
		return

	if model_action_locked:
		return

	var horizontal_speed := Vector2(
		velocity.x,
		velocity.z
	).length()

	if not is_on_floor():
		_play_model_animation(jump_animation)
		return

	if horizontal_speed > 0.1:
		_play_model_animation(
			walk_animation,
			walk_animation_speed
		)
	else:
		_play_idle_animation()


func _play_idle_animation() -> void:
	if model_anim == null:
		return

	if model_anim.has_animation(idle_animation):
		_play_model_animation(idle_animation)
		return

	if model_anim.is_playing():
		model_anim.stop()

	model_anim.seek(0.0, true)


func _play_model_animation(
	animation_name: StringName,
	custom_speed: float = 1.0
) -> void:
	if model_anim == null:
		return

	if not model_anim.has_animation(animation_name):
		return

	if (
		model_anim.current_animation == animation_name
		and model_anim.is_playing()
	):
		model_anim.speed_scale = custom_speed
		return

	model_anim.speed_scale = custom_speed
	model_anim.play(animation_name)


func _play_model_action(animation_name: StringName) -> void:
	if model_anim == null:
		return

	if not model_anim.has_animation(animation_name):
		_log_warning(
			"Character animation '%s' does not exist."
			% String(animation_name)
		)
		return

	model_action_locked = true
	model_anim.speed_scale = 1.0
	model_anim.stop()
	model_anim.play(animation_name)


func _on_model_animation_finished(
	animation_name: StringName
) -> void:
	if (
		animation_name == break_animation
		or animation_name == block_animation
	):
		model_action_locked = false
		_update_model_animation()


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
			_log_warning(
				"Interaction failed: "
				+ "Global.active_terrain is NULL."
			)
			return

	if camera == null:
		_log_warning(
			"Interaction failed: Camera3D node not found."
		)
		return

	var origin := camera.global_position

	var forward := (
		-camera.global_transform.basis.z
	).normalized()

	var hit: VoxelRaycastResult = voxel_tool.raycast(
		origin,
		forward,
		reach_distance
	)

	if not hit:
		return

	play_hand_swing()

	voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE

	if is_destroying:
		_play_model_action(break_animation)

		var destroyed_block_id := voxel_tool.get_voxel(
			hit.position
		)

		if destroyed_block_id == Block.AIR:
			return

		if inventory.add_block(destroyed_block_id):
			send_voxel_change(
				hit.position,
				Block.AIR
			)

			_log(
				"Collected block ID: "
				+ str(destroyed_block_id)
			)
		else:
			_log("Inventory is full.")

		return

	_play_model_action(block_animation)

	var placed_block_id := inventory.get_selected_block()

	if placed_block_id == Block.AIR:
		return

	var place_position: Vector3i = hit.previous_position

	if not can_place_block(place_position):
		_log("Cannot place block inside player.")
		return

	send_voxel_change(
		place_position,
		placed_block_id
	)

	inventory.remove_selected_block()

	_log(
		"Placed block ID: "
		+ str(placed_block_id)
	)


func send_voxel_change(
	pos: Vector3i,
	block_id: int
) -> void:
	var game := get_tree().current_scene

	if game == null:
		_log_warning(
			"Cannot send voxel change. Current scene is null."
		)
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
		game.request_voxel_change.rpc_id(
			1,
			pos,
			block_id
		)


func can_place_block(block_pos: Vector3i) -> bool:
	var game := get_tree().current_scene

	if game == null:
		return can_place_block_against_player(
			block_pos,
			self
		)

	var players_node := game.get_node_or_null("Players")

	if players_node == null:
		return can_place_block_against_player(
			block_pos,
			self
		)

	for child in players_node.get_children():
		if child is CharacterBody3D:
			if not can_place_block_against_player(
				block_pos,
				child
			):
				return false

	return true


func can_place_block_against_player(
	block_pos: Vector3i,
	player: CharacterBody3D
) -> bool:
	var block_center := Vector3(
		float(block_pos.x) + 0.5,
		float(block_pos.y) + 0.5,
		float(block_pos.z) + 0.5
	)

	var player_feet := player.global_position

	var player_head := (
		player.global_position
		+ Vector3(0.0, 1.8, 0.0)
	)

	var horizontal_distance := Vector2(
		block_center.x - player.global_position.x,
		block_center.z - player.global_position.z
	).length()

	var overlaps_vertically := (
		block_center.y > player_feet.y - 0.2
		and block_center.y < player_head.y + 0.2
	)

	if (
		horizontal_distance < 0.85
		and overlaps_vertically
	):
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

	if not is_body_inside_solid(global_position):
		return

	_log_warning(
		"Player is inside a solid voxel. Attempting unstuck."
	)

	for height in range(
		1,
		unstuck_max_search_height + 1
	):
		var test_position := (
			global_position
			+ Vector3(0.0, float(height), 0.0)
		)

		if not is_body_inside_solid(test_position):
			global_position = test_position
			velocity = Vector3.ZERO

			_log(
				"Player unstuck to: "
				+ str(global_position)
			)

			return


func is_body_inside_solid(
	test_position: Vector3
) -> bool:
	if voxel_tool == null:
		return false

	var y_offsets: Array[float] = [
		0.2,
		0.9,
		1.6
	]

	var xz_offsets: Array[Vector2] = [
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

			var block_id := voxel_tool.get_voxel(
				voxel_pos
			)

			if block_id != Block.AIR:
				return true

	return false


func play_hand_swing() -> void:
	if hand_anim == null:
		return

	var animation_name: StringName = &"HandSwing"

	if not hand_anim.has_animation(animation_name):
		_log_warning(
			"Animation 'HandSwing' does not exist."
		)
		return

	if hand_anim.is_playing():
		hand_anim.stop()

	hand_anim.play(animation_name)


func _log(message: String) -> void:
	if enable_debug_logs:
		print(
			"[PlayerController] ",
			message
		)


func _log_warning(message: String) -> void:
	if enable_debug_logs:
		push_warning(
			"[PlayerController] "
			+ message
		)
