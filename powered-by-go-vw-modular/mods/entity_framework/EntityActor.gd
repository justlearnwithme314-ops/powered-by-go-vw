extends CharacterBody3D

var runtime: Node3D
var definition: Dictionary
var entity_id := ""
var home := Vector3.ZERO
var goal := Vector3.ZERO
var state := "idle"
var target: Node3D
var receiver: DamageReceiver
var visual: Node3D
var route: Array[Vector3] = []
var state_time := 0.0
var sense_clock := 0.0
var attack_clock := 0.0
var path_clock := 0.0
var flee_from := Vector3.ZERO
var dead := false
var replicated := false
var _stuck := 0.0
var _last := Vector3.ZERO
var _snapshot_position := Vector3.ZERO
var _snapshot_yaw := 0.0
var _hurt_clock := 0.0
var _saved_record: Dictionary = {}
var abilities: Array[Node] = []

func setup(owner_runtime: Node3D, record: Dictionary, replica: bool = false) -> void:
	runtime = owner_runtime
	entity_id = str(record.id)
	definition = runtime.api.entities.definition(str(record.kind))
	replicated = replica
	set_meta("entity_id", entity_id)
	add_to_group("world_entities")
	global_position = runtime.vector(record.position)
	home = runtime.vector(record.get("home", record.position))
	goal = global_position
	_last = global_position
	_snapshot_position = global_position
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(definition.get("radius", 0.35))
	capsule.height = float(definition.get("height", 1.8))
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	add_child(shape)
	receiver = DamageReceiver.new()
	receiver.name = "DamageReceiver"
	receiver.health = float(record.get("health", definition.health))
	add_child(receiver)
	receiver.damaged.connect(_damaged)
	receiver.depleted.connect(_depleted)
	visual = (definition.visual as Script).new() as Node3D
	add_child(visual)
	visual.call("setup", definition)
	for script in definition.get("abilities", []):
		if script is Script:
			var ability := script.new() as Node
			if ability != null:
				add_child(ability)
				abilities.append(ability)
				if ability.has_method("setup"):
					ability.call("setup", self, runtime.api)
				if ability.has_method("restore"):
					ability.call("restore", record.get("ability_state", {}).get(str(abilities.size() - 1), {}))
	dead = bool(record.get("dead", false))
	if dead:
		collision_layer = 0
		collision_mask = 0
		state = "dead"
	runtime.api.events.emit("entity_spawned", {"entity": self, "entity_id": entity_id})

func record() -> Dictionary:
	if not is_inside_tree():
		return _saved_record.duplicate(true)
	_saved_record = {"id": entity_id, "kind": definition.id, "position": runtime.array(global_position), "home": runtime.array(home), "health": receiver.health, "dead": dead}
	var ability_state := {}
	for i in range(abilities.size()):
		if abilities[i].has_method("save_state"):
			ability_state[str(i)] = abilities[i].call("save_state")
	_saved_record.ability_state = ability_state
	return _saved_record.duplicate(true)

func _exit_tree() -> void:
	record()

func apply_snapshot(data: Dictionary) -> void:
	_snapshot_position = runtime.vector(data.position)
	_snapshot_yaw = float(data.yaw)
	state = str(data.state)
	state_time = float(data.get("time", 0))
	if float(data.health) < receiver.health:
		_hurt_clock = 0.35
		_effect()
	receiver.health = float(data.health)
	dead = bool(data.dead)
	if dead:
		collision_layer = 0

func _physics_process(delta: float) -> void:
	_hurt_clock = maxf(_hurt_clock - delta, 0)
	state_time += delta
	if replicated:
		global_position = global_position.lerp(_snapshot_position, minf(delta * 12, 1))
		rotation.y = lerp_angle(rotation.y, _snapshot_yaw, minf(delta * 12, 1))
		visual.call("animate", state, state_time, _hurt_clock)
		return
	if dead:
		visual.call("animate", state, state_time, _hurt_clock)
		return
	for ability in abilities:
		if ability.has_method("tick"):
			ability.call("tick", self, delta)
	# Unloaded terrain cannot be mistaken for free space.
	if not runtime.api.world.is_loaded(Vector3i((global_position - Vector3.UP * 0.1).floor())):
		velocity = Vector3.ZERO
		return
	if global_position.y < -256:
		receiver.receive_damage(receiver.health, {"damage_type": "void"})
		return
	attack_clock = maxf(attack_clock - delta, 0)
	sense_clock -= delta
	path_clock -= delta
	if sense_clock <= 0:
		sense_clock = 0.35 + float(abs(entity_id.hash()) % 10) * 0.01
		_decide()
	if state == "windup" and state_time >= float(definition.get("windup", 0.4)):
		if is_instance_valid(target) and runtime.can_hit(self, target, float(definition.get("reach", 2))):
			runtime.damage_player(target, float(definition.get("damage", 3)), self)
		attack_clock = float(definition.get("cooldown", 1.2))
		_transition("recover")
	elif state == "recover" and state_time >= 0.35:
		_transition("idle")
	var speed := float(definition.get("speed", 2))
	if state == "flee":
		speed *= 1.6
	if state in ["chase", "flee", "wander", "return"]:
		if path_clock <= 0:
			path_clock = 0.8
			route = runtime.path_to(global_position, goal)
		var waypoint := route[0] if not route.is_empty() else global_position
		if not route.is_empty() and not runtime.api.world.can_stand(Vector3i(waypoint.floor())):
			route.clear()
			waypoint = global_position
		var direction := waypoint - global_position
		if Vector2(direction.x, direction.z).length() < 0.35 and not route.is_empty():
			route.pop_front()
		var flat := Vector3(direction.x, 0, direction.z).normalized()
		velocity.x = flat.x * speed
		velocity.z = flat.z * speed
		if flat.length_squared() > 0:
			rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), minf(delta * 8, 1))
		if direction.y > 0.4 and is_on_floor():
			velocity.y = 8.0
		elif is_on_floor() and flat.length_squared() > 0:
			var ahead := Vector3i((global_position + flat * 0.65).floor())
			if runtime.api.world.is_solid(ahead) and runtime.api.world.can_stand(ahead + Vector3i.UP):
				velocity.y = 8.0
		_stuck = _stuck + delta if global_position.distance_to(_last) < delta * 0.1 else 0
		if _stuck > 2:
			route.clear()
			goal = target.global_position if is_instance_valid(target) and state == "chase" else runtime.wander_goal(self)
			path_clock = 0
			_stuck = 0
	else:
		velocity.x = move_toward(velocity.x, 0, delta * 20)
		velocity.z = move_toward(velocity.z, 0, delta * 20)
	_last = global_position
	velocity.y -= 22.0 * delta
	move_and_slide()
	visual.call("animate", state if velocity.length() > 0.2 or state in ["windup", "recover"] else "idle", state_time, _hurt_clock)

func _decide() -> void:
	for ability in abilities:
		if ability.has_method("decide") and bool(ability.call("decide", self)):
			return
	if state in ["windup", "recover"]:
		return
	var flee_threshold := float(definition.get("flee_health_ratio", 0.0))
	if flee_threshold > 0 and receiver.health > 0 and receiver.health <= float(definition.health) * flee_threshold and is_instance_valid(target):
		flee_from = target.global_position
		_set_flee_goal()
		_transition("flee")
		return
	if state == "flee" and state_time < float(definition.get("flee_duration", 4.0)):
		return
	if str(definition.get("faction", "passive")) == "hostile":
		if not is_instance_valid(target) or bool(target.get_meta("gameplay_disabled", false)) or target.global_position.distance_to(home) > 28:
			target = null
		if target == null:
			target = runtime.find_target(self, float(definition.get("detect", 16)))
		if is_instance_valid(target):
			goal = target.global_position
			if attack_clock <= 0 and runtime.can_hit(self, target, float(definition.get("reach", 2))):
				_transition("windup")
			else:
				_transition("chase")
			return
	if global_position.distance_to(home) > 10:
		goal = home
		_transition("return")
	elif state in ["wander", "return"] and global_position.distance_to(goal) > 0.7 and state_time < 5:
		return
	elif state != "idle" or state_time > 2:
		goal = runtime.wander_goal(self)
		_transition("wander" if goal.distance_to(global_position) > 0.5 else "idle")

func _transition(next: String) -> void:
	if state == next:
		return
	state = next
	state_time = 0

func _damaged(amount: float, context: Dictionary) -> void:
	if replicated:
		return
	_hurt_clock = 0.35
	_effect()
	var source := context.get("source") as Node3D
	if source != null and definition.get("faction", "passive") != "hostile":
		flee_from = source.global_position
		_set_flee_goal()
		_transition("flee")
	elif source != null:
		target = source
		if receiver.health > 0 and receiver.health <= float(definition.health) * float(definition.get("flee_health_ratio",0)):
			flee_from = source.global_position
			_set_flee_goal()
			_transition("flee")
	runtime.api.events.emit("entity_damaged", {"entity_id": entity_id, "amount": amount, "context": context})

func _set_flee_goal() -> void:
	var away := global_position - flee_from
	away.y = 0
	if away.length_squared() < 0.01:
		away = global_basis.z
	away = away.normalized()
	# Find an escape cell with support instead of fleeing into a wall or void.
	for angle in [0.0, 0.65, -0.65, 1.2, -1.2]:
		for distance in [6.0, 4.0, 2.0]:
			var cell := Vector3i((global_position + away.rotated(Vector3.UP, angle) * distance).floor())
			for dy in [0,1,-1]:
				if runtime.api.world.can_stand(cell + Vector3i(0,dy,0)):
					goal = Vector3(cell + Vector3i(0,dy,0)) + Vector3(0.5,0.05,0.5)
					path_clock = 0
					return
	goal = global_position

func _depleted(context: Dictionary) -> void:
	if replicated or dead:
		return
	# Persist death and loot together before displaying a committed death.
	if not runtime.commit_death(self, context):
		receiver.health = 1
		return
	dead = true
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_transition("dead")
	_effect()
	runtime.api.events.emit("entity_died", {"entity": self, "entity_id": entity_id, "context": context})

func interact(player: Node3D) -> void:
	if dead or not runtime.authority() or not runtime.can_hit(player, self, 3):
		return
	runtime.api.events.emit("entity_interact", {"entity": self, "entity_id": entity_id, "player": player})
	for ability in abilities:
		if ability.has_method("interact"):
			ability.call("interact", player)

func _effect() -> void:
	var particles := CPUParticles3D.new()
	particles.amount = 8
	particles.lifetime = 0.3
	particles.one_shot = true
	particles.explosiveness = 1
	particles.direction = Vector3.UP
	particles.spread = 90
	particles.initial_velocity_min = 1
	particles.initial_velocity_max = 2
	particles.gravity = Vector3.DOWN * 6
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.06
	particles.mesh = box
	runtime.add_child(particles)
	particles.global_position = global_position + Vector3.UP * 0.7
	particles.finished.connect(particles.queue_free)
	particles.emitting = true
	var sound: AudioStream = definition.get("hit_sound") as AudioStream
	if sound != null:
		var audio := AudioStreamPlayer3D.new()
		audio.stream = sound
		audio.volume_db = -12
		audio.max_distance = 24
		runtime.add_child(audio)
		audio.global_position = global_position + Vector3.UP
		audio.finished.connect(audio.queue_free)
		audio.play()
