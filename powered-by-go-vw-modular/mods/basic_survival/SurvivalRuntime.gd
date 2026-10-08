extends Node

var api: ModAPI
var changes = {}
var pending = {}
var cooldowns = {}
var timer = 0.0
var save_path = ""
var _is_authority = true
var _sync_requested = false
var writable = true

func setup(context: ModAPI) -> void:
	api = context
	_is_authority = authority()
	save_path = api.saves.root_path.path_join(api.saves.active_world_id+".farming.json")
	if authority() and FileAccess.file_exists(save_path):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if saved is Dictionary and int(saved.get("version",0)) == 1 and saved.get("cells") is Dictionary:
			changes = saved.cells
		else:
			writable = false
			push_error("Invalid farming save; existing file preserved: "+save_path)
	api.on(GameEvents.AFTER_BLOCK_BREAK,_broken,-300)
	api.on(GameEvents.AFTER_BLOCK_PLACE,_placed,-300)
	api.on(GameEvents.PLAYER_SPAWNED,_joined,-300)

func authority() -> bool:
	if not is_inside_tree(): return _is_authority
	return multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer or multiplayer.is_server()

func networked() -> bool:
	return multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer

func key(pos: Vector3i) -> String:
	return "%d,%d,%d" % [pos.x,pos.y,pos.z]

func position(id: String) -> Vector3i:
	var parts = id.split(",")
	return Vector3i(int(parts[0]),int(parts[1]),int(parts[2]))

func change(pos: Vector3i, id: String) -> bool:
	if not api.world.is_loaded(pos) or not api.world.set_block(pos,id): return false
	changes[key(pos)] = id
	if networked(): apply_cell.rpc(pos,id)
	return true

@rpc("authority","reliable")
func apply_cell(pos: Vector3i, id: String) -> void:
	if not api.world.is_loaded(pos) or not api.world.set_block(pos,id): pending[key(pos)] = id

@rpc("any_peer","reliable")
func request_sync() -> void:
	if authority() and networked(): sync_cells.rpc_id(multiplayer.get_remote_sender_id(),changes)

@rpc("authority","reliable")
func sync_cells(cells: Dictionary) -> void:
	for id in cells: pending[id] = cells[id]

func _joined(event: Dictionary) -> Dictionary:
	if authority() and networked() and event.get("player") is Node:
		var peer = (event.player as Node).get_multiplayer_authority()
		if peer != 1 and peer in multiplayer.get_peers(): sync_cells.rpc_id(peer,changes)
	return event

func use(event: Dictionary) -> bool:
	var id = str(event.get("item_id",""))
	var player = event.get("player") as Node3D
	if player == null: return false
	var props = api.content.get_item(id).get("properties",{}) as Dictionary
	var seeds = seed_map()
	if id != "survival:bow" and str(props.get("tool_type","")) != "hoe" and not seeds.has(id): return false
	var hit: Variant = event.get("hit")
	if id != "survival:bow" and hit == null: return false
	var cell = Vector3i(hit.position) if hit != null else Vector3i.ZERO
	if seeds.has(id) and api.world.get_block_id(cell) != "survival:farmland": return false
	var camera = player.get_node_or_null("Camera3D") as Camera3D
	var direction = -camera.global_basis.z if camera != null else Vector3.FORWARD
	if authority(): perform(player,cell,direction)
	else: request_use.rpc_id(1,cell,direction)
	return true

func seed_map() -> Dictionary:
	return {"survival:wheat_seeds":"wheat","frontier:carrot":"carrots","frontier:potato":"potatoes","survival:beetroot_seeds":"beetroots","survival:pumpkin_seeds":"pumpkin","survival:melon_seeds":"melon"}

@rpc("any_peer","reliable")
func request_use(cell: Vector3i, direction: Vector3) -> void:
	if not authority() or not is_instance_valid(api.entities.runtime): return
	var peer = multiplayer.get_remote_sender_id()
	for player in api.entities.runtime.call("players"):
		if player.get_multiplayer_authority() == peer and bool(player.get_meta("inventory_authority",false)):
			perform(player,cell,direction)
			api.entities.runtime.call("save_inventory",player)
			return

func perform(player: Node3D, cell: Vector3i, direction: Vector3) -> bool:
	if not authority() or bool(player.get_meta("gameplay_disabled",false)): return false
	var inventory = player.get_node_or_null("Inventory") as Inventory
	if inventory == null: return false
	var now = Time.get_ticks_msec()
	var player_key = player.get_instance_id()
	if now < int(cooldowns.get(player_key,0)): return false
	var stack = inventory.get_slot(inventory.selected_slot)
	if stack.is_empty() or not api.item_instances.usable(stack): return false
	var id = str(stack.id)
	if id == "survival:bow":
		if inventory.get_item_count("survival:arrow") < 1 or not direction.is_finite() or direction.length_squared() < 0.5: return false
		var camera = player.get_node_or_null("Camera3D") as Camera3D
		if camera == null: return false
		cooldowns[player_key] = now+600
		inventory.remove_item("survival:arrow",1)
		api.item_instances.spend(inventory,inventory.selected_slot)
		var origin = camera.global_position
		var query = PhysicsRayQueryParameters3D.create(origin,origin+direction.normalized()*32)
		query.exclude = [player.get_rid()]
		var hit = player.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider is Node:
			DamageReceiver.deliver(hit.collider,6,{"source":player,"damage_type":"physical","position":hit.position,"direction":direction.normalized()})
		return true
	if cell.distance_to(Vector3i(player.global_position.floor())) > 5 or not api.world.is_loaded(cell): return false
	var current = api.world.get_block_id(cell)
	var props = api.item_instances.stats(stack)
	if str(props.get("tool_type","")) == "hoe":
		if current not in ["core:dirt","core:grass"] or api.world.get_block_id(cell+Vector3i.UP) != "core:air": return false
		if change(cell,"survival:farmland"):
			api.item_instances.spend(inventory,inventory.selected_slot)
			cooldowns[player_key] = now+200
			return true
	elif seed_map().has(id):
		var destination = cell+Vector3i.UP
		if current != "survival:farmland" or api.world.get_block_id(destination) != "core:air": return false
		if change(destination,"survival:"+str(seed_map()[id])+"_crop_0"):
			inventory.remove_item(id,1)
			cooldowns[player_key] = now+200
			return true
	return false

func _process(delta: float) -> void:
	if not authority() and not _sync_requested and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_sync_requested = true
		request_sync.rpc_id(1)
	for id in pending.keys():
		var pos = position(id)
		if api.world.is_loaded(pos) and api.world.set_block(pos,str(pending[id])): pending.erase(id)
	if not authority(): return
	timer += delta
	if timer < 15: return
	timer = 0
	grow()
	save_state()

func grow() -> void:
	for id in changes.keys():
		var pos = position(id)
		if not api.world.is_loaded(pos): continue
		var block = api.world.get_block_id(pos)
		if not block.contains("_crop_"): continue
		if api.world.get_block_id(pos+Vector3i.DOWN) != "survival:farmland":
			change(pos,"core:air")
			continue
		var crop = block.get_slice("_crop_",0)
		var stage = int(block.get_slice("_crop_",1))
		var last = 7 if crop == "survival:wheat" else 3
		if stage < last: change(pos,crop+"_crop_"+str(stage+1))

func _broken(event: Dictionary) -> Dictionary:
	if authority() and changes.has(key(event.position)): changes[key(event.position)] = "core:air"
	return event

func _placed(event: Dictionary) -> Dictionary:
	if authority() and changes.has(key(event.position)): changes[key(event.position)] = event.block_id
	return event

func save_state() -> void:
	if not authority() or not writable or save_path.is_empty(): return
	var file = FileAccess.open(save_path+".tmp",FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"version":1,"cells":changes}))
		file.close()
		DirAccess.rename_absolute(save_path+".tmp",save_path)

func _exit_tree() -> void:
	if api != null:
		save_state()
		api.off(GameEvents.AFTER_BLOCK_BREAK,_broken)
		api.off(GameEvents.AFTER_BLOCK_PLACE,_placed)
		api.off(GameEvents.PLAYER_SPAWNED,_joined)

