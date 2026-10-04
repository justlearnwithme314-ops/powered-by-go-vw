extends CharacterBody3D

@export_group("Movement")
@export var speed := 6.0
@export var jump_velocity := 5.0
@export var mouse_sensitivity := 0.002
@export var ground_acceleration: float = 30.0
@export var air_acceleration: float = 12.0
@export var extra_jumps: int = 1
@export var double_jump_velocity: float = 5.0
@export var dash_speed: float = 13.0
@export var dash_duration: float = 0.22
@export var dash_cooldown: float = 0.65
@export var roll_speed: float = 10.0
@export var roll_duration: float = 0.45
@export var wall_jump_velocity: float = 5.5
@export var wall_jump_push: float = 6.0
@export var crouch_speed_scale: float = 0.5
@export var prone_speed_scale: float = 0.25
@export var crouch_key: Key = KEY_C
@export var dash_key: Key = KEY_Q
@export var roll_key: Key = KEY_R
@export var lie_key: Key = KEY_Z
@export var sit_key: Key = KEY_X

@export_group("Pistol")
@export var pistol_damage: float = 25.0
@export var pistol_range: float = 50.0
@export var pistol_fire_rate: float = 0.15
@export var pistol_knockback: float = 2.0

@export_group("Safety")
@export var enable_debug_starting_inventory := false
@export var enable_auto_unstuck := true
@export var unstuck_check_interval := 0.25
@export var unstuck_max_search_height := 12

@export_group("Animation")
@export var idle_animation: StringName = &"idle"
@export var walk_animation: StringName = &"walk"
@export var jump_animation: StringName = &"jump"
@export var walk_animation_speed := 1.0

@onready var camera: Camera3D = $Camera3D
@onready var model_anim: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
@onready var inventory: Inventory = $Inventory
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var player_visual: Node3D = $PlayerVisual

const STAND_HEIGHT: float = 1.9
const CROUCH_HEIGHT: float = 1.25
const PRONE_HEIGHT: float = 0.8

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var unstuck_timer: float = 0.0
var sync_timer: float = 0.0
var sync_interval: float = 0.05
var jumps_remaining: int = 0
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var roll_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
var roll_direction: Vector3 = Vector3.ZERO
var crouch_held: bool = false
var lying: bool = false
var sitting: bool = false
var current_height: float = STAND_HEIGHT
var camera_stand_y: float = 1.58

# Pistol state
var has_pistol: bool = true
var pistol_cooldown_timer: float = 0.0


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	if model_anim and not model_anim.animation_finished.is_connected(_on_animation_finished):
		model_anim.animation_finished.connect(_on_animation_finished)

	if not is_multiplayer_authority():
		camera.current = false
		var viewer := camera.get_node_or_null("VoxelViewer")
		if viewer:
			viewer.queue_free()
		return

	camera.current = true
	camera_stand_y = camera.position.y
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_initialize_debug_inventory()
	_play_state_animation()
	
	# Enable pistol by default for testing
	if player_visual != null and player_visual.has_method("set_pistol"):
		player_visual.set_pistol(has_pistol)
	
	print("[PlayerController] Ready! Mouse mode: ", Input.get_mouse_mode())


func _initialize_debug_inventory() -> void:
	if not enable_debug_starting_inventory:
		return
	if inventory == null or not inventory.items.is_empty():
		return

	for item_id in ["core:grass", "core:dirt", "core:stone", "core:log"]:
		inventory.add_item(item_id, 32)
	inventory.assign_to_hotbar("core:grass", 0)
	inventory.assign_to_hotbar("core:dirt", 1)
	inventory.assign_to_hotbar("core:stone", 2)
	inventory.assign_to_hotbar("core:log", 3)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Escape toggles between gameplay/captured mouse and free mouse.
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

		get_viewport().set_input_as_handled()
		return

	# Mouse wheel changes the selected hotbar slot.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			inventory.set_selected_slot(
				inventory.selected_slot - 1
			)
			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			inventory.set_selected_slot(
				inventory.selected_slot + 1
			)
			get_viewport().set_input_as_handled()
			return

		# Left click while the mouse is visible captures it again.
		if (
			event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
			and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE
		):
			Input.set_mouse_mode(
				Input.MOUSE_MODE_CAPTURED
			)
			get_viewport().set_input_as_handled()
			return

	# Mouse look only works while the mouse is captured.
	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			return

		rotate_y(
			-event.relative.x * mouse_sensitivity
		)

		camera.rotate_x(
			-event.relative.y * mouse_sensitivity
		)

		camera.rotation.x = clampf(
			camera.rotation.x,
			deg_to_rad(-89.0),
			deg_to_rad(89.0)
		)

		return

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.physical_keycode == crouch_key:
			crouch_held = key_event.pressed
			get_viewport().set_input_as_handled()
		if key_event.pressed and not key_event.echo:
			if key_event.physical_keycode == dash_key:
				_start_dash()
			elif key_event.physical_keycode == roll_key:
				_start_roll()
			elif key_event.physical_keycode == lie_key:
				lying = not lying
				if lying:
					sitting = false
			elif key_event.physical_keycode == sit_key:
				sitting = not sitting
				if sitting:
					lying = false
			if key_event.keycode >= KEY_1 and key_event.keycode <= KEY_8:
				inventory.set_selected_slot(key_event.keycode - KEY_1)
		if key_event.physical_keycode == dash_key or key_event.physical_keycode == roll_key or key_event.physical_keycode == crouch_key or key_event.physical_keycode == lie_key or key_event.physical_keycode == sit_key:
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Debug: verify physics process runs
	if Engine.get_process_frames() % 120 == 0:
		print("[PlayerController] _physics_process running, has_pistol: ", has_pistol, ", mouse_mode: ", Input.get_mouse_mode(), ", is_action_pressed(shoot): ", Input.is_action_pressed("shoot"))

	if is_on_floor():
		jumps_remaining = extra_jumps
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - delta)
	if dash_timer > 0.0:
		dash_timer = maxf(0.0, dash_timer - delta)
	if roll_timer > 0.0:
		roll_timer = maxf(0.0, roll_timer - delta)
	if pistol_cooldown_timer > 0.0:
		pistol_cooldown_timer = maxf(0.0, pistol_cooldown_timer - delta)

	_update_posture(delta)
	if not is_on_floor() and dash_timer <= 0.0:
		velocity.y -= gravity * delta
	elif is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0

	var jump_pressed: bool = Input.is_action_just_pressed("jump") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not lying and not sitting
	if jump_pressed:
		_handle_jump()

	# Pistol shooting - debug every frame when pressed
	var shoot_pressed: bool = Input.is_action_pressed("shoot")
	if shoot_pressed:
		print("[PlayerController] Shoot pressed! mouse_mode: ", Input.get_mouse_mode(), " lying: ", lying, " sitting: ", sitting, " cooldown: ", pistol_cooldown_timer)
	
	if shoot_pressed and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not lying and not sitting and pistol_cooldown_timer <= 0.0:
		print("[PlayerController] Shoot input detected! Firing...")
		_shoot_pistol()

	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED or lying or sitting:
		direction = Vector3.ZERO
	if dash_timer > 0.0:
		velocity.x = dash_direction.x * dash_speed
		velocity.z = dash_direction.z * dash_speed
	elif roll_timer > 0.0:
		velocity.x = roll_direction.x * roll_speed
		velocity.z = roll_direction.z * roll_speed
	else:
		var speed_scale: float = prone_speed_scale if lying else (crouch_speed_scale if crouch_held or sitting else 1.0)
		var target: Vector3 = direction * speed * speed_scale
		var acceleration: float = ground_acceleration if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target.z, acceleration * delta)

	move_and_slide()
	_play_state_animation()
	_auto_unstuck(delta)
	_send_movement_sync(delta)


func _shoot_pistol() -> void:
	pistol_cooldown_timer = pistol_fire_rate
	print("[Pistol] _shoot_pistol() called! Cooldown set to: ", pistol_fire_rate)
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + (-camera.global_transform.basis.z * pistol_range))
	query.exclude = [get_rid()]
	query.collision_mask = 4294967295  # All layers
	
	var hit = space_state.intersect_ray(query)
	if hit:
		var hit_position = hit.position
		var hit_normal = hit.normal
		var collider = hit.collider
		
		print("[Pistol] HIT: ", collider, " at ", hit_position, " normal: ", hit_normal)
		
		# Apply damage/knockback to rigid bodies or characters
		if collider is RigidBody3D:
			collider.apply_impulse(-hit_normal * pistol_knockback, hit_position - collider.global_position)
			print("[Pistol] Applied knockback to RigidBody3D")
		elif collider is CharacterBody3D and collider != self:
			print("[Pistol] Hit character: ", collider.name)
			# collider.call_deferred("take_damage", pistol_damage)
	else:
		print("[Pistol] No hit within range: ", pistol_range)
	
	print("[Pistol] Fired! Damage: ", pistol_damage, " Range: ", pistol_range)


func _handle_jump() -> void:
	if is_on_floor():
		velocity.y = jump_velocity
		return
	if is_on_wall():
		var normal: Vector3 = get_wall_normal()
		velocity = Vector3(normal.x * wall_jump_push, wall_jump_velocity, normal.z * wall_jump_push)
		return
	if jumps_remaining > 0:
		velocity.y = double_jump_velocity
		jumps_remaining -= 1


func _start_dash() -> void:
	if dash_cooldown_timer > 0.0 or lying or sitting:
		return
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	dash_direction = (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	if dash_direction == Vector3.ZERO:
		dash_direction = -global_transform.basis.z
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	velocity.y = 0.0


func _start_roll() -> void:
	if not is_on_floor() or lying or sitting:
		return
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	roll_direction = (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	if roll_direction == Vector3.ZERO:
		roll_direction = -global_transform.basis.z
	roll_timer = roll_duration
	lying = false
	sitting = false


func _update_posture(delta: float) -> void:
	var old_height: float = current_height
	var target_height: float = PRONE_HEIGHT if lying else (CROUCH_HEIGHT if crouch_held or sitting else STAND_HEIGHT)
	if target_height > current_height:
		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		var clearance_shape: BoxShape3D = BoxShape3D.new()
		clearance_shape.size = Vector3(0.72, maxf(target_height - current_height, 0.01), 0.72)
		query.shape = clearance_shape
		query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * ((target_height + current_height) * 0.5))
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query).is_empty():
			target_height = current_height
	current_height = move_toward(current_height, target_height, 5.0 * delta)
	var capsule: CapsuleShape3D = collision_shape.shape as CapsuleShape3D
	if capsule != null:
		if collision_shape.shape == get_meta("original_capsule", collision_shape.shape):
			capsule = capsule.duplicate() as CapsuleShape3D
			collision_shape.shape = capsule
			set_meta("original_capsule", collision_shape.shape)
		capsule.height = current_height
	collision_shape.position.y = current_height * 0.5
	var height_delta: float = current_height - old_height
	global_position.y += height_delta * 0.5
	camera.position.y = camera_stand_y - (STAND_HEIGHT - current_height) * 0.72


func _play_state_animation() -> void:
	if model_anim == null:
		return

	if not is_on_floor():
		_play_animation_if_present(jump_animation)
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.1:
		_play_animation_if_present(walk_animation, walk_animation_speed)
	else:
		_play_animation_if_present(idle_animation)


func _play_animation_if_present(animation_name: StringName, speed_scale := 1.0) -> void:
	if model_anim == null or not model_anim.has_animation(animation_name):
		return

	model_anim.speed_scale = speed_scale
	if model_anim.current_animation != animation_name or not model_anim.is_playing():
		model_anim.play(animation_name)


func _on_animation_finished(_animation_name: StringName) -> void:
	pass


func _send_movement_sync(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or GameAPI.session == null:
		return

	sync_timer += delta
	if sync_timer < sync_interval:
		return
	sync_timer = 0.0

	var peer_id: int = multiplayer.get_unique_id()
	GameAPI.session.submit_player_sync(
		peer_id,
		global_position,
		rotation.y,
		camera.rotation.x,
		inventory.get_selected_item_id()
	)


func _auto_unstuck(delta: float) -> void:
	if not enable_auto_unstuck or GameAPI.world == null or GameAPI.world.tool == null:
		return

	unstuck_timer += delta
	if unstuck_timer < unstuck_check_interval:
		return
	unstuck_timer = 0.0

	if not _is_body_inside_solid(global_position):
		return

	for height in range(1, unstuck_max_search_height + 1):
		var test_position := global_position + Vector3(0.0, float(height), 0.0)
		if not _is_body_inside_solid(test_position):
			global_position = test_position
			velocity = Vector3.ZERO
			return


func _is_body_inside_solid(test_position: Vector3) -> bool:
	var y_offsets := [0.2, 0.9, 1.6]
	var xz_offsets := [
		Vector2(0.0, 0.0),
		Vector2(0.35, 0.35),
		Vector2(-0.35, 0.35),
		Vector2(0.35, -0.35),
		Vector2(-0.35, -0.35),
	]

	for y_offset in y_offsets:
		for xz in xz_offsets:
			var sample := test_position + Vector3(xz.x, y_offset, xz.y)
			var voxel_pos := Vector3i(
				floori(sample.x),
				floori(sample.y),
				floori(sample.z)
			)
			var block_id := GameAPI.world.get_block_id(voxel_pos)
			if bool(GameAPI.content.get_block(block_id).get("solid", false)):
				return true

	return false