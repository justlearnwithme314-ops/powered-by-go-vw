extends Node3D

class FakeWorld extends VoxelWorldService:
	var blocks: Dictionary = {}
	func get_block_id(pos: Vector3i) -> String:
		return str(blocks.get(pos, "core:air"))

func _ready() -> void:
	var content := ContentRegistry.new()
	assert(content.register_block({"id": "test:machine", "model": VoxelBlockyModelCube.new(), "tags": ["block", "machine"]}) >= 0)
	assert(content.register_item({"id": "test:ore", "stack_size": 64, "tags": ["ore"]}))
	assert(content.register_item({"id": "test:catalyst", "stack_size": 64, "tags": ["catalyst"]}))
	assert(content.register_item({"id": "test:ingot", "stack_size": 64}))
	assert(content.register_item({"id": "test:alloy", "stack_size": 64}))
	assert(content.register_recipe("test:smelt_like_recipe", "test:ingot", 2, {"#ore": 1}, {"method": "crush", "duration": 1.0}))
	assert(content.register_recipe("test:alloy_recipe", "test:alloy", 1, {"#ore": 1, "#catalyst": 1}, {"method": "crush", "duration": 2.0}))
	assert(content.register_recipe("test:hand_recipe", "test:ingot", 1, {"#ore": 1}, {"method": "craft"}))

	var world := FakeWorld.new(content)
	var stations := BlockEntityService.new(content, world)
	var save_path := "user://machine_tests/%d.entities.json" % Time.get_ticks_usec()
	assert(stations.activate(save_path))
	var machines := MachineRegistry.new(content, stations)
	var definition := {"block_id": "test:machine", "capabilities": ["crusher"], "slots": {"input": 4, "output": 2}, "method": "crush", "duration_scale": 1.0, "energy_per_second": 0.0, "feature": "industry:machines"}
	assert(machines.register(definition))
	assert(not machines.register(definition))
	assert(not machines.register({"block_id": "test:machine", "slots": {"input": 1, "output": 1}, "method": "crush", "duration_scale": 0.0}))
	assert(machines.definition("test:machine").slots.input == 4)

	var events := EventBus.new()
	var api := ModAPI.new(content, events, null, world, null, null)
	api.stations = stations
	api.machines = machines
	api.profile = WorldProfileService.new()
	api.profile.activate({"feature_flags": {"industry:machines": true}})
	var runtime: Node = load("res://mods/machines/MachineRuntime.gd").new()
	add_child(runtime)
	runtime.call("setup", api)
	var pos := Vector3i.ZERO
	world.blocks[pos] = "test:machine"
	var id := stations.ensure(pos)
	assert(not id.is_empty())
	var input := stations.container(id, "input")
	var output := stations.container(id, "output")
	stations.update_state(id, {"custom_marker": "preserve"})

	input.insert({"id": "test:ore", "count": 1})
	assert(runtime.call("tick_record", id, 0.5))
	var state: Dictionary = stations.record(id).state.machine
	assert(is_equal_approx(float(state.progress_seconds), 0.5))
	input.insert({"id": "test:catalyst", "count": 1})
	runtime.call("tick_record", id, 0.25)
	state = stations.record(id).state.machine
	assert(state.recipe == "test:alloy_recipe")
	assert(is_equal_approx(float(state.progress_seconds), 0.25), "Input changes must reset the prior recipe progress")
	runtime.call("tick_record", id, 1.75)
	assert(output.count("test:alloy") == 1)
	assert(input.count("test:ore") == 0)
	assert(input.count("test:catalyst") == 0)
	assert(str(stations.record(id).state.custom_marker) == "preserve")
	assert(stations.activate(save_path), "Machine state and containers should reload")
	input = stations.container(id, "input")
	output = stations.container(id, "output")
	assert(output.count("test:alloy") == 1)
	assert(str(stations.record(id).state.custom_marker) == "preserve")

	input.insert({"id": "test:ore", "count": 2})
	runtime.call("tick_record", id, 2.0)
	assert(output.count("test:ingot") == 4, "The generic runtime should carry time across bounded completions")
	assert(input.count("test:ore") == 0)
	assert(not content.get_recipe("test:hand_recipe").is_empty())
	output.restore([{"id": "test:alloy", "count": 64}, {"id": "test:ingot", "count": 64}])
	input.insert({"id": "test:ore", "count": 1})
	runtime.call("tick_record", id, 1.0)
	assert(input.count("test:ore") == 1)
	assert(str(stations.record(id).state.machine.status) == "Output full")

	var furnace := "1,0,0"
	stations.register_kind("survival:furnace", ["furnace"], {"input": 4, "output": 1, "fuel": 1})
	stations._create(Vector3i(1, 0, 0), "survival:furnace")
	assert(not runtime.call("tick_record", furnace, 10.0), "Generic machines must never process the legacy furnace")

	var disabled := WorldProfileService.new()
	disabled.activate({})
	api.profile = disabled
	assert(not runtime.call("tick_record", id, 1.0))
	assert(input.count("test:ore") == 1, "Disabled experimental machines must not consume inputs")

	api.profile.activate({"feature_flags": {"industry:machines": true}})
	output.restore([])
	var before_input := input.snapshot()
	var before_output := output.snapshot()
	var before_machine_state: Dictionary = stations.record(id).state
	stations.path = ""
	runtime.call("tick_record", id, 1.0)
	assert(input.snapshot() == before_input, "Failed persistence must roll back consumed input")
	assert(output.snapshot() == before_output, "Failed persistence must roll back machine output")
	assert(stations.record(id).state == before_machine_state, "Failed persistence must roll back machine progress")

	stations.activate("")
	runtime.queue_free()
	print("Machine smoke passed: registry validation, recipe priority, tag matching, progress reset, bounded completion, feature gate and furnace isolation")
	get_tree().quit()
