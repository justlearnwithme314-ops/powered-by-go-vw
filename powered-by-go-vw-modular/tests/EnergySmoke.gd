extends Node

class FakeWorld extends VoxelWorldService:
	var blocks: Dictionary = {}
	var unloaded: Dictionary = {}
	func is_ready() -> bool:
		return true
	func is_loaded(position: Vector3i) -> bool:
		return not bool(unloaded.get(position, false))
	func get_block_id(position: Vector3i) -> String:
		return str(blocks.get(position, "core:air"))

func _register_block(registry: ContentRegistry, id: String) -> void:
	assert(registry.register_block({"id": id, "model": VoxelBlockyModelCube.new(), "tags": ["block", "test"]}) >= 0)

func _ready() -> void:
	var content := ContentRegistry.new()
	for id in ["test:consumer", "test:storage", "test:cable", "test:side_cable"]:
		_register_block(content, id)
	var world := FakeWorld.new(content)
	var stations := BlockEntityService.new(content, world)
	var path := "user://energy_tests/%d.entities.json" % Time.get_ticks_usec()
	assert(stations.activate(path))
	var energy := EnergyService.new(content, stations, world)
	var all_faces := [0, 1, 2, 3, 4, 5]
	assert(energy.register({"block_id": "test:consumer", "role": "consumer", "capacity": 100, "transfer_limit": 20, "faces": all_faces}))
	assert(energy.register({"block_id": "test:storage", "role": "storage", "capacity": 100, "transfer_limit": 20, "faces": all_faces}))
	assert(energy.register({"block_id": "test:cable", "role": "cable", "capacity": 0, "transfer_limit": 100, "faces": all_faces}))
	assert(energy.register({"block_id": "test:side_cable", "role": "cable", "capacity": 0, "transfer_limit": 100, "faces": [4, 5]}))
	assert(not energy.register({"block_id": "test:side_cable", "role": "cable", "capacity": 0, "transfer_limit": 100, "faces": [6]}))
	assert(not energy.register({"block_id": "test:cable", "role": "cable", "capacity": 0, "transfer_limit": 100, "faces": all_faces}))

	var consumer_pos := Vector3i.ZERO
	var cable_pos := Vector3i.RIGHT
	var storage_pos := Vector3i.RIGHT * 2
	world.blocks[consumer_pos] = "test:consumer"
	world.blocks[cable_pos] = "test:cable"
	world.blocks[storage_pos] = "test:storage"
	var building := energy.network_for(consumer_pos)
	assert(building.status == "rebuilding")
	for _slice in range(12):
		assert(energy.advance_rebuilds(64) <= 64)
	var network := energy.network_for(consumer_pos)
	assert(network.status == "ready" and network.complete)
	assert(int(network.size) == 3 and network.devices.size() == 2)
	assert(energy.network_for(storage_pos).id == network.id)

	assert(energy.deposit(storage_pos, 75) == 75)
	assert(energy.stored(storage_pos) == 75)
	assert(energy.deposit(storage_pos, 50) == 25)
	assert(energy.stored(storage_pos) == 100)
	assert(energy.consume(storage_pos, 60))
	assert(energy.stored(storage_pos) == 40)
	assert(not energy.consume(storage_pos, 50))
	assert(energy.stored(storage_pos) == 40)
	assert(energy.deposit(cable_pos, 5) == 0)

	world.blocks[cable_pos] = "core:air"
	energy.mark_dirty()
	assert(energy.network_for(consumer_pos).status == "rebuilding")
	for _slice in range(4):
		energy.advance_rebuilds(64)
	assert(energy.network_for(consumer_pos).status == "disconnected")

	var incompatible_device := Vector3i(10, 0, 0)
	var incompatible_cable := incompatible_device + Vector3i.RIGHT
	world.blocks[incompatible_device] = "test:consumer"
	world.blocks[incompatible_cable] = "test:side_cable"
	energy.mark_dirty()
	energy.network_for(incompatible_device)
	for _slice in range(4):
		energy.advance_rebuilds(64)
	var incompatible := energy.network_for(incompatible_device)
	assert(incompatible.status == "disconnected" and incompatible.reason == "no_cable_connection")

	var unloaded_device := Vector3i(20, 0, 0)
	world.blocks[unloaded_device] = "test:consumer"
	world.blocks[unloaded_device + Vector3i.RIGHT] = "test:cable"
	world.blocks[unloaded_device + Vector3i.RIGHT * 2] = "test:storage"
	world.unloaded[unloaded_device + Vector3i.RIGHT + Vector3i.UP] = true
	energy.notify_loaded_state_changed()
	energy.network_for(unloaded_device)
	for _slice in range(4):
		energy.advance_rebuilds(64)
	var unloaded_network := energy.network_for(unloaded_device)
	assert(unloaded_network.status == "incomplete" and unloaded_network.reason == "unloaded")
	assert(int(unloaded_network.size) == 3)

	var long_start := Vector3i(1000, 0, 0)
	for i in range(EnergyService.MAX_NETWORK_CELLS + 1):
		world.blocks[long_start + Vector3i(i, 0, 0)] = "test:cable"
	energy.mark_dirty()
	energy.network_for(long_start)
	for _slice in range(600):
		energy.advance_rebuilds(64)
	var bounded := energy.network_for(long_start)
	assert(bounded.status == "incomplete" and bounded.reason == "cell_limit")
	assert(int(bounded.size) <= EnergyService.MAX_NETWORK_CELLS)

	assert(stations.save())
	assert(stations.activate(path))
	assert(energy.stored(storage_pos) == 40)
	stations.activate("")
	print("Energy smoke passed: validated roles, deterministic six-face graph, local storage, invalidation, unloaded/cell bounds and save/reload")
	get_tree().quit()
