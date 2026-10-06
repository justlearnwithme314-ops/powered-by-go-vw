extends Node

func _ready() -> void:
	GameAPI.saves.root_path = "user://creature_world_tests/%d" % Time.get_ticks_usec()
	GameAPI.saves.legacy_state_path = GameAPI.saves.root_path.path_join("legacy.json")
	var created := GameAPI.saves.create_world("Creature fixture", "53", {"api_version": 1, "mods": GameAPI.mods.get_signature(), "content": GameAPI.content.get_content_signature()})
	assert(created.success)
	assert(GameAPI.saves.select_world(created.save_name).valid)
	var game := load("res://scenes/main/Game.tscn").instantiate() as Node3D
	add_child(game)
	for frame in range(12):
		await get_tree().process_frame
	var player := game.get_node("Players/1") as PlayerController
	player.set_physics_process(false)
	player.get_node("VoxelInteractor").set_physics_process(false)
	player.get_node("FrontierVitals").set_physics_process(false)
	player.get_node("DamageReceiver").set_physics_process(false)
	var runtime := GameAPI.entities.runtime as Node3D
	assert(runtime != null)
	runtime.spawning = false
	var ground = null
	for frame in range(600):
		ground = GameAPI.world.raycast(player.global_position, Vector3.DOWN, 60)
		if ground != null and GameAPI.world.is_loaded(Vector3i(ground.position) + Vector3i.UP):
			break
		await get_tree().physics_frame
	assert(ground != null)
	var center := Vector3i(ground.position) + Vector3i.UP
	for frame in range(600):
		if GameAPI.world.tool.is_area_editable(AABB(Vector3(center + Vector3i(-4, -2, -4)), Vector3(15, 7, 15))):
			break
		await get_tree().physics_frame
	assert(GameAPI.world.tool.is_area_editable(AABB(Vector3(center + Vector3i(-4, -2, -4)), Vector3(15, 7, 15))))
	# Native editable terrain platform used for real collision and block-edit checks.
	for x in range(-3, 9):
		for z in range(-3, 9):
			var cell := center + Vector3i(x, 0, z)
			assert(GameAPI.world.set_block(cell + Vector3i.DOWN, "core:stone"))
			for y in range(3):
				assert(GameAPI.world.set_block(cell + Vector3i(0, y, 0), "core:air"))
	player.global_position = Vector3(center) + Vector3(0.5, 0.05, 0.5)
	for frame in range(60):
		await get_tree().physics_frame
	assert(GameAPI.world.can_stand(center))
	var pig := runtime.spawn("creatures:pig", Vector3(center) + Vector3(3.5, 0.05, 0.5)) as Node3D
	var skeleton := runtime.spawn("creatures:skeleton", Vector3(center) + Vector3(0.5, 0.05, 4.5)) as Node3D
	var pig_id: String = pig.entity_id
	var skeleton_id: String = skeleton.entity_id
	pig.goal = Vector3(center) + Vector3(6.5, 0.05, 0.5)
	pig._transition("wander")
	var before: Vector3 = pig.global_position
	for frame in range(90):
		await get_tree().physics_frame
	assert(pig.global_position.distance_to(before) > 0.5, "Creature must actually move on native terrain")
	assert(pig.global_position.y >= center.y - 0.2, "Collision must keep it on the platform")
	# A newly placed two-block wall invalidates movement cells and forces a route around.
	var wall := center + Vector3i(5, 0, 2)
	assert(GameAPI.world.set_block(wall, "core:stone"))
	assert(GameAPI.world.set_block(wall + Vector3i.UP, "core:stone"))
	assert(not GameAPI.world.can_stand(wall))
	var route: Array[Vector3] = runtime.path_to(Vector3(center + Vector3i(4, 0, 2)) + Vector3(0.5, 0.05, 0.5), Vector3(center + Vector3i(7, 0, 2)) + Vector3(0.5, 0.05, 0.5))
	assert(not route.is_empty())
	for waypoint in route:
		assert(Vector3i(waypoint.floor()) != wall)
	skeleton.receiver.receive_damage(4, {"source": player})
	# A one-block step must be traversable with the actual native collision body.
	for x in range(2,5):
		assert(GameAPI.world.set_block(center + Vector3i(x,0,5), "core:stone"))
	pig.global_position = Vector3(center) + Vector3(1.5,0.05,5.5)
	pig.goal = Vector3(center) + Vector3(4.5,1.05,5.5)
	pig.route.clear()
	pig.path_clock = 0
	pig._transition("wander")
	var peak: float = pig.global_position.y
	for frame in range(100):
		peak = maxf(peak, pig.global_position.y)
		await get_tree().physics_frame
	assert(peak > center.y + 0.9, "Mob must jump high enough to clear a block")
	# Low-health hostiles flee instead of continuing to attack.
	skeleton.receiver.receive_damage(13, {"source": player})
	assert(skeleton.state == "flee")
	assert(runtime.save_state())
	var position: Vector3 = pig.global_position
	game.free()
	await get_tree().process_frame
	game = load("res://scenes/main/Game.tscn").instantiate() as Node3D
	add_child(game)
	for frame in range(12):
		await get_tree().process_frame
	runtime = GameAPI.entities.runtime as Node3D
	runtime.spawning = false
	assert(runtime.records.has(pig_id) and runtime.records.has(skeleton_id))
	assert(runtime.records[skeleton_id].health == 3)
	assert(runtime.vector(runtime.records[pig_id].position).distance_to(position) < 0.1)
	for frame in range(600):
		if runtime.actors.has(pig_id):
			break
		await get_tree().physics_frame
	assert(runtime.actors.has(pig_id), "Saved actor must reactivate once its terrain loads")
	player = game.get_node("Players/1") as PlayerController
	player.set_physics_process(false)
	for frame in range(120):
		await get_tree().physics_frame
	var initial: int = runtime.records.size()
	for attempt in range(20):
		runtime.spawn_attempt()
		await get_tree().physics_frame
	assert(runtime.records.size() > initial, "Natural spawn candidates must succeed on loaded terrain")
	for record in runtime.records.values():
		assert(runtime.api.entities.definition(record.kind).size() > 0)
	game.free()
	print("Creature world PASS: native loaded-terrain queries, real collision/movement, edited-block path rerouting, saved ID/health/position, reactivation and natural spawning")
	get_tree().quit()
