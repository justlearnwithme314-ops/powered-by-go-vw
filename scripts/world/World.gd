extends Node3D

const BLOCK_SCENE := preload("res://scenes/block/block.tscn")

var blocks: Dictionary = {}


func _ready() -> void:
	add_to_group("world")

func _spawn_test_blocks() -> void:
	for x in range(-2, 3):
		for z in range(-2, 3):
			_spawn_block(Vector3i(x, 1, z))


func _block_key(pos: Vector3i) -> String:
	return "%d_%d_%d" % [pos.x, pos.y, pos.z]


func has_block(pos: Vector3i) -> bool:
	return blocks.has(_block_key(pos))


# =====================================================
# INTERNAL FUNCTIONS
# =====================================================

func _spawn_block(pos: Vector3i) -> void:
	var key := _block_key(pos)

	if blocks.has(key):
		return

	var block = BLOCK_SCENE.instantiate()
	block.name = key
	block.position = Vector3(pos)

	add_child(block)

	blocks[key] = block


func _remove_block(pos: Vector3i) -> void:
	var key := _block_key(pos)

	if !blocks.has(key):
		return

	var block = blocks[key]

	if is_instance_valid(block):
		block.queue_free()

	blocks.erase(key)


# =====================================================
# CLIENT FUNCTIONS
# =====================================================

func break_block(pos: Vector3i) -> void:
	request_break_block.rpc_id(1, pos)


func place_block(pos: Vector3i) -> void:
	request_place_block.rpc_id(1, pos)


# =====================================================
# SERVER RPCs
# =====================================================

@rpc("any_peer", "reliable")
func request_break_block(pos: Vector3i) -> void:

	if !multiplayer.is_server():
		return

	_remove_block(pos)

	update_break_block.rpc(pos)


@rpc("any_peer", "reliable")
func request_place_block(pos: Vector3i) -> void:

	if !multiplayer.is_server():
		return

	_spawn_block(pos)

	update_place_block.rpc(pos)


# =====================================================
# CLIENT UPDATES
# =====================================================

@rpc("authority", "call_local", "reliable")
func update_break_block(pos: Vector3i) -> void:
	_remove_block(pos)


@rpc("authority", "call_local", "reliable")
func update_place_block(pos: Vector3i) -> void:
	_spawn_block(pos)
func sync_world_to(peer_id: int) -> void:
	for key in blocks.keys():
		var block = blocks[key]
		update_place_block.rpc_id(peer_id, Vector3i(block.position))
func generate_world():
	_spawn_test_blocks()
