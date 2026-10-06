extends Node3D

const ACTOR = preload("EntityActor.gd")
const PATH = preload("GridPath.gd")
const STATE := "entities:world"
var api: ModAPI
var actors: Dictionary = {}
var records: Dictionary = {}
var loot: Dictionary = {}
var offers: Dictionary = {}
var profiles: Dictionary = {}
var world_id := ""
var path := ""
var writable := true
var spawning := true
var pig_cap := 8
var hostile_cap := 6
var spawn_min_distance := 10.0
var spawn_max_distance := 24.0
var _clock := 0.0
var _spawn_clock := 0.0
var _save_clock := 0.0
var _sequence := 0
var _last_sequence := -1
var _rng := RandomNumberGenerator.new()
var _views: Dictionary = {}
var _credentials: Dictionary = {}
var _peer_keys: Dictionary = {}
var _attack_times: Dictionary = {}
var _join_clock := 0.0
var _joined := false
var _identity := ""
var _extra: Dictionary = {}
var _networked := false
var _authority := true
var _commands: InventoryCommandService
var _inventory_revision := 0
var _last_inventory_revision := -1
var _command_id := 0
var _command_highwater: Dictionary = {}
var _path_budget := 4

func setup(context: ModAPI) -> void:
	api = context
	_commands = InventoryCommandService.new(api.stations, api.crafting)
	_commands.item_instances = api.item_instances
	_networked = multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	_authority = not _networked or multiplayer.is_server()
	if _networked and _authority:
		multiplayer.peer_disconnected.connect(_disconnected)
	_rng.seed = api.world_generation.world_seed
	api.on(GameEvents.PLAYER_SPAWNED, _player_spawned)
	api.on(GameEvents.AFTER_BLOCK_BREAK, _block_broken, -200)
	api.on(GameEvents.BEFORE_BLOCK_PLACE, _before_place, 200)
	api.on(GameEvents.AFTER_BLOCK_PLACE, _block_placed, -200)
	if authority():
		world_id = api.saves.active_world_id
		path = api.saves.root_path.path_join(world_id + ".creatures.json") if networked() else ""
		var data := api.stations.player_data(STATE)
		if networked() and FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				data = parsed
			else:
				writable = false
		if not data.is_empty():
			if int(data.get("version", 0)) != 1 or not data.get("actors", {}) is Dictionary or not data.get("loot", {}) is Dictionary or not data.get("offers", {}) is Dictionary or not data.get("profiles", {}) is Dictionary or not data.get("credentials", {}) is Dictionary or not data.get("loot_receipts", {}) is Dictionary:
				writable = false
			else:
				_extra = data.duplicate(true)
				records = data.get("actors", {}).duplicate(true)
				loot = data.get("loot", {}).duplicate(true)
				offers = data.get("offers", {}).duplicate(true)
				profiles = data.get("profiles", {}).duplicate(true)
				_credentials = data.get("credentials", {}).duplicate(true)
				world_id = str(data.get("world_id", world_id))
				for id in records:
					if not valid_record(records[id]):
						writable = false
				for id in loot:
					if not valid_loot(loot[id]):
						writable = false
				for id in offers:
					if not offers[id] is Dictionary or not offers[id].get("stack") is Dictionary or not offers[id].get("owner") is String:
						writable = false
				for key in profiles:
					if not profiles[key] is Dictionary:
						writable = false
		# A random persistent scope prevents receipts colliding after recreating a world.
		if not _extra.has("scope"):
			_extra.scope = Crypto.new().generate_random_bytes(16).hex_encode()
	if not writable:
		push_error("[Entities] Unreadable/newer creature state preserved; simulation disabled.")
		set_physics_process(false)

func networked() -> bool:
	return _networked

func authority() -> bool:
	return _authority

func array(p: Vector3) -> Array:
	return [p.x, p.y, p.z]

func vector(p: Array) -> Vector3:
	return Vector3(float(p[0]), float(p[1]), float(p[2]))

func finite_vector(p: Variant) -> bool:
	if not p is Array or p.size() != 3:
		return false
	for value in p:
		if not (value is float or value is int) or not is_finite(float(value)) or absf(float(value)) > 1000000:
			return false
	return true

func valid_record(record: Variant) -> bool:
	return record is Dictionary and record.get("id") is String and record.get("kind") is String and finite_vector(record.get("position")) and finite_vector(record.get("home", record.get("position"))) and (record.get("health") is float or record.get("health") is int) and is_finite(float(record.health)) and record.get("ability_state", {}) is Dictionary

func valid_loot(record: Variant) -> bool:
	return record is Dictionary and finite_vector(record.get("position")) and record.get("stack") is Dictionary and int(record.stack.get("count", 0)) > 0

func spawn(kind: String, position: Vector3) -> Node3D:
	if not authority() or not writable or api.entities.definition(kind).is_empty() or records.size() >= 256 or not finite_vector(array(position)):
		return null
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	var record := {"id": id, "kind": kind, "position": array(position), "home": array(position), "health": api.entities.definition(kind).health, "dead": false}
	records[id] = record
	var actor := instantiate_record(record)
	if not save_state():
		records.erase(id)
		_remove_actor(id)
		return null
	return actor

func instantiate_record(record: Dictionary, replica: bool = false) -> Node3D:
	if api.entities.definition(str(record.kind)).is_empty():
		return null
	var actor := ACTOR.new()
	actor.name = "Entity_" + str(record.id)
	add_child(actor)
	actor.setup(self, record, replica)
	actors[str(record.id)] = actor
	return actor

func path_to(start: Vector3, goal: Vector3) -> Array[Vector3]:
	if _path_budget <= 0:
		return []
	_path_budget -= 1
	return PATH.find(api.world, Vector3i(start.floor()), Vector3i(goal.floor()))

func wander_goal(actor: Node3D) -> Vector3:
	for attempt in range(6):
		var cell := Vector3i((actor.global_position + Vector3(_rng.randf_range(-5, 5), 0, _rng.randf_range(-5, 5))).floor())
		for y in [0, 1, -1]:
			if api.world.can_stand(cell + Vector3i(0, y, 0)):
				return Vector3(cell + Vector3i(0, y, 0)) + Vector3(0.5, 0.05, 0.5)
	return actor.global_position

func players(include_dead: bool = false) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not is_inside_tree():
		return result
	for node in get_tree().get_nodes_in_group("player_character"):
		if node is Node3D and node.multiplayer == multiplayer and (include_dead or not bool(node.get_meta("gameplay_disabled", false))):
			result.append(node)
	return result

func can_hit(source: Node3D, target: Node3D, reach: float) -> bool:
	if bool(target.get_meta("gameplay_disabled", false)) or source.global_position.distance_to(target.global_position) > reach:
		return false
	var from := source.global_position + Vector3.UP * 0.9
	var to := target.global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if source is CollisionObject3D:
		query.exclude = [(source as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == target

func find_target(actor: Node3D, reach: float) -> Node3D:
	var closest: Node3D
	for player in players():
		if player.global_position.distance_to(actor.home) <= 28 and can_hit(actor, player, reach):
			if closest == null or player.global_position.distance_to(actor.global_position) < closest.global_position.distance_to(actor.global_position):
				closest = player
	return closest

func damage_player(player: Node3D, amount: float, source: Node3D) -> void:
	if authority():
		DamageReceiver.deliver(player, amount, {"source": source, "damage_type": "physical"})

func commit_death(actor: Node3D, _context: Dictionary) -> bool:
	if not writable or not authority() or loot.size() + actor.definition.get("loot", []).size() > 512:
		return false
	var previous := records.duplicate(true)
	var old_loot := loot.duplicate(true)
	var record: Dictionary = actor.record()
	if bool(records.get(actor.entity_id, {}).get("dead", false)):
		return true
	record.dead = true
	record.health = 0
	records[actor.entity_id] = record
	for i in range(actor.definition.get("loot", []).size()):
		var stack: Dictionary = actor.definition.loot[i].duplicate(true)
		var id := "%s:%s:%d" % [_extra.scope, actor.entity_id, i]
		loot[id] = {"stack": stack, "position": array(actor.global_position + Vector3.UP * 0.25)}
	if not persist():
		records = previous
		loot = old_loot
		return false
	return true

func save_state() -> bool:
	if not authority() or not writable:
		return false
	for id in actors:
		if not actors[id].replicated:
			records[id] = actors[id].record()
	if networked():
		for player in players(true):
			if player.get_multiplayer_authority() == 1:
				profiles["host_inventory"] = player_snapshot(player)
			elif _peer_keys.has(player.get_multiplayer_authority()):
				profiles[_peer_keys[player.get_multiplayer_authority()]] = player_snapshot(player)
	return persist()

func persist() -> bool:
	if not writable:
		return false
	var data := _extra.duplicate(true)
	data.merge({"version": 1, "world_id": world_id, "actors": records, "loot": loot, "offers": offers, "profiles": profiles, "credentials": _credentials}, true)
	if not networked():
		var previous := api.stations.player_data(STATE)
		api.stations.set_player_data(STATE, data)
		if api.stations.save():
			return true
		api.stations.set_player_data(STATE, previous)
		return false
	return write_json(path, data)

func spawn_loot(receipt: String, stack: Dictionary, position: Vector3) -> bool:
	if not authority() or not writable or receipt.is_empty() or not finite_vector(array(position)):
		return false
	var receipts: Dictionary = _extra.get("loot_receipts", {})
	if receipts.has(receipt):
		return true
	if receipts.size() >= 4096 or loot.size() >= 512:
		return false
	var storage := SlotContainer.new(api.content, 1)
	if not storage.valid(stack):
		return false
	var id := "%s:reward:%s" % [_extra.scope, receipt.sha256_text()]
	loot[id] = {"stack": stack.duplicate(true), "position": array(position)}
	receipts[receipt] = true
	_extra.loot_receipts = receipts
	if persist():
		return true
	loot.erase(id)
	receipts.erase(receipt)
	return false

func write_json(destination: String, data: Dictionary) -> bool:
	if destination.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var file := FileAccess.open(destination + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	if FileAccess.file_exists(destination) and DirAccess.copy_absolute(destination, destination + ".bak") != OK:
		return false
	return DirAccess.rename_absolute(destination + ".tmp", destination) == OK

func pickup_local(player: Node3D, id: String) -> bool:
	if not loot.has(id) or bool(player.get_meta("gameplay_disabled", false)) or vector(loot[id].position).distance_to(player.global_position + Vector3.UP * 0.5) > 1.5:
		return false
	var inventory := player.get_node_or_null("Inventory") as Inventory
	if inventory == null or api.stations.inventory != inventory:
		return false
	var before := inventory.get_snapshot()
	var old_loot: Dictionary = loot[id].duplicate(true)
	var result := inventory.add_stack(old_loot.stack)
	if int(result.added) == 0:
		return false
	if result.remainder.is_empty():
		loot.erase(id)
	else:
		loot[id].stack = result.remainder
	if not persist():
		loot[id] = old_loot
		inventory.load_snapshot(before)
		return false
	return true

func _physics_process(delta: float) -> void:
	if api == null:
		return
	_path_budget = 4
	_clock += delta
	_save_clock += delta
	_spawn_clock += delta
	_join_clock += delta
	if not authority():
		if not _joined and _join_clock >= 1 and not players().is_empty():
			_join_clock = 0
			_identity = load_identity()
			join_world.rpc_id(1, _identity)
		return
	if _clock >= 0.2:
		_clock = 0
		update_population()
		update_loot()
		if networked():
			_sequence += 1
			snapshot.rpc(_sequence, snapshot_data())
	if spawning and _spawn_clock >= 3:
		_spawn_clock = 0
		spawn_attempt()
	if _save_clock >= 2:
		_save_clock = 0
		save_state()

func update_population() -> void:
	var active_players := players()
	for id in records.keys():
		var record: Dictionary = records[id]
		if bool(record.get("dead", false)):
			if actors.has(id) and actors[id].state_time > 2:
				_remove_actor(id)
				# Death+loot has committed. Never reuse this random ID; no growing tombstone cap.
				records.erase(id)
			elif not actors.has(id) and not api.entities.definition(str(record.kind)).is_empty():
				records.erase(id)
			continue
		var near := false
		for player in active_players:
			if vector(record.position).distance_to(player.global_position) < 80:
				near = true
		var cell := Vector3i(vector(record.position).floor())
		if near and not actors.has(id) and api.world.is_loaded(cell + Vector3i.DOWN) and not api.world.is_solid(cell):
			instantiate_record(record)
		elif not near and actors.has(id):
			records[id] = actors[id].record()
			_remove_actor(id)

func _remove_actor(id: String) -> void:
	var node: Node = actors[id]
	actors.erase(id)
	api.events.emit("entity_despawned", {"entity_id": id})
	node.queue_free()

func spawn_attempt() -> void:
	var active := players()
	if active.is_empty() or records.size() >= 256:
		return
	var player: Node3D = active[_rng.randi_range(0, active.size() - 1)]
	var counts := {}
	for id in records:
		var record: Dictionary = records[id]
		if not bool(record.get("dead", false)) and vector(record.position).distance_to(player.global_position) < 96:
			counts[record.kind] = int(counts.get(record.kind, 0)) + 1
	for kind in api.entities.definitions:
		var definition := api.entities.definition(kind)
		if not bool(definition.get("natural_spawn", false)):
			continue
		var cap := hostile_cap if definition.get("faction") == "hostile" else pig_cap
		if int(counts.get(kind, 0)) >= cap:
			continue
		for attempt in range(12):
			var angle := _rng.randf() * TAU
			var radius := _rng.randf_range(spawn_min_distance, spawn_max_distance)
			var candidate := player.global_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
			var cell := Vector3i(candidate.floor())
			var found_ground := false
			# Search loaded cells directly: rays can stop on tree crowns or start
			# inside a hillside. Skip wood/leaves and require clear body space.
			for offset in range(24, -41, -1):
				var feet := Vector3i(cell.x, cell.y + offset, cell.z)
				var ground := feet + Vector3i.DOWN
				if not api.world.is_loaded(ground):
					continue
				var block_id := api.world.get_block_id(ground)
				if block_id in ["core:log", "core:leaves"]:
					continue
				if api.world.can_stand(feet, ceili(float(definition.get("height", 2.0)))):
					cell = feet
					found_ground = true
					break
			if not found_ground:
				continue
			var position := Vector3(cell) + Vector3(0.5, 0.05, 0.5)
			var separated := true
			for other in active:
				if position.distance_to(other.global_position) < spawn_min_distance:
					separated = false
			for actor in actors.values():
				if position.distance_to(actor.global_position) < 2:
					separated = false
			if separated:
				spawn(kind, position)
				break

func update_loot() -> void:
	for id in _views.keys():
		if not loot.has(id):
			_views[id].queue_free()
			_views.erase(id)
	for id in loot:
		if not _views.has(id):
			_make_loot(id)
		_views[id].rotation.y += 0.2
	for player in players():
		for id in loot.keys():
			if networked():
				if vector(loot[id].position).distance_to(player.global_position + Vector3.UP * 0.5) < 1.5:
					reserve_loot(player, id)
			else:
				pickup_local(player, id)
	if networked():
		for id in offers:
			for peer in _peer_keys:
				if offers[id].owner == _peer_keys[peer] and int(peer) in multiplayer.get_peers():
					reward.rpc_id(int(peer), id, profiles.get(offers[id].owner, {}))

func _make_loot(id: String) -> void:
	var node := Node3D.new()
	add_child(node)
	node.global_position = vector(loot[id].position)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.2
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.82, 0.55) if str(loot[id].stack.id).contains("bone") else Color(0.85, 0.35, 0.3)
	mesh.material_override = material
	node.add_child(mesh)
	var label := Label3D.new()
	label.text = "%s ×%d" % [api.content.get_item(str(loot[id].stack.id)).get("display_name", loot[id].stack.id), int(loot[id].stack.count)]
	label.position.y = 0.3
	label.pixel_size = 0.002
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.add_child(label)
	_views[id] = node

func submit_attack(player: Node3D, id: String) -> void:
	if authority():
		attack(player, id)
	else:
		request_attack.rpc_id(1, id)

func attack(player: Node3D, id: String) -> bool:
	if not authority() or not actors.has(id) or actors[id].dead or bool(player.get_meta("gameplay_disabled", false)):
		return false
	var now := Time.get_ticks_msec()
	var key := player.get_multiplayer_authority()
	if now - int(_attack_times.get(key, -1000)) < 350:
		return false
	_attack_times[key] = now
	var actor: Node3D = actors[id]
	if not can_hit(player, actor, 3):
		return false
	var inventory := player.get_node_or_null("Inventory") as Inventory
	var stack := inventory.get_slot(inventory.selected_slot) if inventory != null else {}
	# Network clients cannot nominate item stats; only server-owned equipment applies.
	if not api.item_instances.usable(stack):
		return false
	var amount := float(api.item_instances.stats(stack).get("melee_damage", 1))
	var previous: float = actor.receiver.health
	DamageReceiver.deliver(actor, amount, {"source": player, "damage_type": "physical"})
	if actor.receiver.health < previous:
		if inventory != null:
			api.item_instances.spend(inventory, inventory.selected_slot)
		actor.velocity += (actor.global_position - player.global_position).normalized() * 3 + Vector3.UP
		if networked():
			save_inventory(player)
		return true
	return false

@rpc("any_peer", "reliable")
func request_attack(id: String) -> void:
	if not authority():
		return
	var peer := multiplayer.get_remote_sender_id()
	for player in players():
		if player.get_multiplayer_authority() == peer and _peer_keys.has(peer):
			attack(player, id)

func snapshot_data() -> Dictionary:
	var entities := {}
	for id in actors:
		var actor: Node3D = actors[id]
		var data: Dictionary = actor.record()
		data.merge({"yaw": actor.rotation.y, "state": actor.state, "time": actor.state_time}, true)
		entities[id] = data
	return {"entities": entities, "loot": loot}

@rpc("authority", "unreliable_ordered", "call_remote", 2)
func snapshot(sequence: int, data: Dictionary) -> void:
	if authority() or sequence <= _last_sequence or not data.get("entities") is Dictionary or data.entities.size() > 256:
		return
	_last_sequence = sequence
	for id in actors.keys():
		if not data.entities.has(id):
			_remove_actor(id)
	for id in data.entities:
		var record: Dictionary = data.entities[id]
		if not valid_record(record):
			continue
		if not actors.has(id):
			instantiate_record(record, true)
		if actors.has(id):
			actors[id].apply_snapshot(record)
	loot = data.get("loot", {}).duplicate(true)
	update_loot_views()

func update_loot_views() -> void:
	for id in _views.keys():
		if not loot.has(id):
			_views[id].queue_free()
			_views.erase(id)
	for id in loot:
		if not _views.has(id) and valid_loot(loot[id]):
			_make_loot(id)

func load_identity() -> String:
	var destination := "user://creature_identity.json"
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(destination)) if FileAccess.file_exists(destination) else {}
	if value is Dictionary and str(value.get("token", "")).length() == 64:
		return value.token
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	return token if write_json(destination, {"token": token}) else ""

@rpc("any_peer", "reliable")
func join_world(token: String) -> void:
	if not authority() or token.length() != 64 or token.hex_decode().size() != 32:
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer <= 1:
		return
	var key := token.sha256_text()
	# Token is a private bearer credential; peers cannot nominate another reward owner.
	if _peer_keys.values().has(key) and _peer_keys.get(peer, "") != key:
		return
	_credentials[key] = true
	_peer_keys[peer] = key
	for player in players(true):
		if player.get_multiplayer_authority() == peer:
			var inventory := player.get_node("Inventory") as Inventory
			inventory.load_snapshot(profiles.get(key, {"version": 2, "hotbar_size": 10, "slots": []}))
			player.set_meta("inventory_authority", true)
			var vitals := player.get_node_or_null("DamageReceiver")
			if vitals != null and vitals.has_method("restore"):
				vitals.call("restore", profiles.get(key, {}).get("creature_vitals", {}))
	if persist():
		joined.rpc_id(peer, str(_extra.scope))
		for player in players(true):
			if player.get_multiplayer_authority() == peer:
				publish_inventory(player)

@rpc("authority", "reliable")
func joined(scope: String) -> void:
	if authority():
		return
	_joined = true
	world_id = scope
	for player in players(true):
		if player.is_multiplayer_authority():
			(player.get_node("Inventory") as Inventory).network_adapter = self
			var session := player.get_parent().get_parent()
			if session.has_method("set_network_world_scope"):
				session.call("set_network_world_scope", scope)

func reserve_loot(player: Node3D, id: String) -> bool:
	var peer := player.get_multiplayer_authority()
	if peer == 1:
		return pickup_host(player, id)
	if not _peer_keys.has(peer) or not loot.has(id) or offers.size() >= 512:
		return false
	var old: Dictionary = loot[id]
	var inventory := player.get_node("Inventory") as Inventory
	var before := inventory.get_snapshot()
	if int(inventory.add_stack(old.stack, true).added) == 0:
		return false
	inventory.reward_receipts[id] = true
	var owner: String = _peer_keys[peer]
	profiles[owner] = player_snapshot(player)
	offers[id] = {"owner": _peer_keys[peer], "stack": old.stack}
	loot.erase(id)
	if not persist():
		loot[id] = old
		offers.erase(id)
		inventory.load_snapshot(before, true)
		profiles[owner] = before
		return false
	return true

func pickup_host(player: Node3D, id: String) -> bool:
	var inventory := player.get_node_or_null("Inventory") as Inventory
	if inventory == null:
		return false
	# Host inventory and death loot share the creature transaction until exit.
	var before := inventory.get_snapshot()
	var old: Dictionary = loot[id].duplicate(true)
	var result := inventory.add_stack(old.stack)
	if int(result.added) == 0:
		return false
	if result.remainder.is_empty():
		loot.erase(id)
	else:
		loot[id].stack = result.remainder
	profiles["host_inventory"] = player_snapshot(player)
	if not persist():
		inventory.load_snapshot(before)
		loot[id] = old
		profiles["host_inventory"] = before
		return false
	return true

@rpc("authority", "reliable")
func reward(id: String, stack: Dictionary) -> void:
	if authority() or not _joined:
		return
	for player in players(true):
		if player.is_multiplayer_authority():
			var inventory := player.get_node("Inventory") as Inventory
			if inventory.reward_receipts.has(id):
				ack_reward.rpc_id(1, id)
				return
			var before := inventory.get_snapshot()
			# This payload is the authority's inventory, never a client-origin stack.
			if not stack.has("slots"):
				return
			inventory.load_snapshot(stack, true)
			var session := player.get_parent().get_parent()
			if session.has_method("_save_local_player_state") and bool(session.call("_save_local_player_state")):
				ack_reward.rpc_id(1, id)
			else:
				inventory.load_snapshot(before)

@rpc("any_peer", "reliable")
func ack_reward(id: String) -> void:
	if not authority():
		return
	var peer := multiplayer.get_remote_sender_id()
	if offers.has(id) and offers[id].owner == _peer_keys.get(peer, ""):
		var old: Dictionary = offers[id]
		offers.erase(id)
		if not persist():
			offers[id] = old

func _player_spawned(event: Dictionary) -> Dictionary:
	var player := event.get("player") as Node3D
	if player == null or player.multiplayer != multiplayer or not networked() or player.has_node("DamageReceiver"):
		return event
	if authority() and player.get_multiplayer_authority() == 1 and profiles.has("host_inventory"):
		(player.get_node("Inventory") as Inventory).load_snapshot(profiles.host_inventory)
	var vitals := api.load_asset("NetworkVitals.gd").new() as Node
	vitals.name = "DamageReceiver"
	vitals.set_multiplayer_authority(1)
	player.add_child(vitals)
	vitals.call("setup", self)
	if authority() and player.get_multiplayer_authority() == 1:
		vitals.call("restore", profiles.get("host_inventory", {}).get("creature_vitals", {}))
	if authority():
		player.set_meta("inventory_authority", true)
		if player.get_multiplayer_authority() > 1:
			api.world.track_actor(player)
	else:
		# Disable local grants/consumption from the first frame of a network spawn.
		(player.get_node("Inventory") as Inventory).network_adapter = self
	return event

func _exit_tree() -> void:
	if api != null:
		if authority():
			save_state()
		api.off(GameEvents.PLAYER_SPAWNED, _player_spawned)
		api.off(GameEvents.AFTER_BLOCK_BREAK, _block_broken)
		api.off(GameEvents.BEFORE_BLOCK_PLACE, _before_place)
		api.off(GameEvents.AFTER_BLOCK_PLACE, _block_placed)

func _disconnected(peer: int) -> void:
	_peer_keys.erase(peer)
	_attack_times.erase(peer)
	_command_highwater.erase(peer)

func submit_interaction(player: Node3D, id: String) -> void:
	if authority():
		if actors.has(id):
			actors[id].interact(player)
	else:
		request_interaction.rpc_id(1, id)

@rpc("any_peer", "reliable")
func request_interaction(id: String) -> void:
	if not authority() or not actors.has(id):
		return
	var peer := multiplayer.get_remote_sender_id()
	for player in players():
		if player.get_multiplayer_authority() == peer and _peer_keys.has(peer):
			actors[id].interact(player)

func inventory_request(player: Node, action: String, arguments: Dictionary) -> Dictionary:
	if authority():
		return _commands.request(player, action, arguments)
	_command_id += 1
	request_inventory.rpc_id(1, _command_id, action, arguments)
	return {"success": false, "pending": true, "reason": "Waiting for server"}

@rpc("any_peer", "reliable")
func request_inventory(id: int, action: String, arguments: Dictionary) -> void:
	if not authority() or action not in ["select", "move", "equip", "unequip", "click", "return_cursor", "collect", "quick_transfer", "organize", "recover", "craft", "repair", "grid_resize", "grid_click", "grid_craft", "grid_return"] or JSON.stringify(arguments).length() > 2048:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _peer_keys.has(peer) or id <= int(_command_highwater.get(peer, 0)):
		return
	_command_highwater[peer] = id
	for player in players():
		if player.get_multiplayer_authority() == peer:
			var inventory := player.get_node("Inventory") as Inventory
			var before := inventory.get_snapshot()
			_commands.request(player, action, arguments)
			if not save_inventory(player):
				inventory.load_snapshot(before, true)
			publish_inventory(player)

func save_inventory(player: Node3D) -> bool:
	var peer := player.get_multiplayer_authority()
	var key: String = "host_inventory" if peer == 1 else str(_peer_keys.get(peer, ""))
	if key.is_empty():
		return false
	var before: Dictionary = profiles.get(key, {}).duplicate(true)
	profiles[key] = player_snapshot(player)
	if not persist():
		profiles[key] = before
		return false
	publish_inventory(player)
	return true

func publish_inventory(player: Node3D) -> void:
	var peer := player.get_multiplayer_authority()
	if peer > 1:
		_inventory_revision += 1
		inventory_state.rpc_id(peer, _inventory_revision, (player.get_node("Inventory") as Inventory).get_snapshot())

@rpc("authority", "reliable")
func inventory_state(revision: int, state: Dictionary) -> void:
	if authority() or revision <= _last_inventory_revision:
		return
	_last_inventory_revision = revision
	for player in players(true):
		if player.is_multiplayer_authority():
			(player.get_node("Inventory") as Inventory).load_snapshot(state, true)

func player_snapshot(player: Node3D) -> Dictionary:
	var data := (player.get_node("Inventory") as Inventory).get_snapshot()
	var vitals := player.get_node_or_null("DamageReceiver") as DamageReceiver
	if vitals != null:
		data.creature_vitals = {"health": vitals.health, "dead": bool(player.get_meta("gameplay_disabled", false))}
	return data

func _block_broken(event: Dictionary) -> Dictionary:
	var player := event.get("player") as Node3D
	if not authority() or not networked() or player == null or player.multiplayer != multiplayer:
		return event
	var inventory := player.get_node("Inventory") as Inventory
	if player.get_multiplayer_authority() > 1:
		for stack in event.get("drops", []):
			inventory.grant_item(str(stack.get("item", stack.get("id", ""))), int(stack.get("count", 1)))
	api.item_instances.spend(inventory, inventory.selected_slot)
	save_inventory(player)
	return event

func _before_place(event: Dictionary) -> Dictionary:
	var player := event.get("player") as Node3D
	if authority() and networked() and player != null and player.multiplayer == multiplayer:
		if (player.get_node("Inventory") as Inventory).get_item_count(str(event.item_id)) < 1:
			event.cancelled = true
	return event

func _block_placed(event: Dictionary) -> Dictionary:
	var player := event.get("player") as Node3D
	if authority() and networked() and player != null and player.multiplayer == multiplayer and player.get_multiplayer_authority() > 1:
		(player.get_node("Inventory") as Inventory).remove_item(str(event.item_id), 1)
		save_inventory(player)
	return event
