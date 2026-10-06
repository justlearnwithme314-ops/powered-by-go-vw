extends Node3D

class FakeWorld extends VoxelWorldService:
	var blocks: Dictionary = {}
	func get_block_id(pos: Vector3i) -> String:
		return str(blocks.get(pos, "core:air"))

var entities: BlockEntityService
var inventory: Inventory
var player: CharacterBody3D
var commands: InventoryCommandService
var runtime: Node
var world: FakeWorld

func _ready() -> void:
	world = FakeWorld.new(GameAPI.content)
	entities = BlockEntityService.new(GameAPI.content, world)
	entities.register_kind("survival:workbench", ["workbench"], {})
	entities.register_kind("survival:furnace", ["furnace"], {"input": 4, "fuel": 1, "output": 1})
	var recipes := CraftingService.new(GameAPI.content, GameAPI.events)
	recipes.stations = entities
	commands = InventoryCommandService.new(entities, recipes)
	var path := "user://crafting_station_tests/%d.entities.json" % Time.get_ticks_usec()
	assert(entities.activate(path))
	player = CharacterBody3D.new()
	inventory = Inventory.new()
	inventory.name = "Inventory"
	player.add_child(inventory)
	add_child(player)
	entities.bind_inventory(inventory)
	# Empty-start hand progression and workbench enforcement.
	assert(inventory.items.is_empty())
	inventory.add_item("core:log", 5)
	assert(commands.request(player, "craft", {"recipe_id": "survival:planks"}).success)
	assert(inventory.get_item_count("survival:planks") == 4)
	assert(commands.request(player, "craft", {"recipe_id": "survival:workbench"}).success)
	inventory.add_item("core:stick", 3)
	inventory.add_item("survival:planks",3)
	assert(not recipes.craft(player, inventory, "frontier:wood_pickaxe").success)
	world.blocks[Vector3i.ZERO] = "survival:workbench"
	# Terrain stations grant recipes even before a persistent record is created.
	assert(recipes.can_craft(inventory, "frontier:wood_pickaxe"))
	player.position = Vector3(3.6, 0, 0)
	assert(not recipes.can_craft(inventory, "frontier:wood_pickaxe"))
	player.position = Vector3.ZERO
	var bench := entities.ensure(Vector3i.ZERO)
	assert(not bench.is_empty())
	assert(recipes.can_craft(inventory, "frontier:wood_pickaxe"))
	assert(commands.request(player, "craft", {"recipe_id": "frontier:wood_pickaxe"}).success)
	player.position = Vector3(20, 0, 0)
	assert(not recipes.can_craft(inventory, "frontier:wood_shovel"))
	player.position = Vector3.ZERO
	# Atomic fuel processing and correctly typed station slots.
	var furnace_pos := Vector3i(2, 0, 0)
	world.blocks[furnace_pos] = "survival:furnace"
	var furnace := entities.ensure(furnace_pos)
	var api := ModAPI.new(GameAPI.content, GameAPI.events, GameAPI.world_generation, world, GameAPI.edits, recipes)
	api.stations = entities
	api.inventory_commands = commands
	api.root_path = "res://mods/crafting_progression"
	runtime = load("res://mods/crafting_progression/StationRuntime.gd").new()
	add_child(runtime)
	runtime.setup(api)
	runtime.set_process(false)
	runtime.tick_furnace(furnace, 0.0)
	var input := entities.container(furnace, "input")
	var fuel := entities.container(furnace, "fuel")
	var output := entities.container(furnace, "output")
	assert(int(fuel.insert({"id": "core:stone", "count": 1}).added) == 0)
	assert(int(input.insert({"id": "core:stick", "count": 1}).added) == 0)
	input.insert({"id": "frontier:iron_lump", "count": 3})
	runtime.tick_furnace(furnace, 8.0)
	assert(input.count("frontier:iron_lump") == 3 and output.count("frontier:iron_ingot") == 0)
	fuel.insert({"id": "core:log", "count": 2})
	runtime.tick_furnace(furnace, 3.0)
	assert(is_equal_approx(float(entities.record(furnace).state.progress), 3.0))
	assert(fuel.count("core:log") == 1)
	assert(entities.save())
	var saved_text := FileAccess.get_file_as_string(path)
	# Reload binds the matching inventory and furnace progress from ONE snapshot.
	assert(entities.activate(path))
	entities.bind_inventory(inventory)
	input = entities.container(furnace, "input")
	fuel = entities.container(furnace, "fuel")
	output = entities.container(furnace, "output")
	assert(is_equal_approx(float(entities.record(furnace).state.progress), 3.0))
	runtime.tick_furnace(furnace, 5.0)
	assert(output.count("frontier:iron_ingot") == 1 and input.count("frontier:iron_lump") == 2)
	assert(not recipes.craft(player, inventory, "frontier:iron_ingot").success)
	# Full output retains input and consumes no NEW fuel; existing fire burns.
	output.take(0, 64)
	output.insert({"id": "frontier:iron_ingot", "count": 64})
	var old_fuel := fuel.count("core:log")
	runtime.tick_furnace(furnace, 20.0)
	assert(input.count("frontier:iron_lump") == 2 and fuel.count("core:log") == old_fuel)
	assert(entities.record(furnace).state.status == "Output full")
	output.take(0, 64)
	runtime.tick_furnace(furnace, 8.0)
	assert(output.count("frontier:iron_ingot") == 1)
	# A transfer commits both containers before observers fire and cannot replay.
	var slot := 0
	while slot < Inventory.CAPACITY and not inventory.get_slot(slot).is_empty():
		slot += 1
	var request := {"action": "station_transfer", "request_id": 100, "revisions": commands.revisions(inventory), "station": furnace, "container": "output", "station_revision": output.revision, "into": false, "from": 0, "to": slot, "amount": 1}
	assert(commands.execute(player, request).success)
	assert(commands.execute(player, request).success)
	assert(inventory.get_item_count("frontier:iron_ingot") == 1 and output.count("frontier:iron_ingot") == 0)
	var altered := request.duplicate(true)
	altered.amount = 2
	assert(not commands.execute(player, altered).success)
	assert(not commands.request(player, "station_transfer", {"station": furnace, "container": "output", "station_revision": output.revision, "into": true, "from": slot, "to": 0}).success)
	# Removed/distant stations cannot be accessed even through an already open UI.
	for fixture in [
		{"ingredients":{"frontier:copper_lump":1}, "output":"frontier:copper_ingot", "count":1},
		{"ingredients":{"frontier:iron_lump":1}, "output":"frontier:iron_ingot", "count":1},
		{"ingredients":{"frontier:copper_lump":2,"frontier:tin_lump":1}, "output":"frontier:bronze_ingot", "count":3},
		{"ingredients":{"frontier:iron_lump":2,"frontier:coal_lump":1}, "output":"frontier:steel_ingot", "count":2}]:
		for i in range(input.size()):
			input.take(i, 2147483647)
		output.take(0,2147483647)
		fuel.take(0,2147483647)
		entities.update_state(furnace,{})
		for ingredient in fixture.ingredients:
			assert(input.insert({"id":ingredient,"count":fixture.ingredients[ingredient]}).added > 0)
		fuel.insert({"id":"core:log","count":1})
		runtime.tick_furnace(furnace,8.0)
		assert(output.count(fixture.output) == fixture.count, "Alloy recipe must win over individual ingots")
	player.position = Vector3(50, 0, 0)
	assert(not entities.accessible(player, furnace))
	player.position = Vector3.ZERO
	world.blocks[furnace_pos] = "core:air"
	assert(not entities.accessible(player, furnace))
	world.blocks[furnace_pos] = "survival:furnace"
	# Broken stations transfer contents once and cancel later processing.
	var contents := entities.remove(furnace)
	assert(not contents.is_empty() and entities.remove(furnace).is_empty())
	runtime.tick_furnace(furnace, 20.0)
	assert(entities.record(furnace).is_empty())
	# Restore the saved fixture for native UI verification.
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(saved_text)
	file.close()
	assert(entities.activate(path))
	entities.bind_inventory(inventory)
	runtime.open_station(player, furnace)
	assert(runtime._ui != null)
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://tests/furnace-ui-preview.png")
	runtime._ui.close()
	entities.activate("")
	player.queue_free()
	runtime.queue_free()
	print("Crafting stations PASS: empty-start progression, station gates/reach, fuel/input filters, atomic smelting, combined reload, full output, replay protection, destruction and UI")
	get_tree().quit()
