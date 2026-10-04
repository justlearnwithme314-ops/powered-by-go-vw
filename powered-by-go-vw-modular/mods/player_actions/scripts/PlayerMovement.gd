class_name PlayerActionMovement
extends Node

var player: PlayerController
var jumps_remaining: int = 0
var dash_timer: float = 0.0
var cooldown: float = 0.0
var roll_timer: float = 0.0
var roll_cooldown: float = 0.0
var direction: Vector3 = Vector3.ZERO
var crouching: bool = false
var lying: bool = false
var sitting: bool = false
var walk_sound: AudioStreamPlayer

func setup(owner_player: PlayerController, api: ModAPI) -> void:
	player = owner_player
	walk_sound = AudioStreamPlayer.new()
	var stream: AudioStreamMP3 = api.load_asset("sounds/walking_regular.mp3") as AudioStreamMP3
	if stream != null:
		stream = stream.duplicate() as AudioStreamMP3
		stream.loop = true
		walk_sound.stream = stream
	walk_sound.volume_db = -6.0
	add_child(walk_sound)
	player.add_movement_extension(self)

func _exit_tree() -> void:
	if is_instance_valid(player):
		player.remove_movement_extension(self)
		player.visual_pose = {}

func movement_input(event: InputEvent) -> bool:
	if not player.gameplay_input_enabled() or not event is InputEventKey:
		return false
	var key: InputEventKey = event as InputEventKey
	if key.physical_keycode == player.crouch_key:
		crouching = key.pressed
		return true
	if not key.pressed or key.echo:
		return false
	if key.physical_keycode == player.dash_key:
		if cooldown <= 0.0 and dash_timer <= 0.0 and roll_timer <= 0.0 and not lying and not sitting:
			direction = _input_direction()
			dash_timer = maxf(0.01, player.dash_duration)
			cooldown = maxf(dash_timer, player.dash_cooldown)
		return true
	if key.physical_keycode == player.roll_key:
		if player.is_on_floor() and roll_cooldown <= 0.0 and dash_timer <= 0.0 and roll_timer <= 0.0 and not lying and not sitting:
			direction = _input_direction()
			roll_timer = maxf(0.01, player.roll_duration)
			roll_cooldown = roll_timer + 0.3
		return true
	if key.physical_keycode == player.lie_key or key.physical_keycode == player.sit_key:
		if player.is_on_floor() and dash_timer <= 0.0 and roll_timer <= 0.0:
			if key.physical_keycode == player.lie_key:
				lying = not lying
				sitting = false
			else:
				sitting = not sitting
				lying = false
		return true
	return false

func _input_direction() -> Vector3:
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var result: Vector3 = (player.transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	return -player.global_transform.basis.z if result == Vector3.ZERO else result

func movement_prepare(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	roll_cooldown = maxf(0.0, roll_cooldown - delta)
	dash_timer = maxf(0.0, dash_timer - delta)
	roll_timer = maxf(0.0, roll_timer - delta)
	if player.is_on_floor():
		jumps_remaining = player.extra_jumps
	else:
		# Ground-only poses must not float when stepping off a ledge.
		lying = false
		sitting = false
		roll_timer = 0.0
	if not player.gameplay_input_enabled():
		crouching = false
		dash_timer = 0.0
		roll_timer = 0.0
	elif crouching and not Input.is_physical_key_pressed(player.crouch_key):
		crouching = false
	player.requested_height = 0.8 if lying or roll_timer > 0.0 else (1.25 if sitting or crouching else player.STAND_HEIGHT)
	player.movement_blocked = lying or sitting or roll_timer > 0.0 or dash_timer > 0.0
	player.movement_scale = player.crouch_speed_scale if crouching or player.current_height < player.STAND_HEIGHT - 0.1 else 1.0
	player.visual_pose = {"lying": lying, "sitting": sitting, "crouching": crouching, "rolling": roll_timer > 0.0, "roll_progress": 1.0 - roll_timer / maxf(0.01, player.roll_duration)}
	var walking: bool = player.is_on_floor() and not player.movement_blocked and Vector2(player.velocity.x, player.velocity.z).length() > 0.5
	if walking and not walk_sound.playing:
		walk_sound.play()
	elif not walking and walk_sound.playing:
		walk_sound.stop()

func movement_jump() -> bool:
	if player.is_on_floor():
		player.velocity.y = player.jump_velocity
	elif player.is_on_wall():
		var normal: Vector3 = player.get_wall_normal()
		player.velocity = Vector3(normal.x * player.wall_jump_push, player.wall_jump_velocity, normal.z * player.wall_jump_push)
	elif jumps_remaining > 0:
		player.velocity.y = player.double_jump_velocity
		jumps_remaining -= 1
	return true

func movement_apply(_delta: float) -> void:
	if not player.gameplay_input_enabled():
		return
	if dash_timer > 0.0:
		player.velocity.x = direction.x * player.dash_speed
		player.velocity.z = direction.z * player.dash_speed
		player.velocity.y = 0.0
	elif roll_timer > 0.0:
		player.velocity.x = direction.x * player.roll_speed
		player.velocity.z = direction.z * player.roll_speed
