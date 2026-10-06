extends Node3D

class FlatWorld extends VoxelWorldService:
	var walls: Dictionary = {}
	var loaded := true
	func is_loaded(_position: Vector3i) -> bool:
		return loaded
	func is_solid(position: Vector3i) -> bool:
		return position.y < 0 or walls.has(position)
	func get_block_id(position: Vector3i) -> String:
		return "core:stone" if is_solid(position) else "core:air"

var api: ModAPI
var runtime: Node3D

func _ready() -> void:
	api = ModAPI.new(GameAPI.content, EventBus.new(), GameAPI.world_generation, FlatWorld.new(GameAPI.content), GameAPI.edits, GameAPI.crafting, "entities:test", "1", "res://mods/entity_framework")
	api.saves = GameAPI.saves
	api.entities = EntityRegistry.new()
	api.entities.definitions = GameAPI.entities.definitions.duplicate(true)
	api.item_instances = GameAPI.item_instances
	api.stations = BlockEntityService.new(api.content, api.world)
	var destination := "user://creature_tests/%d.entities.json" % Time.get_ticks_usec()
	api.stations.activate(destination)
	runtime = load("res://mods/entity_framework/EntityRuntime.gd").new()
	runtime.name = "Entities"
	add_child(runtime)
	runtime.setup(api)
	runtime.spawning = false
	runtime.set_physics_process(false)
	api.entities.runtime = runtime
	var player := load("res://scenes/player/Player.tscn").instantiate() as PlayerController
	player.name = "1"
	add_child(player)
	player.set_physics_process(false)
	player.get_node("VoxelInteractor").set_physics_process(false)
	player.global_position = Vector3(0, 0.05, 2)
	var inventory := player.get_node("Inventory") as Inventory
	api.stations.bind_inventory(inventory)
	var health := DamageReceiver.new()
	health.name = "DamageReceiver"
	health.health = 20
	player.add_child(health)
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(100, 1, 100)
	floor_collision.shape = floor_shape
	floor_body.position.y = -0.5
	floor_body.add_child(floor_collision)
	add_child(floor_body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var pig := runtime.spawn("creatures:pig", Vector3(2.5, 0.05, 0.5)) as Node3D
	var skeleton := runtime.spawn("creatures:skeleton", Vector3(0, 0.05, 0)) as Node3D
	pig.set_physics_process(false)
	skeleton.set_physics_process(false)
	assert(pig.visual.legs.size() == 4)
	assert(skeleton.visual.limbs.size() == 4)
	assert(skeleton.visual.material.albedo_texture != null)
	skeleton.visual.animate("attack", 0.4, 0)
	assert(skeleton.visual.limbs[0].rotation.x < -1.0)
	health.receive_damage(NAN, {})
	assert(health.health == 20)
	pig.receiver.receive_damage(2, {"source": player})
	assert(pig.state == "flee" and pig.receiver.health == 8)
	assert(pig.target == null)
	var grid := api.world as FlatWorld
	grid.walls[Vector3i(1, 0, 0)] = true
	grid.walls[Vector3i(1, 1, 0)] = true
	var route: Array[Vector3] = runtime.path_to(Vector3(0.5, 0.05, 0.5), Vector3(3.5, 0.05, 0.5))
	assert(not route.is_empty())
	for waypoint in route:
		assert(grid.can_stand(Vector3i(waypoint.floor())))
		assert(Vector3i(waypoint.floor()) != Vector3i(1, 0, 0))
	grid.loaded = false
	assert(not grid.can_stand(Vector3i.ZERO))
	grid.loaded = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(runtime.find_target(skeleton, 16) == player)
	skeleton._decide()
	assert(skeleton.state == "windup")
	skeleton._physics_process(0.41)
	assert(health.health == 17 and skeleton.state == "recover")
	skeleton._physics_process(0.1)
	assert(health.health == 17)
	player.set_meta("gameplay_disabled", true)
	assert(not runtime.can_hit(skeleton, player, 3))
	player.set_meta("gameplay_disabled", false)
	# Collision wall blocks perception and the eventual attack.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 3, 0.25)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 1, 1)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(not runtime.can_hit(skeleton, player, 3))
	wall.free()
	# Failed persistence must neither commit death nor award loot.
	api.stations.writable = false
	pig.receiver.receive_damage(20, {})
	assert(not pig.dead and runtime.loot.is_empty() and pig.receiver.health == 1)
	api.stations.writable = true
	pig.receiver.receive_damage(20, {})
	assert(pig.dead and runtime.loot.size() == 1)
	pig._depleted({})
	assert(runtime.loot.size() == 1)
	var inventory_before := inventory.get_snapshot()
	inventory.load_snapshot({"version": 2, "hotbar_size": 10, "slots": []})
	assert(inventory.add_item("creatures:bone", Inventory.CAPACITY * 64))
	var full_id: String = runtime.loot.keys()[0]
	var old_position: Array = runtime.loot[full_id].position.duplicate()
	# Move the drop close for this capacity check.
	runtime.loot[full_id].position = runtime.array(player.global_position + Vector3.UP * 0.5)
	assert(not runtime.pickup_local(player, full_id) and runtime.loot.has(full_id))
	runtime.loot[full_id].position = old_position
	inventory.load_snapshot(inventory_before)
	var loot_id: String = runtime.loot.keys()[0]
	player.global_position = pig.global_position
	api.stations.writable = false
	assert(not runtime.pickup_local(player, loot_id))
	assert(inventory.get_item_count("creatures:raw_meat") == 0 and runtime.loot.has(loot_id))
	api.stations.writable = true
	assert(runtime.pickup_local(player, loot_id))
	assert(inventory.get_item_count("creatures:raw_meat") == 2 and runtime.loot.is_empty())
	assert(not runtime.pickup_local(player, loot_id))
	assert(runtime.save_state())
	var saved := JSON.parse_string(FileAccess.get_file_as_string(destination)) as Dictionary
	assert(saved.player_data["entities:world"].actors[pig.entity_id].dead)
	assert(saved.player_data["entities:world"].loot.is_empty())
	var id: String = skeleton.entity_id
	runtime.records[id].health = 11
	assert(runtime.persist())
	var next_service := BlockEntityService.new(api.content, api.world)
	assert(next_service.activate(destination))
	assert(next_service.player_data("entities:world").actors[id].health == 11)
	# Stable reward receipts survive ordinary inventory save/reload.
	inventory.reward_receipts["fixture"] = true
	var snapshot := inventory.get_snapshot()
	inventory.load_snapshot(snapshot)
	assert(inventory.reward_receipts.has("fixture"))
	assert(api.entities.register({"id": "test:npc", "health": 10, "faction": "neutral", "visual": load("res://mods/first_creatures/PigVisual.gd"), "interactive": true, "abilities": [load("res://tests/CreatureAbilityFixture.gd")]}))
	var npc := runtime.spawn("test:npc", player.global_position + Vector3(0, 0, 2)) as Node3D
	npc.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	npc._decide()
	npc.interact(player)
	assert(npc.abilities[0].decisions == 1 and npc.abilities[0].interactions == 1)
	assert(npc.record().ability_state["0"].interactions == 1)
	assert(api.entities.spawn_loot("fixture:quest", {"id": "creatures:bone", "count": 1}, Vector3(20, 0.2, 0)))
	assert(api.entities.spawn_loot("fixture:quest", {"id": "creatures:bone", "count": 1}, Vector3(20, 0.2, 0)))
	assert(runtime.loot.size() == 1)
	# Profile a first-release population with bounded path searches.
	var start := Time.get_ticks_usec()
	for i in range(14):
		var actor := runtime.spawn("creatures:pig" if i < 8 else "creatures:skeleton", Vector3(i + 4, 0.05, 4)) as Node3D
		actor.set_physics_process(false)
		actor._physics_process(0.016)
	print("Creature population sample (14 actors + bounded searches): %d us" % (Time.get_ticks_usec() - start))
	var tick_start := Time.get_ticks_usec()
	for frame in range(30):
		runtime._path_budget = 4
		for actor in runtime.actors.values():
			if not actor.dead:
				actor._physics_process(1.0 / 60.0)
	print("Creature simulation sample: %.0f us/frame across %d actors" % [float(Time.get_ticks_usec() - tick_start) / 30, runtime.actors.size()])
	if "--capture" in OS.get_cmdline_user_args():
		await capture(pig, skeleton)
	print("Creatures PASS: rig clips/strike, passive flee, terrain path/loaded checks, timed attacks, wall/dead-target rejection, atomic death/loot/pickup rollback, saved health and reward receipts")
	api.entities.runtime = null
	runtime.free()
	await get_tree().process_frame
	get_tree().quit()

func capture(pig: Node3D, skeleton: Node3D) -> void:
	for actor in runtime.actors.values():
		actor.visible = actor == pig or actor == skeleton
	get_node("1").visible = false
	pig.global_position = Vector3(-1, 0.05, 0)
	pig.dead = false
	pig.state = "wander"
	pig.visual.animate("wander", 0.3, 0)
	skeleton.global_position = Vector3(1, 0.05, 0)
	skeleton.visual.animate("windup", 0.35, 0)
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = Vector3(3.5, 2.5, -5)
	camera.look_at(Vector3(0, 0.8, 0))
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.shadow_enabled = true
	add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("60764f")
	ground.material_override = material
	add_child(ground)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("798b99")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/creature-preview.png")
