extends CharacterBody3D


# ============================================================
# MOVEMENT PARAMETERS
# ============================================================

@export_group("Movement")

@export var speed: float = 6.0
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.002


# ============================================================
# VOXEL INTERACTION PARAMETERS
# ============================================================

@export_group("Voxel Settings")

@export var reach_distance: float = 8.0


# ============================================================
# BLOCK BREAKING
# ============================================================

@export_group("Block Breaking")

# Normal breaking requires 3 hits.
@export var normal_break_hits: int = 3

# Stick requires only 2 hits.
@export var stick_break_hits: int = 2


# ============================================================
# ITEM IDs
# ============================================================

# For the MVP, every item/tool ID starts at 1000.
#
# Blocks:
#   Block.GRASS
#   Block.DIRT
#   Block.STONE
#   etc.
#
# Items:
#   1000 = Stick
#   1001 = future item
#   1002 = future tool
#
const FIRST_ITEM_ID: int = 1000
const STICK_ID: int = 1000


# ============================================================
# CHARACTER ANIMATION SETTINGS
# ============================================================

@export_group("Character Animations")

@export var idle_animation: StringName = &"idle"
@export var walk_animation: StringName = &"walk"
@export var jump_animation: StringName = &"jump"
@export var break_animation: StringName = &"break"
@export var block_animation: StringName = &"block"
@export var walk_animation_speed: float = 1.0


# ============================================================
# DEBUG SETTINGS
# ============================================================

@export_group("Debug")

@export var enable_debug_logs: bool = true


# ============================================================
# SAFETY SETTINGS
# ============================================================

@export_group("Safety")

@export var enable_auto_unstuck: bool = true
@export var unstuck_check_interval: float = 0.25
@export var unstuck_max_search_height: int = 12


# ============================================================
# PHYSICS
# ============================================================

var gravity: float = float(
	ProjectSettings.get_setting(
		"physics/3d/default_gravity"
	)
)


# ============================================================
# VOXEL
# ============================================================

var voxel_tool: VoxelTool = null


# ============================================================
# MULTIPLAYER SYNC
# ============================================================

var sync_timer: float = 0.0
var sync_delay: float = 0.05

var spawn_grace_timer: float = 1.0

var unstuck_timer: float = 0.0


# ============================================================
# CHARACTER ANIMATION STATE
# ============================================================

var model_action_locked: bool = false
var last_grounded: bool = false


# ============================================================
# BLOCK BREAKING STATE
# ============================================================
#
# We remember:
#
# Which block is being hit?
# How many times has it been hit?
# Which item/tool is being used?
#
# Example:
#
# hit block at (10,5,4)
# hit #1
#
# hit same block
# hit #2
#
# hit same block
# hit #3
# -> block breaks
#
# If the player looks at another block:
#
# counter resets.
#
# ============================================================

var breaking_active: bool = false

var breaking_position: Vector3i = Vector3i.ZERO

var breaking_hits: int = 0

var breaking_item_id: int = Inventory.EMPTY_ITEM_ID


# ============================================================
# NODES
# ============================================================

@onready var camera: Camera3D = $Camera3D

@onready var inventory: Inventory = $Inventory


@onready var hand_anim: AnimationPlayer = (
	get_node_or_null(
		"Camera3D/Hand/AnimationPlayer"
	) as AnimationPlayer
)


@onready var model_anim: AnimationPlayer = (
	get_node_or_null(
		"AnimationPlayer"
	) as AnimationPlayer
)


# ============================================================
# MULTIPLAYER AUTHORITY
# ============================================================

func _enter_tree() -> void:

	set_multiplayer_authority(
		name.to_int()
	)


# ============================================================
# READY
# ============================================================

func _ready() -> void:

	# --------------------------------------------------------
	# MODEL ANIMATION SIGNAL
	# --------------------------------------------------------

	if model_anim != null:

		if not model_anim.animation_finished.is_connected(
			_on_model_animation_finished
		):

			model_anim.animation_finished.connect(
				_on_model_animation_finished
			)


	# --------------------------------------------------------
	# REMOTE PLAYER
	# --------------------------------------------------------

	if not is_multiplayer_authority():

		if camera:
			camera.current = false


		var remote_voxel_viewer: Node = (
			get_node_or_null("VoxelViewer")
		)


		if remote_voxel_viewer:

			remote_voxel_viewer.queue_free()


		return


	# --------------------------------------------------------
	# LOCAL PLAYER
	# --------------------------------------------------------

	if camera:
		camera.current = true


	Input.set_mouse_mode(
		Input.MOUSE_MODE_CAPTURED
	)


	last_grounded = is_on_floor()


	call_deferred(
		"_initialize_voxel_tool"
	)


	call_deferred(
		"_update_model_animation"
	)


# ============================================================
# INITIALIZE VOXEL TOOL
# ============================================================

func _initialize_voxel_tool() -> void:

	if Global.active_terrain != null:

		voxel_tool = (
			Global.active_terrain.get_voxel_tool()
		)


		_log(
			"Successfully acquired VoxelTool from "
			+ "Global.active_terrain."
		)

	else:

		_log_warning(
			"Global.active_terrain is NULL during initialization. "
			+ "Will attempt dynamic fetch on interaction."
		)


# ============================================================
# INPUT
# ============================================================

func _unhandled_input(event: InputEvent) -> void:

	if not is_multiplayer_authority():
		return


	# ========================================================
	# MOUSE BUTTONS
	# ========================================================

	if event is InputEventMouseButton:


		# ----------------------------------------------------
		# MOUSE WHEEL UP
		# ----------------------------------------------------

		if (
			event.button_index == MOUSE_BUTTON_WHEEL_UP
			and event.pressed
		):

			inventory.set_selected_slot(
				inventory.selected_slot - 1
			)

			# Changing hotbar selection cancels breaking.
			_reset_breaking()

			return


		# ----------------------------------------------------
		# MOUSE WHEEL DOWN
		# ----------------------------------------------------

		if (
			event.button_index == MOUSE_BUTTON_WHEEL_DOWN
			and event.pressed
		):

			inventory.set_selected_slot(
				inventory.selected_slot + 1
			)

			# Changing hotbar selection cancels breaking.
			_reset_breaking()

			return


		# ----------------------------------------------------
		# LEFT CLICK = DESTROY / USE TOOL
		# ----------------------------------------------------

		if (
			event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
		):

			if (
				Input.get_mouse_mode()
				!= Input.MOUSE_MODE_CAPTURED
			):

				Input.set_mouse_mode(
					Input.MOUSE_MODE_CAPTURED
				)

				return


			interact_with_voxels(true)

			return


		# ----------------------------------------------------
		# RIGHT CLICK = PLACE BLOCK
		# ----------------------------------------------------

		if (
			event.button_index == MOUSE_BUTTON_RIGHT
			and event.pressed
		):

			if (
				Input.get_mouse_mode()
				== Input.MOUSE_MODE_CAPTURED
			):

				interact_with_voxels(false)

			return


	# ========================================================
	# MOUSE LOOK
	# ========================================================

	if event is InputEventMouseMotion:

		if (
			Input.get_mouse_mode()
			!= Input.MOUSE_MODE_CAPTURED
		):

			return


		rotate_y(
			-event.relative.x
			* mouse_sensitivity
		)


		if camera:

			camera.rotate_x(
				-event.relative.y
				* mouse_sensitivity
			)


			camera.rotation.x = clampf(
				camera.rotation.x,
				deg_to_rad(-89.0),
				deg_to_rad(89.0)
			)


	# ========================================================
	# ESC
	# ========================================================

	if event.is_action_pressed(
		"ui_cancel"
	):

		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE
		)


# ============================================================
# PHYSICS
# ============================================================

func _physics_process(delta: float) -> void:

	if not is_multiplayer_authority():
		return


	# --------------------------------------------------------
	# SPAWN GRACE
	# --------------------------------------------------------

	if spawn_grace_timer > 0.0:

		spawn_grace_timer -= delta


	# --------------------------------------------------------
	# GRAVITY
	# --------------------------------------------------------

	if not is_on_floor():

		velocity.y -= gravity * delta


	# ========================================================
	# MOUSE NOT CAPTURED
	# ========================================================

	if (
		Input.get_mouse_mode()
		!= Input.MOUSE_MODE_CAPTURED
	):

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


	# ========================================================
	# JUMP
	# ========================================================

	if (
		Input.is_action_just_pressed("jump")
		and is_on_floor()
	):

		velocity.y = jump_velocity


	# ========================================================
	# MOVEMENT
	# ========================================================

	var input_vector: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)


	var direction: Vector3 = (
		transform.basis
		* Vector3(
			input_vector.x,
			0.0,
			input_vector.y
		)
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


# ============================================================
# MODEL ANIMATION
# ============================================================

func _update_model_animation() -> void:

	if model_anim == null:
		return


	if model_action_locked:
		return


	var horizontal_speed: float = Vector2(
		velocity.x,
		velocity.z
	).length()


	if not is_on_floor():

		_play_model_animation(
			jump_animation
		)

		return


	if horizontal_speed > 0.1:

		_play_model_animation(
			walk_animation,
			walk_animation_speed
		)

	else:

		_play_idle_animation()


# ============================================================
# IDLE ANIMATION
# ============================================================

func _play_idle_animation() -> void:

	if model_anim == null:
		return


	if model_anim.has_animation(
		idle_animation
	):

		_play_model_animation(
			idle_animation
		)

		return


	if model_anim.is_playing():

		model_anim.stop()


	model_anim.seek(
		0.0,
		true
	)


# ============================================================
# PLAY ANIMATION
# ============================================================

func _play_model_animation(
	animation_name: StringName,
	custom_speed: float = 1.0
) -> void:

	if model_anim == null:
		return


	if not model_anim.has_animation(
		animation_name
	):

		return


	if (
		model_anim.current_animation
		== animation_name
		and model_anim.is_playing()
	):

		model_anim.speed_scale = custom_speed

		return


	model_anim.speed_scale = custom_speed

	model_anim.play(
		animation_name
	)


# ============================================================
# PLAY ACTION ANIMATION
# ============================================================

func _play_model_action(
	animation_name: StringName
) -> void:

	if model_anim == null:
		return


	if not model_anim.has_animation(
		animation_name
	):

		_log_warning(
			"Character animation '%s' does not exist."
			% String(animation_name)
		)

		return


	model_action_locked = true

	model_anim.speed_scale = 1.0

	model_anim.stop()

	model_anim.play(
		animation_name
	)


# ============================================================
# ANIMATION FINISHED
# ============================================================

func _on_model_animation_finished(
	animation_name: StringName
) -> void:

	if (
		animation_name == break_animation
		or animation_name == block_animation
	):

		model_action_locked = false

		_update_model_animation()


# ============================================================
# MOVEMENT SYNC
# ============================================================

func _send_movement_sync(
	delta: float
) -> void:

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


	var game: Node = (
		get_tree().current_scene
	)


	if game == null:
		return


	var my_id: int = (
		multiplayer.get_unique_id()
	)


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


# ============================================================
# VOXEL INTERACTION
# ============================================================

func interact_with_voxels(
	is_destroying: bool
) -> void:

	if not is_multiplayer_authority():
		return


	# ========================================================
	# GET VOXEL TOOL
	# ========================================================

	if voxel_tool == null:

		if Global.active_terrain != null:

			voxel_tool = (
				Global.active_terrain.get_voxel_tool()
			)

		else:

			_log_warning(
				"Interaction failed: "
				+ "Global.active_terrain is NULL."
			)

			return


	# ========================================================
	# CHECK CAMERA
	# ========================================================

	if camera == null:

		_log_warning(
			"Interaction failed: "
			+ "Camera3D node not found."
		)

		return


	# ========================================================
	# RAYCAST
	# ========================================================

	var origin: Vector3 = (
		camera.global_position
	)


	var forward: Vector3 = (
		-camera.global_transform.basis.z
	).normalized()


	var hit: VoxelRaycastResult = voxel_tool.raycast(
		origin,
		forward,
		reach_distance
	)


	if not hit:
		return


	voxel_tool.channel = (
		VoxelBuffer.CHANNEL_TYPE
	)


	# ========================================================
	# DESTROY / USE TOOL
	# ========================================================

	if is_destroying:

		_handle_block_breaking(
			hit
		)

		return


	# ========================================================
	# PLACE BLOCK
	# ========================================================

	_handle_block_placement(
		hit
	)


# ============================================================
# BLOCK BREAKING
# ============================================================

func _handle_block_breaking(
	hit: VoxelRaycastResult
) -> void:

	# --------------------------------------------------------
	# GET CURRENT BLOCK
	# --------------------------------------------------------

	var destroyed_block_id: int = (
		voxel_tool.get_voxel(
			hit.position
		)
	)


	if destroyed_block_id == Block.AIR:

		_reset_breaking()

		return


	# --------------------------------------------------------
	# GET CURRENT HOTBAR ITEM
	# --------------------------------------------------------
	#
	# This can be:
	#
	# Block.LOG
	# Block.STONE
	# -1
	# 1000 = Stick
	#
	# --------------------------------------------------------

	var selected_item_id: int = (
		inventory.get_selected_item_id()
	)


	# --------------------------------------------------------
	# DETERMINE REQUIRED HITS
	# --------------------------------------------------------

	var required_hits: int = (
		_get_required_break_hits(
			selected_item_id
		)
	)


	# --------------------------------------------------------
	# NEW TARGET?
	# --------------------------------------------------------
	#
	# If the player moves the crosshair to another block,
	# start from zero again.
	#
	# --------------------------------------------------------

	if (
		not breaking_active
		or breaking_position != hit.position
		or breaking_item_id != selected_item_id
	):

		breaking_active = true

		breaking_position = hit.position

		breaking_hits = 0

		breaking_item_id = selected_item_id


	# --------------------------------------------------------
	# ONE HIT
	# --------------------------------------------------------

	breaking_hits += 1


	# Hand animation on every hit.
	play_hand_swing()


	# Character breaking animation on every hit.
	_play_model_action(
		break_animation
	)


	_log(
		"Breaking block ID "
		+ str(destroyed_block_id)
		+ ": hit "
		+ str(breaking_hits)
		+ "/"
		+ str(required_hits)
		+ " using item ID "
		+ str(selected_item_id)
	)


	# --------------------------------------------------------
	# BLOCK NOT BROKEN YET
	# --------------------------------------------------------

	if breaking_hits < required_hits:

		return


	# ========================================================
	# BLOCK BREAKS
	# ========================================================

	if inventory.add_block(
		destroyed_block_id
	):

		send_voxel_change(
			hit.position,
			Block.AIR
		)


		_log(
			"Block broken. Collected block ID: "
			+ str(destroyed_block_id)
		)


	else:

		_log(
			"Could not add broken block to inventory."
		)


	# --------------------------------------------------------
	# RESET BREAKING
	# --------------------------------------------------------

	_reset_breaking()


# ============================================================
# REQUIRED BREAK HITS
# ============================================================

func _get_required_break_hits(
	item_id: int
) -> int:

	# --------------------------------------------------------
	# STICK
	# --------------------------------------------------------

	if item_id == STICK_ID:

		return max(
			stick_break_hits,
			1
		)


	# --------------------------------------------------------
	# EVERYTHING ELSE
	# --------------------------------------------------------
	#
	# This includes:
	#
	# - empty hand
	# - blocks
	# - future non-tool items
	#
	# --------------------------------------------------------

	return max(
		normal_break_hits,
		1
	)


# ============================================================
# RESET BREAKING
# ============================================================

func _reset_breaking() -> void:

	breaking_active = false

	breaking_hits = 0

	breaking_position = Vector3i.ZERO

	breaking_item_id = Inventory.EMPTY_ITEM_ID


# ============================================================
# CHECK WHETHER ID IS AN ITEM
# ============================================================

func is_item_id(
	item_id: int
) -> bool:

	return item_id >= FIRST_ITEM_ID


# ============================================================
# BLOCK PLACEMENT
# ============================================================

func _handle_block_placement(
	hit: VoxelRaycastResult
) -> void:

	# --------------------------------------------------------
	# CHANGING TO PLACEMENT CANCELS BREAKING
	# --------------------------------------------------------

	_reset_breaking()


	# --------------------------------------------------------
	# GET SELECTED ITEM
	# --------------------------------------------------------

	var selected_item_id: int = (
		inventory.get_selected_item_id()
	)


	# --------------------------------------------------------
	# EMPTY HOTBAR SLOT
	# --------------------------------------------------------

	if selected_item_id == Inventory.EMPTY_ITEM_ID:

		return


	# --------------------------------------------------------
	# ITEM / TOOL CANNOT BE PLACED
	# --------------------------------------------------------
	#
	# This is the important part.
	#
	# Stick = 1000
	#
	# 1000 >= 1000
	#
	# Therefore it is an ITEM and cannot be passed to the
	# voxel world as a block.
	#
	# --------------------------------------------------------

	if is_item_id(
		selected_item_id
	):

		_log(
			"Cannot place item ID "
			+ str(selected_item_id)
			+ " as a block."
		)

		return


	# --------------------------------------------------------
	# PLAY BLOCK PLACEMENT ANIMATION
	# --------------------------------------------------------

	_play_model_action(
		block_animation
	)


	# --------------------------------------------------------
	# CALCULATE PLACEMENT POSITION
	# --------------------------------------------------------

	var place_position: Vector3i = (
		hit.previous_position
	)


	# --------------------------------------------------------
	# CHECK PLAYER COLLISION
	# --------------------------------------------------------

	if not can_place_block(
		place_position
	):

		_log(
			"Cannot place block inside player."
		)

		return


	# --------------------------------------------------------
	# PLACE BLOCK
	# --------------------------------------------------------

	send_voxel_change(
		place_position,
		selected_item_id
	)


	# --------------------------------------------------------
	# REMOVE ONE FROM INVENTORY
	# --------------------------------------------------------

	inventory.remove_selected_item()


	_log(
		"Placed block ID: "
		+ str(selected_item_id)
	)


# ============================================================
# SEND VOXEL CHANGE
# ============================================================

func send_voxel_change(
	pos: Vector3i,
	block_id: int
) -> void:

	var game: Node = (
		get_tree().current_scene
	)


	if game == null:

		_log_warning(
			"Cannot send voxel change. "
			+ "Current scene is null."
		)

		return


	# ========================================================
	# SINGLE PLAYER
	# ========================================================

	if not multiplayer.has_multiplayer_peer():

		if Global.active_terrain != null:

			var tool: VoxelTool = (
				Global.active_terrain.get_voxel_tool()
			)


			tool.channel = (
				VoxelBuffer.CHANNEL_TYPE
			)


			tool.set_voxel(
				pos,
				block_id
			)

		return


	# ========================================================
	# MULTIPLAYER
	# ========================================================

	if multiplayer.is_server():

		game.request_voxel_change(
			pos,
			block_id
		)

	else:

		game.request_voxel_change.rpc_id(
			1,
			pos,
			block_id
		)


# ============================================================
# CAN PLACE BLOCK
# ============================================================

func can_place_block(
	block_pos: Vector3i
) -> bool:

	var game: Node = (
		get_tree().current_scene
	)


	if game == null:

		return can_place_block_against_player(
			block_pos,
			self
		)


	var players_node: Node = (
		game.get_node_or_null(
			"Players"
		)
	)


	if players_node == null:

		return can_place_block_against_player(
			block_pos,
			self
		)


	for child: Node in players_node.get_children():

		if child is CharacterBody3D:

			if not can_place_block_against_player(
				block_pos,
				child as CharacterBody3D
			):

				return false


	return true


# ============================================================
# CAN PLACE AGAINST PLAYER
# ============================================================

func can_place_block_against_player(
	block_pos: Vector3i,
	player: CharacterBody3D
) -> bool:

	var block_center: Vector3 = Vector3(
		float(block_pos.x) + 0.5,
		float(block_pos.y) + 0.5,
		float(block_pos.z) + 0.5
	)


	var player_feet: Vector3 = (
		player.global_position
	)


	var player_head: Vector3 = (
		player.global_position
		+ Vector3(0.0, 1.8, 0.0)
	)


	var horizontal_distance: float = Vector2(
		block_center.x
		- player.global_position.x,
		block_center.z
		- player.global_position.z
	).length()


	var overlaps_vertically: bool = (
		block_center.y > player_feet.y - 0.2
		and block_center.y < player_head.y + 0.2
	)


	if (
		horizontal_distance < 0.85
		and overlaps_vertically
	):

		return false


	return true


# ============================================================
# AUTO UNSTUCK
# ============================================================

func _auto_unstuck(
	delta: float
) -> void:

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

			voxel_tool = (
				Global.active_terrain.get_voxel_tool()
			)

		else:

			return


	voxel_tool.channel = (
		VoxelBuffer.CHANNEL_TYPE
	)


	if not is_body_inside_solid(
		global_position
	):

		return


	_log_warning(
		"Player is inside a solid voxel. "
		+ "Attempting unstuck."
	)


	for height: int in range(
		1,
		unstuck_max_search_height + 1
	):

		var test_position: Vector3 = (
			global_position
			+ Vector3(
				0.0,
				float(height),
				0.0
			)
		)


		if not is_body_inside_solid(
			test_position
		):

			global_position = (
				test_position
			)

			velocity = Vector3.ZERO


			_log(
				"Player unstuck to: "
				+ str(global_position)
			)


			return


# ============================================================
# CHECK BODY INSIDE SOLID
# ============================================================

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


	for y_offset: float in y_offsets:

		for xz_offset: Vector2 in xz_offsets:

			var sample_position: Vector3 = Vector3(
				test_position.x
				+ xz_offset.x,

				test_position.y
				+ y_offset,

				test_position.z
				+ xz_offset.y
			)


			var voxel_pos: Vector3i = Vector3i(
				floori(sample_position.x),
				floori(sample_position.y),
				floori(sample_position.z)
			)


			var block_id: int = (
				voxel_tool.get_voxel(
					voxel_pos
				)
			)


			if block_id != Block.AIR:

				return true


	return false


# ============================================================
# HAND SWING
# ============================================================

func play_hand_swing() -> void:

	if hand_anim == null:
		return


	var animation_name: StringName = (
		&"HandSwing"
	)


	if not hand_anim.has_animation(
		animation_name
	):

		_log_warning(
			"Animation 'HandSwing' does not exist."
		)

		return


	if hand_anim.is_playing():

		hand_anim.stop()


	hand_anim.play(
		animation_name
	)


# ============================================================
# DEBUG LOG
# ============================================================

func _log(
	message: String
) -> void:

	if enable_debug_logs:

		print(
			"[PlayerController] ",
			message
		)


# ============================================================
# DEBUG WARNING
# ============================================================

func _log_warning(
	message: String
) -> void:

	if enable_debug_logs:

		push_warning(
			"[PlayerController] "
			+ message
		)
