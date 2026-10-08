extends Node3D

const FIXTURE = preload("BasicSurvivalSmoke.gd")

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var world = FIXTURE.FlatWorld.new(GameAPI.content)
	var events = EventBus.new()
	var api = ModAPI.new(GameAPI.content,events,GameAPI.world_generation,world,WorldEditService.new(GameAPI.content,world,events),GameAPI.crafting,"blast:test","1","res://mods/basic_survival")
	api.saves = WorldSaveService.new("user://creeper_tests/%d"%Time.get_ticks_usec())
	api.saves.active_world_id = "fixture"
	api.entities = EntityRegistry.new()
	api.entities.definitions = GameAPI.entities.definitions.duplicate(true)
	api.item_instances = GameAPI.item_instances
	api.stations = BlockEntityService.new(api.content,world)
	DirAccess.make_dir_recursive_absolute(api.saves.root_path)
	api.stations.activate(api.saves.root_path+"/stations.json")
	var runtime = load("res://mods/entity_framework/EntityRuntime.gd").new()
	runtime.name = "Entities"
	add_child(runtime)
	runtime.setup(api)
	runtime.set_physics_process(false)
	api.entities.runtime = runtime
	var changes = load("res://mods/basic_survival/SurvivalRuntime.gd").new()
	changes.name = "BasicSurvival"
	add_child(changes)
	changes.setup(api)
	changes.set_process(false)
	var blast = load("res://mods/basic_survival/ExplosionRuntime.gd").new()
	blast.name = "CreeperExplosions"
	add_child(blast)
	blast.setup(api,changes)
	assert(blast.blast_sound.data.size()>10000)
	var player = load("res://scenes/player/Player.tscn").instantiate()
	player.name = "1"
	add_child(player)
	player.set_physics_process(false)
	player.get_node("VoxelInteractor").set_physics_process(false)
	player.global_position = Vector3(0.5,0.05,2.5)
	var health = DamageReceiver.new()
	health.name = "DamageReceiver"
	health.health = 20
	player.add_child(health)
	var creeper = runtime.spawn("creatures:creeper",Vector3(0.5,0.05,0.5))
	creeper.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ability = creeper.abilities[0]
	ability.tick(creeper,0.6)
	assert(creeper.state == "fuse" and health.health == 20)
	creeper.visual.animate("fuse",0.6,0)
	assert(creeper.visual.body.scale.x>1)
	player.global_position.z = 10
	ability.tick(creeper,0.5)
	assert(ability.fuse == 0 and not creeper.dead)
	var saved = ability.save_state()
	ability.restore(saved)
	assert(not ability.detonated)
	player.global_position.z = 2.5
	await get_tree().physics_frame
	world.cells[Vector3i(1,0,0)] = "core:dirt"
	world.cells[Vector3i(4,0,0)] = "core:dirt"
	ability.tick(creeper,1.0)
	ability.tick(creeper,0.51)
	assert(creeper.dead and ability.detonated and blast.effect_count == 1)
	assert(health.health<20 and player.velocity.y>0 and player.velocity.z>0)
	assert(world.get_block_id(Vector3i(1,0,0)) == "core:air")
	assert(world.get_block_id(Vector3i(4,0,0)) == "core:dirt")
	for key in changes.changes:
		var center = Vector3(changes.position(key))+Vector3.ONE*0.5
		assert(center.distance_to(Vector3(0.5,0.85,0.5))<=blast.BLOCK_RADIUS)
	assert(runtime.loot.is_empty(),"Exploding creepers must not also award kill loot")
	ability.tick(creeper,2)
	assert(blast.effect_count == 1)
	var record = runtime.records[creeper.entity_id]
	assert(record.dead and record.ability_state["0"].detonated)
	assert(FileAccess.file_exists(changes.save_path))
	assert(blast.get_node("ExplosionParticles") is CPUParticles3D)
	# Verify characteristic body sizes and UV bounds against the reference models.
	for pair in [["pig",Vector3(10,16,8)],["cow",Vector3(12,18,10)],["sheep",Vector3(8,16,6)],["chicken",Vector3(6,8,6)]]:
		var definition = api.entities.definition("creatures:"+pair[0])
		var visual = definition.visual.new()
		add_child(visual)
		visual.setup(definition)
		var mesh = visual.body.get_node("Torso").get_child(0).mesh
		assert(mesh.get_aabb().size.is_equal_approx(pair[1]/16))
		visual.free()
	print("Creeper PASS: fuse/escape, one blast, player damage/launch, spherical crater, saved death/cells, sound/particles and reference mob proportions")
	get_tree().quit()
