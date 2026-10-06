extends Node

class FakeWorld extends VoxelWorldService:
	var position := Vector3i(1, 1, 1)
	func get_block_id(_pos: Vector3i) -> String:
		return "core:stone"
	func raycast(_origin: Vector3, _direction: Vector3, _distance: float = 10.0):
		return {"position": position, "previous_position": position + Vector3i.UP}

func _ready() -> void:
	var c := GameAPI.content
	assert(not c.get_mining_profile("", "core:stone").allowed)
	assert(not c.get_mining_profile("frontier:wood_axe", "core:stone").allowed)
	# Resolve the mod namespace from registered starter tools.
	var wood := ""
	for id in c.items:
		if str(id).ends_with(":wood_pickaxe"):
			wood = id
	assert(not wood.is_empty())
	var ns := wood.split(":")[0]
	assert(c.get_mining_profile(wood, "core:stone").allowed)
	assert(not c.get_mining_profile(wood, "core:iron_ore").allowed)
	assert(c.get_mining_profile(ns + ":stone_pickaxe", "core:iron_ore").allowed)
	assert(not c.get_mining_profile(ns + ":stone_pickaxe", "core:diamond_ore").allowed)
	assert(c.get_mining_profile(ns + ":bronze_pickaxe", "core:diamond_ore").allowed)
	assert(not c.get_mining_profile(ns + ":murexium_pickaxe", "core:bedrock").allowed)
	assert(not c.get_mining_profile(wood, "core:water").allowed)
	assert(c.get_break_hits(wood, "core:stone") > c.get_break_hits(ns + ":diamond_pickaxe", "core:stone"))
	assert(c.get_mining_profile(wood, "core:stone").interval > c.get_mining_profile(ns + ":diamond_pickaxe", "core:stone").interval)
	assert(c.get_break_hits(ns + ":diamond_shovel", "core:dirt") < c.get_break_hits(wood, "core:dirt"))
	assert(c.get_break_hits(ns + ":wood_axe", "core:log") < c.get_break_hits(wood, "core:log"))
	var original_world := GameAPI.world
	var fake := FakeWorld.new(c)
	GameAPI.world = fake
	var player := CharacterBody3D.new()
	var inv := Inventory.new()
	inv.name = "Inventory"
	player.add_child(inv)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	player.add_child(camera)
	var interactor := VoxelInteractor.new()
	player.add_child(interactor)
	add_child(player)
	inv.add_item(wood, 1)
	inv.assign_to_hotbar(wood, 0)
	inv.set_selected_slot(0)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	interactor._handle_primary_action()
	assert(interactor.breaking_hits == 1)
	assert(interactor.mining_bar.value == 1)
	interactor._handle_primary_action()
	assert(interactor.breaking_hits == 1) # Swing cooldown rejects click spam.
	# Headless DisplayServer cannot capture a mouse. Tick while inactive to
	# verify no automatic mining; restore the clicked target afterwards.
	interactor.breaking_active = false
	interactor._physics_process(1.0)
	assert(interactor.breaking_hits == 1)
	interactor.breaking_active = true
	interactor._handle_primary_action()
	assert(interactor.breaking_hits == 2)
	fake.position += Vector3i.RIGHT
	interactor._physics_process(0.1)
	assert(not interactor.breaking_active)
	assert(not interactor.mining_hud.visible)
	var edits := WorldEditService.new(c, fake, GameAPI.events)
	inv.assign_to_hotbar(ns + ":wood_axe", 0)
	inv.add_item(ns + ":wood_axe", 1)
	inv.assign_to_hotbar(ns + ":wood_axe", 0)
	assert(not edits.break_block(player, fake.position).success)
	GameAPI.world = original_world
	player.queue_free()
	print("Mining smoke passed: tool rules, tiers, speed, discrete hits, HUD and target reset")
	get_tree().quit()
