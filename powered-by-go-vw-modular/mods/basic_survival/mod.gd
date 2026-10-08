extends GameMod

const PACK = "res://assets/minecraft-inspired-textures-free/"
const WOODS = ["oak","spruce","birch","jungle","acacia","dark_oak","mangrove","crimson","warped"]
var _api: ModAPI
var _runtime: Node

func register(api: ModAPI) -> void:
	_api = api
	woods(api)
	crops(api)
	items(api)
	mobs(api)
	block(api,"survival:chest","Chest","oak_planks",2.0,"axe",["block","wood","container"])
	chest_model(api)
	api.stations.register_kind("survival:chest",[],{"storage":27})
	api.register_recipe("survival:chest","survival:chest",1,{"#core:planks":8},{"station":"workbench"})
	api.crafting.grid_service.register_pattern("survival:chest",pattern(["PPP","P P","PPP"],{"P":"#core:planks"}))
	api.on(GameEvents.WORLD_READY,_ready_world,-150)
	api.on(GameEvents.WORLD_STOPPING,_stopping,250)
	api.on(GameEvents.ITEM_USE,_use,400)
	api.on(GameEvents.PRIMARY_ACTION,_primary,400)
	api.on(GameEvents.BEFORE_BLOCK_BREAK,_drops,250)

func chest_model(api: ModAPI) -> void:
	var builder = api.load_asset("../first_creatures/HumanoidVisual.gd").new()
	builder.atlas_size = Vector2(64,64)
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The supplied 64x64 chest atlas contains a 14x10x14 body,
	# a 14x5x14 lid (overlapping the body by one pixel), and a 2x4x1 latch.
	for part in [
		[Vector3(14,10,14), Vector2(0,19), Vector3(8,5,8)],
		[Vector3(14,5,14), Vector2.ZERO, Vector3(8,11.5,8)],
		[Vector3(2,4,1), Vector2.ZERO, Vector3(8,10,0.5)]
	]:
		var mesh: ArrayMesh = builder._cube(part[0],part[1],false)
		surface.append_from(mesh,0,Transform3D(Basis.IDENTITY,part[2] / 16.0))
	surface.index()
	var material = StandardMaterial3D.new()
	material.albedo_texture = texture("chest/normal","entity")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 1.0
	var model = VoxelBlockyModelMesh.new()
	model.mesh = surface.commit()
	# Custom mesh models default to NO box collision. VoxelTool raycasts use
	# these boxes for targeting as well as the terrain's physical collision.
	model.collision_aabbs = [AABB(Vector3(1,0,1) / 16.0,Vector3(14,14,14) / 16.0)]
	model.set_material_override(0,material)
	api.content.get_block("survival:chest").model = model
	# Use a readable item icon instead of displaying the entire unfolded atlas.
	api.content.get_item("survival:chest").icon = api.asset("icons/chest.png")
	builder.free()

func texture(name: String, group: String = "block") -> Texture2D:
	return _api.load_asset(PACK+group+"/"+name+".png") as Texture2D

func block(api: ModAPI, id: String, label: String, tex: String, hardness: float, tool: String, tags: Array, top: String = "", transparent: bool = false) -> void:
	var material = StandardMaterial3D.new()
	material.albedo_texture = texture(tex)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 1
	if "leaves" in tags: material.albedo_color = Color(0.45,0.75,0.3,0.72)
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var model = VoxelBlockyModelCube.new()
	if "leaves" in tags: model.atlas_size_in_tiles = Vector2i(1,1)
	model.set_material_override(0,material)
	# Different log end textures use a three-wide local atlas.
	if not top.is_empty():
		var side_image = texture(tex).get_image()
		var end_image = texture(top).get_image()
		side_image.convert(Image.FORMAT_RGBA8)
		end_image.convert(Image.FORMAT_RGBA8)
		var atlas = Image.create(side_image.get_width()*3,side_image.get_height(),false,Image.FORMAT_RGBA8)
		atlas.blit_rect(side_image,Rect2i(Vector2i.ZERO,side_image.get_size()),Vector2i.ZERO)
		for x in [1,2]: atlas.blit_rect(end_image,Rect2i(Vector2i.ZERO,end_image.get_size()),Vector2i(x*side_image.get_width(),0))
		material.albedo_texture = ImageTexture.create_from_image(atlas)
		model.atlas_size_in_tiles = Vector2i(3,1)
		model.tile_top = Vector2i(1,0)
		model.tile_bottom = Vector2i(2,0)
	api.register_block({"id":id,"display_name":label,"model":model,"hardness":hardness,"preferred_tool":tool,"required_tool":"pickaxe" if tool == "pickaxe" else "","mining_level":1,"tags":tags,"transparent":transparent})
	api.content.get_item(id).icon = api.asset(PACK+"block/"+tex+".png")

func woods(api: ModAPI) -> void:
	# Older worlds use core:leaves; give these the same oak material.
	var legacy_leaves = VoxelBlockyModelCube.new()
	var leaf_material = StandardMaterial3D.new()
	leaf_material.albedo_texture = texture("oak_leaves")
	leaf_material.albedo_color = Color(0.45,0.75,0.3,0.72)
	leaf_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	leaf_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	leaf_material.roughness = 1.0
	legacy_leaves.atlas_size_in_tiles = Vector2i(1,1)
	legacy_leaves.set_material_override(0,leaf_material)
	api.content.get_block("core:leaves").model = legacy_leaves
	api.content.get_item("core:leaves").icon = api.asset(PACK+"block/oak_leaves.png")
	for wood in WOODS:
		var stem = wood in ["crimson","warped"]
		var base = "survival:"+wood
		var log_tex = wood+("_stem" if stem else "_log")
		block(api,base+"_log",wood.capitalize()+" Log",log_tex,2,"axe",["block","wood","core:logs"],log_tex+"_top")
		block(api,base+"_planks",wood.capitalize()+" Planks",wood+"_planks",0.8,"axe",["block","wood","core:planks"])
		api.configure_item_properties(base+"_log",{"fuel_seconds":16})
		api.configure_item_properties(base+"_planks",{"fuel_seconds":4})
		api.register_recipe(base+"_planks",base+"_planks",4,{base+"_log":1})
		api.register_recipe(base+"_charcoal","survival:charcoal",1,{base+"_log":1},{"method":"smelt","station":"furnace","duration":8})
		if not stem:
			block(api,base+"_leaves",wood.capitalize()+" Leaves",wood+"_leaves",0.5,"",["block","leaves"],"",true)
	for id in ["core:log"]:
		api.content.get_block(id).tags.append("core:logs")
		api.content.get_item(id).tags.append("core:logs")
	for wood in WOODS.slice(0,7):
		api.content.get_block("survival:"+wood+"_log").tags.append("survival:tree_log")
	# Existing recipes retain their IDs and now accept all log species.
	for id in api.content.get_recipe_ids():
		var recipe = api.content.get_recipe(id)
		if recipe.method == "craft" and recipe.ingredients.has("core:log"):
			var amount = int(recipe.ingredients["core:log"])
			recipe.ingredients.erase("core:log")
			recipe.ingredients["#core:logs"] = amount
	block(api,"survival:cobblestone","Cobblestone","cobblestone",2,"pickaxe",["block","stone","core:stone"])
	api.content.get_block("core:stone").tags.append("core:stone")
	api.content.get_item("core:stone").tags.append("core:stone")
	for id in api.content.get_recipe_ids():
		var recipe = api.content.get_recipe(id)
		if recipe.method == "craft" and recipe.ingredients.has("core:stone"):
			var amount = int(recipe.ingredients["core:stone"])
			recipe.ingredients.erase("core:stone")
			recipe.ingredients["#core:stone"] = amount
	api.content.get_block("core:stone").drops = [{"item":"survival:cobblestone","count":1}]
	api.register_recipe("survival:stone_from_cobble","core:stone",1,{"survival:cobblestone":1},{"method":"smelt","station":"furnace","duration":8})

func item(api: ModAPI, id: String, tex: String, tags: Array = [], props: Dictionary = {}, stack: int = 64) -> void:
	api.register_item({"id":id,"display_name":id.get_slice(":",1).replace("_"," ").capitalize(),"stack_size":stack,"icon":api.asset(PACK+"item/"+tex+".png"),"tags":tags,"properties":props})

func items(api: ModAPI) -> void:
	for resource in ["leather","feather","string","flint","gunpowder","egg","sugar","wheat","wheat_seeds","beetroot_seeds","pumpkin_seeds","melon_seeds"]:
		item(api,"survival:"+resource,resource,["seed"] if resource.ends_with("seeds") else ["resource"])
	for entry in [["raw_beef","beef",3],["cooked_beef","cooked_beef",8],["raw_chicken","chicken",2],["cooked_chicken","cooked_chicken",6],["raw_mutton","mutton",2],["cooked_mutton","cooked_mutton",6],["baked_potato","baked_potato",5],["beetroot","beetroot",1],["melon_slice","melon_slice",2],["pumpkin_pie","pumpkin_pie",8]]:
		item(api,"survival:"+entry[0],entry[1],["food"],{"food_value":entry[2],"stamina_restore":entry[2]*2})
	for food in ["beef","chicken","mutton"]:
		api.register_recipe("survival:cooked_"+food,"survival:cooked_"+food,1,{"survival:raw_"+food:1},{"method":"smelt","station":"furnace","duration":6})
	api.register_recipe("survival:baked_potato","survival:baked_potato",1,{"frontier:potato":1},{"method":"smelt","station":"furnace","duration":6})
	api.register_recipe("survival:wheat_bread","frontier:bread",1,{"survival:wheat":3})
	api.register_recipe("survival:sugar","survival:sugar",1,{"survival:wheat":1})
	api.register_recipe("survival:pumpkin_pie","survival:pumpkin_pie",1,{"survival:pumpkin":1,"survival:sugar":1,"survival:egg":1})
	api.crafting.grid_service.register_pattern("survival:wheat_bread",[["survival:wheat","survival:wheat","survival:wheat"]])
	for tier in ["wood","stone","copper","iron"]:
		var material = "#core:planks" if tier == "wood" else "#core:stone" if tier == "stone" else "frontier:"+tier+"_ingot"
		for kind in ["pickaxe","axe","shovel","sword","hoe"]:
			var id = "frontier:"+tier+"_"+kind
			if api.content.has_item(id): continue
			var level = ["wood","stone","copper","iron"].find(tier)+1
			var tex_tier = "wooden" if tier == "wood" else "iron" if tier == "copper" else tier
			item(api,id,tex_tier+"_"+kind,["tool",kind,tier],{"tool_type":kind,"material":tier,"mining_level":level,"break_power":2+level*1.5,"mining_interval":0.38-level*0.03,"melee_damage":4+level if kind == "sword" else 2,"max_durability":64*level,"repair_material":"survival:oak_planks" if tier == "wood" else "core:stone" if tier == "stone" else material,"repair_station":"workbench"},1)
			var amount = 3 if kind in ["axe","pickaxe"] else 2 if kind in ["hoe","sword"] else 1
			api.register_recipe(id,id,1,{material:amount,"core:stick":1 if kind == "sword" else 2},{"station":"workbench"})
			if kind == "hoe": api.crafting.grid_service.register_pattern(id,pattern(["MM"," S"," S"],{"M":material,"S":"core:stick"}))
	item(api,"survival:bow","bow",["weapon","ranged"],{"max_durability":384,"repair_material":"survival:string","repair_station":"workbench","ranged_damage":6},1)
	item(api,"survival:arrow","arrow",["ammo"])
	api.register_recipe("survival:bow","survival:bow",1,{"core:stick":3,"survival:string":3},{"station":"workbench"})
	api.crafting.grid_service.register_pattern("survival:bow",pattern([" ST","S T"," ST"],{"S":"core:stick","T":"survival:string"}))
	api.register_recipe("survival:arrows","survival:arrow",4,{"survival:flint":1,"core:stick":1,"survival:feather":1})
	api.crafting.grid_service.register_pattern("survival:arrows",[["survival:flint"],["core:stick"],["survival:feather"]])
	for entry in [["helmet","head",1,5],["chestplate","body",3,8],["leggings","legs",2,7],["boots","feet",1,4]]:
		var id = "survival:leather_"+entry[0]
		item(api,id,"leather_"+entry[0],["armor"],{"equipment_slots":[entry[1]],"armor":entry[2],"max_durability":100,"repair_material":"survival:leather","repair_station":"workbench"},1)
		api.register_recipe(id,id,1,{"survival:leather":entry[3]},{"station":"workbench"})

func crops(api: ModAPI) -> void:
	block(api,"survival:farmland","Farmland","farmland",0.6,"shovel",["block","soil"],"farmland_moist")
	for crop in ["wheat","carrots","potatoes","beetroots","pumpkin","melon"]:
		var stages = 8 if crop == "wheat" else 4
		if crop in ["pumpkin","melon"]:
			block(api,"survival:"+crop,crop.capitalize(),crop+"_side",0.5,"axe",["block","crop"],crop+"_top")
		for stage in range(stages):
			var tex = crop+"_stage"+str(stage) if crop not in ["pumpkin","melon"] else crop+"_stem"
			var id = "survival:"+crop+"_crop_"+str(stage)
			var material = StandardMaterial3D.new()
			material.albedo_texture = texture(tex)
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			var mesh = SurfaceTool.new()
			mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
			for axis in [0,1]:
				for corner in [0,1,2,0,2,3]:
					var coords = [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
					var uv: Vector2 = coords[corner]
					mesh.set_uv(uv)
					mesh.set_normal(Vector3.FORWARD if axis == 0 else Vector3.RIGHT)
					mesh.add_vertex(Vector3(uv.x,1-uv.y,0.5) if axis == 0 else Vector3(0.5,1-uv.y,uv.x))
			var model = VoxelBlockyModelMesh.new()
			mesh.index()
			model.mesh = mesh.commit()
			model.set_material_override(0,material)
			model.set_mesh_collision_enabled(0,false)
			api.register_block({"id":id,"display_name":crop.capitalize()+" Crop","model":model,"solid":false,"transparent":true,"hardness":0.1,"tags":["block","crop"],"drops":[]})

func mobs(api: ModAPI) -> void:
	var visual = api.load_asset("AnimalVisual.gd") as Script
	for entry in [["pig",10,0.9,"pig/pig",[{"id":"creatures:raw_meat","count":2}]],["cow",10,1.3,"cow/cow",[{"id":"survival:raw_beef","count":2},{"id":"survival:leather","count":2}]],["sheep",8,1.1,"sheep/sheep",[{"id":"survival:raw_mutton","count":2},{"id":"survival:white_wool","count":1}]],["chicken",4,0.7,"chicken",[{"id":"survival:raw_chicken","count":1},{"id":"survival:feather","count":2},{"id":"survival:egg","count":1}]]]:
		var id = "creatures:"+entry[0]
		var definition = {"id":id,"health":entry[1],"height":entry[2],"radius":0.25 if entry[0] == "chicken" else 0.4,"speed":1.5,"faction":"passive","natural_spawn":true,"visual":visual,"skin":texture(entry[3],"entity"),"animal_kind":entry[0],"loot":entry[4]}
		if api.entities.definitions.has(id): api.entities.definitions[id].merge(definition,true)
		else: api.entities.register(definition)
	api.entities.register({"id":"creatures:spider","health":16,"height":0.8,"radius":0.55,"speed":2.4,"damage":2,"detect":16,"reach":2,"windup":0.4,"cooldown":1.2,"faction":"hostile","natural_spawn":true,"visual":visual,"skin":texture("spider/spider","entity"),"animal_kind":"spider","flee_health_ratio":0.2,"loot":[{"id":"survival:string","count":2}]})
	block(api,"survival:white_wool","White Wool","white_wool",0.8,"",["block","wool"])
	api.register_recipe("survival:white_wool","survival:white_wool",1,{"survival:string":4})
	api.crafting.grid_service.register_pattern("survival:white_wool",[["survival:string","survival:string"],["survival:string","survival:string"]])
	# Saved prototype mob IDs remain valid; their loot now feeds progression.
	api.entities.definitions["creatures:box_zombie"].loot = [{"id":"frontier:carrot","count":1},{"id":"frontier:potato","count":1}]
	api.entities.definitions["creatures:box_creeper"].loot = [{"id":"survival:gunpowder","count":2}]
	api.entities.definitions["creatures:box_creeper"].abilities = [api.load_asset("CreeperAbility.gd")]
	api.entities.definitions["creatures:box_creeper"].damage = 0
	api.entities.definitions["creatures:box_creeper"].flee_health_ratio = 0
	api.entities.definitions["creatures:skeleton"].loot = [{"id":"creatures:bone","count":2},{"id":"survival:arrow","count":2}]
	api.entities.definitions["creatures:skeleton"].natural_spawn = true
	for pair in [["zombie","box_zombie"],["creeper","box_creeper"]]:
		var definition: Dictionary = api.entities.definitions["creatures:"+pair[1]].duplicate(true)
		definition.id = "creatures:"+pair[0]
		definition.natural_spawn = false
		api.entities.register(definition)

func pattern(rows: Array, keys: Dictionary) -> Array:
	var result: Array = []
	for row in rows:
		var cells: Array = []
		for ch in str(row): cells.append(str(keys.get(ch,"")))
		result.append(cells)
	return result

func _ready_world(event: Dictionary) -> Dictionary:
	_runtime = _api.load_asset("SurvivalRuntime.gd").new() as Node
	_runtime.name = "BasicSurvival"
	(event.world as Node).add_child(_runtime)
	_runtime.call("setup",_api)
	var explosions := _api.load_asset("ExplosionRuntime.gd").new() as Node3D
	explosions.name = "CreeperExplosions"
	(event.world as Node).add_child(explosions)
	explosions.call("setup",_api,_runtime)
	return event

func _stopping(event: Dictionary) -> Dictionary:
	if is_instance_valid(_runtime): _runtime.call("save_state")
	_runtime = null
	return event

func _use(event: Dictionary) -> Dictionary:
	if not bool(event.get("handled",false)) and is_instance_valid(_runtime):
		if _runtime.call("use",event): event.handled = true
	return event

func _primary(event: Dictionary) -> Dictionary:
	var player = event.get("player") as Node
	if player != null:
		var inventory = player.get_node_or_null("Inventory") as Inventory
		if inventory != null and inventory.get_selected_item_id() == "survival:bow": event.handled = true
	return event

func _drops(event: Dictionary) -> Dictionary:
	var id = str(event.get("block_id",""))
	if id.contains("_crop_"):
		var crop = id.get_slice(":",1).get_slice("_crop_",0)
		var mature = int(id.get_slice("_crop_",1)) == (7 if crop == "wheat" else 3)
		var seed = {"wheat":"survival:wheat_seeds","carrots":"frontier:carrot","potatoes":"frontier:potato","beetroots":"survival:beetroot_seeds","pumpkin":"survival:pumpkin_seeds","melon":"survival:melon_seeds"}.get(crop,"")
		event.drops = [{"item":seed,"count":2 if mature else 1}]
		if mature:
			var produce = {"wheat":"survival:wheat","beetroots":"survival:beetroot","pumpkin":"survival:pumpkin","melon":"survival:melon_slice"}.get(crop,seed)
			event.drops.append({"item":produce,"count":3})
	elif id == "core:gravel":
		event.drops.append({"item":"survival:flint","count":1})
	elif "leaves" in _api.content.get_block(id).get("tags",[]) or id == "core:leaves":
		event.drops.append({"item":"survival:wheat_seeds","count":1})
		# Additional crop seeds share the existing exploration loop.
		var seeds = ["survival:beetroot_seeds","survival:pumpkin_seeds","survival:melon_seeds"]
		event.drops.append({"item":seeds[posmod(hash(event.position),3)],"count":1})
	return event

