extends Node3D

class World extends VoxelWorldService:
	var blocks := {}
	func get_block_id(pos: Vector3i) -> String:
		return str(blocks.get(pos,"core:air"))

func put(grid: SlotContainer, index: int, stack: Dictionary) -> void:
	var source := SlotContainer.new(GameAPI.content,1)
	source.insert(stack)
	assert(source.transfer_to(grid,0,index).success)

func _ready() -> void:
	var world := World.new(GameAPI.content)
	var stations := BlockEntityService.new(GameAPI.content,world)
	stations.register_kind("survival:workbench",["workbench"],{})
	stations.register_kind("survival:furnace",["furnace"],{})
	var api := ModAPI.new(GameAPI.content,EventBus.new(),GameAPI.world_generation,world,GameAPI.edits,GameAPI.crafting)
	api.stations = stations
	api.item_instances = GameAPI.item_instances
	var service := load("res://mods/shaped_crafting/GridCrafting.gd").new() as RefCounted
	service.setup(api)
	var player := CharacterBody3D.new()
	player.name = "1"
	add_child(player)
	var inventory := Inventory.new()
	player.add_child(inventory)
	assert(service.dimensions(player) == Vector2i(2,2))
	for i in range(4):
		put(inventory.crafting_grid,i,{"id":"survival:planks","count":2})
	assert("survival:workbench" in service.matches(inventory))
	assert(service.command(player,inventory,"grid_craft",{"recipe_id":"survival:workbench"}).success)
	assert(inventory.get_item_count("survival:workbench") == 1)
	assert(inventory.crafting_grid.stack_at(0).count == 1)
	service.command(player,inventory,"grid_return",{})
	assert(inventory.get_item_count("survival:planks") == 4)
	# Different plank species may share one recipe without becoming one item.
	var plank_types := ["survival:planks", "frontier:dark_plank", "frontier:cherry_plank", "frontier:ebony_plank"]
	for i in range(4):
		assert("core:planks" in GameAPI.content.get_block(plank_types[i]).tags)
		put(inventory.crafting_grid,i,{"id":plank_types[i],"count":1})
	assert("survival:workbench" in service.matches(inventory))
	assert(service.command(player,inventory,"grid_craft",{"recipe_id":"survival:workbench"}).success)
	assert(inventory.get_item_count("survival:workbench") == 2)
	for i in range(4): assert(inventory.crafting_grid.stack_at(i).is_empty())
	put(inventory.crafting_grid,0,{"id":"core:log","count":1})
	put(inventory.crafting_grid,2,{"id":"frontier:weathered_plank","count":1})
	assert("survival:sticks" not in service.matches(inventory))
	service.return_grid(inventory)
	put(inventory.crafting_grid,0,{"id":"frontier:dark_plank","count":1})
	put(inventory.crafting_grid,2,{"id":"frontier:weathered_plank","count":1})
	assert("survival:sticks" in service.matches(inventory))
	assert(service.command(player,inventory,"grid_craft",{"recipe_id":"survival:sticks"}).success)
	assert(inventory.get_item_count("core:stick") == 4)
	# The non-grid crafting service must consume actual tagged inventory items.
	inventory.add_item("frontier:dark_plank",1)
	inventory.add_item("frontier:weathered_plank",1)
	var plank_count := inventory.get_item_count("survival:planks") + inventory.get_item_count("frontier:dark_plank") + inventory.get_item_count("frontier:weathered_plank")
	assert(GameAPI.crafting.craft(player,inventory,"survival:sticks").success)
	assert(inventory.get_item_count("survival:planks") + inventory.get_item_count("frontier:dark_plank") + inventory.get_item_count("frontier:weathered_plank") == plank_count - 2)
	# Overlapping exact/tag requirements must allocate distinct units.
	var allocated := GameAPI.content.resolve_ingredients({"#core:planks":1,"survival:planks":1},{"survival:planks":1,"frontier:dark_plank":1})
	assert(allocated.success and allocated.items.size() == 2)
	assert(not GameAPI.content.resolve_ingredients({"#core:planks":1,"survival:planks":1},{"survival:planks":1}).success)
	var registry := ContentRegistry.new()
	assert(registry.register_item({"id":"test:plank","tags":["test:planks"]}))
	assert(registry.register_item({"id":"test:output"}))
	assert(registry.register_recipe("test:tag_recipe","test:output",1,{"#test:planks":2}))
	world.blocks[Vector3i.ZERO] = "survival:workbench"
	service.command(player,inventory,"grid_resize",{})
	assert(inventory.crafting_width == 3)
	for i in [0,1,2]: put(inventory.crafting_grid,i,{"id":plank_types[i+1],"count":1})
	for i in [4,7]: put(inventory.crafting_grid,i,{"id":"core:stick","count":1})
	assert("frontier:wood_pickaxe" in service.matches(inventory))
	inventory.crafting_grid.transfer_to(inventory.crafting_grid,7,8)
	assert("frontier:wood_pickaxe" not in service.matches(inventory))
	inventory.crafting_grid.transfer_to(inventory.crafting_grid,8,7)
	assert(service.command(player,inventory,"grid_craft",{"recipe_id":"frontier:wood_pickaxe"}).success)
	assert(inventory.get_item_count("frontier:wood_pickaxe") == 1)
	world.blocks[Vector3i.RIGHT] = "survival:workbench"
	assert(service.dimensions(player) == Vector2i(6,3))
	world.blocks[Vector3i.BACK] = "survival:workbench"
	world.blocks[Vector3i.RIGHT+Vector3i.BACK] = "survival:workbench"
	assert(service.dimensions(player) == Vector2i(6,6))
	service.command(player,inventory,"grid_resize",{})
	assert(inventory.crafting_grid.size() == 36)
	# A recipe can use the lower half of a square table arrangement.
	for i in [19,20,21]: put(inventory.crafting_grid,i,{"id":"core:stone","count":1})
	for i in [26,32]: put(inventory.crafting_grid,i,{"id":"core:stick","count":1})
	assert("frontier:stone_pickaxe" in service.matches(inventory))
	assert(service.command(player,inventory,"grid_craft",{"recipe_id":"frontier:stone_pickaxe"}).success)
	world.blocks.erase(Vector3i.RIGHT)
	world.blocks.erase(Vector3i.RIGHT+Vector3i.BACK)
	assert(service.dimensions(player) == Vector2i(6,3))
	world.blocks[Vector3i.UP] = "survival:workbench"
	assert(service.dimensions(player) == Vector2i(6,3))
	world.blocks.erase(Vector3i.UP)
	world.blocks.erase(Vector3i.BACK)
	for i in range(1,5): world.blocks[Vector3i(i,0,0)] = "survival:workbench"
	assert(service.dimensions(player) == Vector2i(15,3))
	service.command(player,inventory,"grid_resize",{})
	assert(inventory.crafting_grid.size() == 45)
	# Shapes translate freely within the expanded grid.
	for i in [10,11,12]: put(inventory.crafting_grid,i,{"id":"core:stone","count":1})
	for i in [26,41]: put(inventory.crafting_grid,i,{"id":"core:stick","count":1})
	assert("frontier:stone_pickaxe" in service.matches(inventory))
	var saved := inventory.get_snapshot()
	inventory.load_snapshot(saved,true)
	assert(inventory.crafting_width == 15 and "frontier:stone_pickaxe" in service.matches(inventory))
	player.position = Vector3(30,0,0)
	assert(not service.command(player,inventory,"grid_craft",{"recipe_id":"frontier:stone_pickaxe"}).success)
	service.command(player,inventory,"grid_resize",{})
	assert(inventory.crafting_width == 2 and inventory.get_item_count("core:stone") == 3)
	assert(GameAPI.content.get_recipe("frontier:iron_ingot").method == "smelt")
	print("Shaped crafting PASS: hand/workbench patterns, wrong layout rejection, expansion, translation, crafting, recovery, saved grid and furnace method")
	get_tree().quit()
