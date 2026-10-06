class_name PlayerController
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
@export var roll_key: Key = KEY_V
@export var lie_key: Key = KEY_Z
@export var sit_key: Key = KEY_X

@export_group("Pistol")
@export var pistol_damage: float = 25.0
@export var pistol_range: float = 50.0
@export var pistol_fire_rate: float = 0.25
@export var pistol_knockback: float = 2.0
@export var pistol_recoil: float = 1.5
@export var pistol_recoil_recover: float = 6.0
@export var pistol_mag_size: int = 12
@export var pistol_reload_time: float = 1.2

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

const STAND_HEIGHT: float = 1.9
const CROUCH_HEIGHT: float = 1.25
const PRONE_HEIGHT: float = 0.8

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var unstuck_timer: float = 0.0
var sync_timer: float = 0.0
var sync_interval: float = 0.05
var current_height: float = STAND_HEIGHT
var requested_height: float = STAND_HEIGHT
var camera_stand_y: float = 1.58
var movement_scale: float = 1.0
var movement_blocked: bool = false
var visual_pose: Dictionary = {}
var _extensions: Array[Node] = []
var _capture_input_blocked: bool = false
var remote_airborne: bool = false
var interaction_swing: float = 0.0
var _remote_position: Vector3
var _remote_yaw: float = 0.0
var _remote_pitch: float = 0.0
var _has_remote_snapshot: bool = false

func apply_remote_sync(position_value: Vector3, yaw: float, pitch: float, item_id: String, state: Dictionary) -> void:
	if is_multiplayer_authority():
		return
	# First snapshot and teleports snap; ordinary movement converges smoothly.
	if not _has_remote_snapshot or global_position.distance_to(position_value) > 10.0:
		global_position = position_value
		rotation.y = yaw
		camera.rotation.x = pitch
	_remote_position = position_value
	_remote_yaw = yaw
	_remote_pitch = pitch
	_has_remote_snapshot = true
	velocity = state.get("velocity", Vector3.ZERO)
	remote_airborne = bool(state.get("airborne", false))
	interaction_swing = float(state.get("swing", 0.0))
	visual_pose = (state.get("pose", {}) as Dictionary).duplicate()
	current_height = float(state.get("height", STAND_HEIGHT))
	camera.position.y = camera_stand_y - (STAND_HEIGHT - current_height) * 0.72
	var capsule: CapsuleShape3D = collision_shape.shape as CapsuleShape3D
	if capsule != null:
		capsule.height = current_height
		collision_shape.position.y = current_height * 0.5
	var visual: PlayerVisual = get_node_or_null("PlayerVisual") as PlayerVisual
	if visual != null:
		visual.set_held_item(item_id)
		visual.set_network_animation_phase(float(state.get("animation_phase", 0.0)))
	# Server-side edit checks must use the newest position, not a visual lag.
	if multiplayer.is_server():
		global_position = position_value

func _process(delta: float) -> void:
	if is_multiplayer_authority() or not _has_remote_snapshot:
		return
	var weight: float = 1.0 - exp(-delta * 20.0)
	global_position = global_position.lerp(_remote_position, weight)
	rotation.y = lerp_angle(rotation.y, _remote_yaw, weight)
	camera.rotation.x = lerp_angle(camera.rotation.x, _remote_pitch, weight)
	if bool(visual_pose.get("rolling", false)):
		visual_pose["roll_progress"] = minf(1.0, float(visual_pose.get("roll_progress", 0.0)) + delta / maxf(0.01, roll_duration))

# Optional mod-owned child hooks; called only on the local authority.
func add_movement_extension(extension: Node) -> void:
	if not _extensions.has(extension):
		_extensions.append(extension)

func remove_movement_extension(extension: Node) -> void:
	_extensions.erase(extension)

func gameplay_input_enabled() -> bool:
	return is_multiplayer_authority() and not bool(get_meta("gameplay_disabled", false)) and not _capture_input_blocked and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	# Shape ownership is per player, allocated once rather than each tick.
	if collision_shape.shape is CapsuleShape3D:
		collision_shape.shape = collision_shape.shape.duplicate() as CapsuleShape3D
		current_height = (collision_shape.shape as CapsuleShape3D).height
		requested_height = current_height
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
	_play_state_animation()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if bool(get_meta("gameplay_disabled", false)):
		return

	# Escape toggles between gameplay/captured mouse and free mouse.
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			_capture_input_blocked = true

		get_viewport().set_input_as_handled()
		return

	# Mouse wheel changes the selected hotbar slot.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed and gameplay_input_enabled():
			inventory.set_selected_slot(
				inventory.selected_slot - 1
			)
			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed and gameplay_input_enabled():
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
			_capture_input_blocked = true
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

	if not gameplay_input_enabled():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			inventory.set_selected_slot(event.keycode - KEY_1)
		elif event.keycode == KEY_0:
			inventory.set_selected_slot(9)
	for extension: Node in _extensions.duplicate():
		if is_instance_valid(extension) and extension.has_method("movement_input"):
			if bool(extension.call("movement_input", event)):
				get_viewport().set_input_as_handled()
				return

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	movement_scale = 1.0
	movement_blocked = false
	requested_height = STAND_HEIGHT
	for extension: Node in _extensions.duplicate():
		if is_instance_valid(extension) and extension.has_method("movement_prepare"):
			extension.call("movement_prepare", delta)
	_update_posture(delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	if gameplay_input_enabled() and not movement_blocked and Input.is_action_just_pressed("jump"):
		var handled: bool = false
		for extension: Node in _extensions.duplicate():
			if is_instance_valid(extension) and extension.has_method("movement_jump"):
				handled = bool(extension.call("movement_jump")) or handled
		if not handled and is_on_floor():
			velocity.y = jump_velocity
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	if not gameplay_input_enabled() or movement_blocked:
		direction = Vector3.ZERO
	var target: Vector3 = direction * speed * movement_scale
	var acceleration: float = ground_acceleration if is_on_floor() else air_acceleration
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	for extension: Node in _extensions.duplicate():
		if is_instance_valid(extension) and extension.has_method("movement_apply"):
			extension.call("movement_apply", delta)
	move_and_slide()
	_play_state_animation()
	_auto_unstuck(delta)
	_send_movement_sync(delta)
	_capture_input_blocked = false


func _update_posture(delta: float) -> void:
	var capsule: CapsuleShape3D = collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return
	var target_height: float = maxf(requested_height, capsule.radius * 2.0)
	if target_height > current_height:
		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		var clearance: CapsuleShape3D = CapsuleShape3D.new()
		clearance.radius = capsule.radius
		clearance.height = target_height
		query.shape = clearance
		query.transform = Transform3D(global_transform.basis, global_position + Vector3.UP * (target_height * 0.5 + 0.01))
		query.exclude = [get_rid()]
		query.collision_mask = collision_mask
		if not get_world_3d().direct_space_state.intersect_shape(query).is_empty():
			target_height = current_height
	current_height = move_toward(current_height, target_height, 5.0 * delta)
	capsule.height = current_height
	collision_shape.position.y = current_height * 0.5
	# Body origin remains at the feet; never teleport to change posture.
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
		inventory.get_selected_item_id(),
		{
			"velocity": velocity,
			"airborne": not is_on_floor(),
			"height": current_height,
			"pose": visual_pose,
			"swing": interaction_swing,
			"animation_phase": (get_node("PlayerVisual") as PlayerVisual).get_animation_phase(),
		}
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
	var capsule: CapsuleShape3D = collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return false
	for offset: Vector3 in capsule_samples(capsule.height, capsule.radius):
		var sample: Vector3 = test_position + offset
		var voxel_pos: Vector3i = Vector3i(floori(sample.x), floori(sample.y), floori(sample.z))
		var block_id: String = GameAPI.world.get_block_id(voxel_pos)
		if bool(GameAPI.content.get_block(block_id).get("solid", false)):
			return true
	return false


static func capsule_samples(height: float, radius: float) -> Array[Vector3]:
	var samples: Array[Vector3] = []
	var inset: float = minf(0.05, radius * 0.25)
	var radial: float = maxf(0.0, radius - inset)
	for y: float in [inset, radius, height * 0.5, height - radius, height - inset]:
		samples.append(Vector3(0.0, y, 0.0))
		if y >= radius and y <= height - radius:
			for offset: Vector2 in [Vector2(radial, 0), Vector2(-radial, 0), Vector2(0, radial), Vector2(0, -radial)]:
				samples.append(Vector3(offset.x, y, offset.y))
	return samples
