extends "CreeperSmoke.gd"

func run() -> void:
	var console = load("res://mods/debug_console/Console.gd").new()
	assert(console._resolve("creeper",GameAPI.entities.definitions.keys()) == "creatures:creeper")
	assert(console._resolve("zombie",GameAPI.entities.definitions.keys()) == "creatures:zombie")
	assert(console._resolve("creeper",["creatures:box_creeper"]) == "creatures:box_creeper")
	assert(console._resolve("creeper",["a:creeper","b:creeper"]) == "")
	var world = FIXTURE.FlatWorld.new(GameAPI.content)
	var events = EventBus.new()
	var api = ModAPI.new(GameAPI.content,events,GameAPI.world_generation,world,WorldEditService.new(GameAPI.content,world,events),GameAPI.crafting,"console:test","1","res://mods/debug_console")
	api.saves = WorldSaveService.new("user://console_summon_tests/%d"%Time.get_ticks_usec())
	api.saves.active_world_id = "fixture"
	api.entities = EntityRegistry.new()
	api.entities.definitions = GameAPI.entities.definitions.duplicate(true)
	api.item_instances = GameAPI.item_instances
	api.stations = BlockEntityService.new(api.content,world)
	api.stations.activate(api.saves.root_path+"/stations.json")
	var runtime = load("res://mods/entity_framework/EntityRuntime.gd").new()
	add_child(runtime)
	runtime.setup(api)
	runtime.set_physics_process(false)
	api.entities.runtime = runtime
	for i in range(256):
		var id = str(i)
		runtime.records[id] = {"id":id,"kind":"creatures:pig","position":[500,0,500],"home":[500,0,500],"health":10,"dead":false}
	var player = Node3D.new()
	add_child(player)
	console.api = api
	console.player = player
	assert(console.execute("/summon creeper") == "Summoned creatures:creeper")
	assert(runtime.records.size() == 257)
	assert(console.execute("/summon creatures:creeper") == "Summoned creatures:creeper")
	assert(runtime.spawn("missing:mob",Vector3.ZERO) == null)
	assert(runtime.last_spawn_error == "unknown mob ID.")
	console.free()
	print("Console summon PASS: canonical short names, legacy fallback, ambiguity safety, and summoning past 256 saved mobs")
	get_tree().quit()
