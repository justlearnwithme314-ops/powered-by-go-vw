extends Node3D

class FakeWorld extends VoxelWorldService:
	var target := Vector3i.ZERO
	func get_block_id(_pos: Vector3i) -> String:
		return "core:stone"
	func raycast(_origin: Vector3, _direction: Vector3, _distance: float = 10.0):
		return {"position": target, "previous_position": target + Vector3i.UP}

class FakeSession extends Node:
	signal edit_result(request_id: int, action: String, result: Dictionary)
	var places := 0
	var breaks := 0
	var pending := false
	func submit_block_place(_pos: Vector3i, _item: String) -> Dictionary:
		places += 1
		return {"pending": true, "request_id": 77} if pending else {"success": true, "block_id": "core:dirt"}
	func submit_block_break(_pos: Vector3i) -> Dictionary:
		breaks += 1
		return {"success": true, "block_id": "core:stone", "drops": []}
	func can_place_block(_pos: Vector3i, _player: Node) -> bool:
		return true

class FakeVisual extends PlayerVisual:
	var swings := 0
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func play_interaction_swing() -> void:
		swings += 1

func _ready() -> void:
	var original_world := GameAPI.world
	var original_session := GameAPI.session
	var world := FakeWorld.new(GameAPI.content)
	var session := FakeSession.new()
	GameAPI.world = world
	GameAPI.session = session
	var player := CharacterBody3D.new()
	var inventory := Inventory.new()
	inventory.name = "Inventory"
	player.add_child(inventory)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	player.add_child(camera)
	var visual := FakeVisual.new()
	visual.name = "PlayerVisual"
	var body := Node3D.new()
	body.name = "Body"
	visual.add_child(body)
	player.add_child(visual)
	var interactor := VoxelInteractor.new()
	interactor.name = "VoxelInteractor"
	player.add_child(interactor)
	add_child(player)
	interactor.set_physics_process(false)
	var tool := ""
	for id in GameAPI.content.items:
		if str(id).ends_with(":wood_pickaxe"):
			tool = str(id)
	inventory.add_item(tool, 1)
	inventory.assign_to_hotbar(tool, 0)
	inventory.set_selected_slot(0)
	var api := ModAPI.new(GameAPI.content, GameAPI.events, GameAPI.world_generation, world, GameAPI.edits, GameAPI.crafting)
	api.root_path = "res://mods/block_feedback"
	var feedback_mod = load("res://mods/block_feedback/mod.gd").new()
	feedback_mod.register(api)
	feedback_mod._spawned({"player": player})
	var feedback: Node3D = player.get_node("BlockFeedback")
	assert(feedback != null)
	for ratio in [0.0, 0.01, 0.2, 0.4, 0.6, 0.8, 1.0]:
		var stage: int = feedback.stage_for_progress(ratio)
		assert(stage >= 0 and stage <= 7)
	assert(feedback.stage_for_progress(0.0) == 0 and feedback.stage_for_progress(1.0) == 7)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	interactor._unhandled_input(press)
	assert(interactor.breaking_hits == 1 and visual.swings == 1)
	assert(feedback.overlay.visible)
	assert(feedback.overlay.global_position == Vector3.ONE * 0.5)
	var required := GameAPI.content.get_break_hits(tool, "core:stone")
	assert(feedback.material.albedo_texture == feedback.frames[feedback.stage_for_progress(1.0 / required)])
	assert(feedback.get_child(feedback.get_child_count() - 1) is AudioStreamPlayer3D)
	interactor._physics_process(0.01)
	assert(interactor.breaking_hits == 1 and visual.swings == 1)
	interactor._physics_process(0.5)
	assert(interactor.breaking_hits == 2 and visual.swings == 2)
	press.pressed = false
	interactor._unhandled_input(press)
	interactor._physics_process(0.5)
	assert(interactor.breaking_hits == 2 and visual.swings == 2)
	world.target += Vector3i.RIGHT
	interactor._physics_process(0.01)
	assert(not feedback.overlay.visible)
	# Cancelled hits never increase the displayed damage.
	GameAPI.events.subscribe(GameEvents.BLOCK_HIT, _cancel_hit)
	interactor._handle_primary_action()
	assert(interactor.breaking_hits == 0 and not feedback.overlay.visible)
	GameAPI.events.unsubscribe(GameEvents.BLOCK_HIT, _cancel_hit)
	inventory.add_item("core:dirt", 8)
	inventory.assign_to_hotbar("core:dirt", 1)
	inventory.set_selected_slot(1)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	interactor._unhandled_input(right)
	assert(session.places == 1 and inventory.get_item_count("core:dirt") == 7)
	interactor._handle_secondary_action()
	assert(session.places == 1)
	interactor._physics_process(0.1)
	assert(session.places == 1)
	interactor._physics_process(0.11)
	assert(session.places == 2 and inventory.get_item_count("core:dirt") == 6)
	right.pressed = false
	interactor._unhandled_input(right)
	interactor._physics_process(0.3)
	assert(session.places == 2)
	# Pending network placements neither repeat nor consume inventory before acknowledgement.
	session.pending = true
	interactor._handle_secondary_action()
	interactor._physics_process(0.3)
	interactor._handle_secondary_action()
	assert(session.places == 3 and inventory.get_item_count("core:dirt") == 6)
	session.edit_result.emit(77, "place", {"success": true, "block_id": "core:dirt"})
	assert(inventory.get_item_count("core:dirt") == 5)
	session.edit_result.emit(77, "place", {"success": true, "block_id": "core:dirt"})
	assert(inventory.get_item_count("core:dirt") == 5)
	assert(feedback._sounds.stone is AudioStream and feedback._sounds.wood is AudioStream and feedback._sounds.earth is AudioStream)
	inventory.set_selected_slot(0)
	for hit in range(required):
		interactor.hit_cooldown = 0.0
		interactor._handle_primary_action()
	assert(session.breaks == 1 and not interactor.breaking_active and not feedback.overlay.visible)
	# Losing mouse capture cancels held actions and damage.
	interactor.primary_held = true
	interactor.secondary_held = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	interactor._physics_process(1.0)
	assert(not interactor.primary_held and not interactor.secondary_held)
	# Capture a representative cracked block through the real rendering pipeline.
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color(0.65, 0.56, 0.4)
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cube.material_override = surface
	add_child(cube)
	cube.position = Vector3.ONE * 0.5
	feedback._progress(Vector3i.ZERO, 0.7)
	assert(feedback.overlay.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 36)
	camera.global_position = Vector3(2.6, 2.3, 3.6)
	camera.look_at(Vector3.ONE * 0.5)
	camera.current = true
	interactor._reset_breaking()
	assert(not feedback.overlay.visible)
	feedback._progress(Vector3i.ZERO, 0.7)
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://tests/block-feedback-preview.png")
	GameAPI.world = original_world
	player.free()
	GameAPI.session = original_session
	session.free()
	print("Block feedback PASS: held swings/hits, release, tool rules, 0.2s placement, network acknowledgements, crack stages/reset/UVs, sound assets")
	get_tree().quit()

func _cancel_hit(event: Dictionary) -> Dictionary:
	event.cancelled = true
	return event
