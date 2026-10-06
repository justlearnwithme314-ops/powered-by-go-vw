extends GameMod

## Frontier Survival Expansion
##
## A texture-backed survival/progression layer built on the public mod API:
## - hunger + stamina + sprinting
## - a seven-tier tool/material progression
## - new ores and rare deep vaults
## - biome surface variants
## - food and cooking-style recipes
## - texture-backed inventory/crafting icons
##
## All world generation is deterministic and worker-thread safe.

const NS := "frontier"

const COPPER_ORE := NS + ":copper_ore"
const TIN_ORE := NS + ":tin_ore"
const SILVER_ORE := NS + ":silver_ore"
const MESE_ORE := NS + ":mese_ore"
const MUREXIUM_ORE := NS + ":murexium_ore"

const COPPER_BLOCK := NS + ":copper_block"
const TIN_BLOCK := NS + ":tin_block"
const BRONZE_BLOCK := NS + ":bronze_block"
const STEEL_BLOCK := NS + ":steel_block"
const SILVER_BLOCK := NS + ":silver_block"
const MESE_BLOCK := NS + ":mese_block"
const MUREXIUM_BLOCK := NS + ":murexium_block"
const OBSIDIAN_BRICK := NS + ":obsidian_brick"
const GRANITE_BRICK := NS + ":granite_brick"
const DARK_PLANK := NS + ":dark_plank"
const WEATHERED_PLANK := NS + ":weathered_plank"
const CHERRY_PLANK := NS + ":cherry_plank"
const EBONY_PLANK := NS + ":ebony_plank"

const BADLAND_GRASS := NS + ":badland_grass"
const FROST_GRASS := NS + ":frost_grass"
const PRAIRIE_GRASS := NS + ":prairie_grass"
const JAPANESE_GRASS := NS + ":japanese_grass"
const BAMBOO_GRASS := NS + ":bamboo_grass"

const COPPER_LUMP := NS + ":copper_lump"
const TIN_LUMP := NS + ":tin_lump"
const IRON_LUMP := NS + ":iron_lump"
const COAL_LUMP := NS + ":coal_lump"
const GOLD_LUMP := NS + ":gold_lump"
const SILVER_LUMP := NS + ":silver_lump"
const COPPER_INGOT := NS + ":copper_ingot"
const TIN_INGOT := NS + ":tin_ingot"
const BRONZE_INGOT := NS + ":bronze_ingot"
const IRON_INGOT := NS + ":iron_ingot"
const STEEL_INGOT := NS + ":steel_ingot"
const SILVER_INGOT := NS + ":silver_ingot"
const GOLD_INGOT := NS + ":gold_ingot"
const DIAMOND := NS + ":diamond"
const MESE_CRYSTAL := NS + ":mese_crystal"
const MUREXIUM := NS + ":murexium"

const WOOD_PICKAXE := NS + ":wood_pickaxe"
const WOOD_AXE := NS + ":wood_axe"
const WOOD_SHOVEL := NS + ":wood_shovel"
const WOOD_SWORD := NS + ":wood_sword"
const STONE_PICKAXE := NS + ":stone_pickaxe"
const STONE_AXE := NS + ":stone_axe"
const STONE_SHOVEL := NS + ":stone_shovel"
const STONE_SWORD := NS + ":stone_sword"
const BRONZE_PICKAXE := NS + ":bronze_pickaxe"
const BRONZE_AXE := NS + ":bronze_axe"
const BRONZE_SHOVEL := NS + ":bronze_shovel"
const BRONZE_SWORD := NS + ":bronze_sword"
const STEEL_PICKAXE := NS + ":steel_pickaxe"
const STEEL_AXE := NS + ":steel_axe"
const STEEL_SHOVEL := NS + ":steel_shovel"
const STEEL_SWORD := NS + ":steel_sword"
const MESE_PICKAXE := NS + ":mese_pickaxe"
const MESE_AXE := NS + ":mese_axe"
const MESE_SHOVEL := NS + ":mese_shovel"
const MESE_SWORD := NS + ":mese_sword"
const DIAMOND_PICKAXE := NS + ":diamond_pickaxe"
const DIAMOND_AXE := NS + ":diamond_axe"
const DIAMOND_SHOVEL := NS + ":diamond_shovel"
const DIAMOND_SWORD := NS + ":diamond_sword"
const MUREXIUM_PICKAXE := NS + ":murexium_pickaxe"
const MUREXIUM_AXE := NS + ":murexium_axe"
const MUREXIUM_SHOVEL := NS + ":murexium_shovel"
const MUREXIUM_SWORD := NS + ":murexium_sword"

const APPLE := NS + ":apple"
const GOLDEN_APPLE := NS + ":golden_apple"
const BREAD := NS + ":bread"
const STRAWBERRY := NS + ":strawberry"
const CARROT := NS + ":carrot"
const POTATO := NS + ":potato"
const TOMATO := NS + ":tomato"
const CORN := NS + ":corn"
const CHILI := NS + ":chili"
const MUSHROOM := NS + ":mushroom"
const POISON_MUSHROOM := NS + ":poison_mushroom"
const MUSHROOM_SOUP := NS + ":mushroom_soup"
const HEARTY_STEW := NS + ":hearty_stew"
const SPICY_STEW := NS + ":spicy_stew"

var _api: ModAPI
var _vitals_script: Script
var _active_vitals: Dictionary = {}
var _heart_path := ""
var _stamina_bg_path := ""
var _stamina_fg_path := ""


func register(api: ModAPI) -> void:
	_api = api
	_vitals_script = api.load_asset("scripts/FrontierVitals.gd") as Script
	_heart_path = api.asset("ui/heart.png")
	_stamina_bg_path = api.asset("ui/stamina_bg.png")
	_stamina_fg_path = api.asset("ui/stamina_fg.png")

	_register_blocks(api)
	_register_resources(api)
	_register_tools(api)
	_register_food(api)
	_register_recipes(api)
	_register_worldgen(api)

	api.on(GameEvents.BEFORE_BLOCK_BREAK, Callable(self, "_on_before_block_break"), 50)
	api.on(GameEvents.ITEM_USE, Callable(self, "_on_item_use"), 100)
	api.on(GameEvents.PLAYER_SPAWNED, Callable(self, "_on_player_spawned"), 100)
	api.on(GameEvents.PLAYER_DESPAWNED, Callable(self, "_on_player_despawned"), 100)
	api.on(GameEvents.GAME_STOPPING, Callable(self, "_on_game_stopping"), 100)
	api.on(GameEvents.WORLD_STOPPING, Callable(self, "_on_world_stopping"), 300)

	api.log("Frontier Survival loaded: survival, metallurgy, food, biomes and deep vaults enabled.")


func _register_blocks(api: ModAPI) -> void:
	_register_block(api, COPPER_ORE, "Copper Ore", "copper_ore", 3.0,
		[{"item": COPPER_LUMP, "count": 1}], ["block", "ore", "copper"])
	_register_block(api, TIN_ORE, "Tin Ore", "tin_ore", 2.7,
		[{"item": TIN_LUMP, "count": 1}], ["block", "ore", "tin"])
	_register_block(api, SILVER_ORE, "Silver Ore", "silver_ore", 3.4,
		[{"item": SILVER_LUMP, "count": 1}], ["block", "ore", "silver"])
	_register_block(api, MESE_ORE, "Mese Ore", "mese_ore", 4.4,
		[{"item": MESE_CRYSTAL, "count": 1}], ["block", "ore", "mese"])
	_register_block(api, MUREXIUM_ORE, "Murexium Ore", "murexium_ore", 5.5,
		[{"item": MUREXIUM, "count": 1}], ["block", "ore", "murexium"])

	_register_block(api, COPPER_BLOCK, "Copper Block", "copper_block", 4.0,
		[{"item": COPPER_BLOCK, "count": 1}], ["block", "metal", "copper"])
	_register_block(api, TIN_BLOCK, "Tin Block", "tin_block", 4.0,
		[{"item": TIN_BLOCK, "count": 1}], ["block", "metal", "tin"])
	_register_block(api, BRONZE_BLOCK, "Bronze Block", "bronze_block", 4.6,
		[{"item": BRONZE_BLOCK, "count": 1}], ["block", "metal", "bronze"])
	_register_block(api, STEEL_BLOCK, "Steel Block", "steel_block", 5.4,
		[{"item": STEEL_BLOCK, "count": 1}], ["block", "metal", "steel"])
	_register_block(api, SILVER_BLOCK, "Silver Block", "silver_block", 4.8,
		[{"item": SILVER_BLOCK, "count": 1}], ["block", "metal", "silver"])
	_register_block(api, MESE_BLOCK, "Mese Block", "mese_block", 6.0,
		[{"item": MESE_BLOCK, "count": 1}], ["block", "metal", "mese"])
	_register_block(api, MUREXIUM_BLOCK, "Murexium Block", "murexium_block", 8.0,
		[{"item": MUREXIUM_BLOCK, "count": 1}], ["block", "metal", "murexium"])

	_register_block(api, OBSIDIAN_BRICK, "Obsidian Brick", "obsidian_brick", 8.0,
		[{"item": OBSIDIAN_BRICK, "count": 1}], ["block", "building", "obsidian"])
	_register_block(api, GRANITE_BRICK, "Granite Brick", "granite_brick", 4.2,
		[{"item": GRANITE_BRICK, "count": 1}], ["block", "building", "granite"])

	_register_block(api, DARK_PLANK, "Dark Wood Planks", "dark_plank", 2.2,
		[{"item": DARK_PLANK, "count": 1}], ["block", "building", "wood"])
	_register_block(api, WEATHERED_PLANK, "Weathered Wood Planks", "weathered_plank", 2.2,
		[{"item": WEATHERED_PLANK, "count": 1}], ["block", "building", "wood"])
	_register_block(api, CHERRY_PLANK, "Cherry Blossom Planks", "cherry_plank", 2.2,
		[{"item": CHERRY_PLANK, "count": 1}], ["block", "building", "wood"])
	_register_block(api, EBONY_PLANK, "Ebony Planks", "ebony_plank", 2.5,
		[{"item": EBONY_PLANK, "count": 1}], ["block", "building", "wood"])

	_register_block(api, BADLAND_GRASS, "Badland Grass", "badland_grass", 1.0,
		[{"item": BADLAND_GRASS, "count": 1}], ["block", "grass", "biome"])
	_register_block(api, FROST_GRASS, "Frost Grass", "frost_grass", 1.0,
		[{"item": FROST_GRASS, "count": 1}], ["block", "grass", "biome"])
	_register_block(api, PRAIRIE_GRASS, "Prairie Grass", "prairie_grass", 1.0,
		[{"item": PRAIRIE_GRASS, "count": 1}], ["block", "grass", "biome"])
	_register_block(api, JAPANESE_GRASS, "Japanese Forest Grass", "japanese_grass", 1.0,
		[{"item": JAPANESE_GRASS, "count": 1}], ["block", "grass", "biome"])
	_register_block(api, BAMBOO_GRASS, "Bamboo Forest Grass", "bamboo_grass", 1.0,
		[{"item": BAMBOO_GRASS, "count": 1}], ["block", "grass", "biome"])


func _register_block(
	api: ModAPI,
	block_id: String,
	display_name: String,
	model_name: String,
	hardness: float,
	drops: Array,
	tags: Array
) -> void:
	api.register_block({
		"id": block_id,
		"display_name": display_name,
		"model": api.load_asset("models/%s.tres" % model_name),
		"hardness": hardness,
		"preferred_tool": "axe" if "wood" in tags else ("shovel" if "grass" in tags else "pickaxe"),
		"required_tool": "" if "wood" in tags or "grass" in tags else "pickaxe",
		"mining_level": 7 if "murexium" in tags else (5 if "mese" in tags else (6 if "obsidian" in tags else 2)),
		"solid": true,
		"transparent": false,
		"drops": drops,
		"tags": tags,
	})
	api.register_item({
		"id": block_id,
		"display_name": display_name,
		"stack_size": 64,
		"place_block": block_id,
		"tags": tags,
		"icon": api.asset("textures/%s.png" % model_name),
	})


func _register_resources(api: ModAPI) -> void:
	_register_item(api, COPPER_LUMP, "Copper Lump", 64, "resource", "icons/copper_lump.png")
	_register_item(api, TIN_LUMP, "Tin Lump", 64, "resource", "icons/tin_lump.png")
	_register_item(api, IRON_LUMP, "Iron Lump", 64, "resource", "icons/iron_lump.png")
	_register_item(api, COAL_LUMP, "Coal Lump", 64, "resource", "icons/coal_lump.png")
	_register_item(api, GOLD_LUMP, "Gold Lump", 64, "resource", "icons/gold_lump.png")
	_register_item(api, SILVER_LUMP, "Silver Lump", 64, "resource", "icons/silver_lump.png")
	_register_item(api, COPPER_INGOT, "Copper Ingot", 64, "resource", "icons/copper_ingot.png")
	_register_item(api, TIN_INGOT, "Tin Ingot", 64, "resource", "icons/tin_ingot.png")
	_register_item(api, BRONZE_INGOT, "Bronze Ingot", 64, "resource", "icons/bronze_ingot.png")
	_register_item(api, IRON_INGOT, "Iron Ingot", 64, "resource", "icons/iron_lump.png")
	_register_item(api, STEEL_INGOT, "Steel Ingot", 64, "resource", "icons/steel_ingot.png")
	_register_item(api, SILVER_INGOT, "Silver Ingot", 64, "resource", "icons/silver_ingot.png")
	_register_item(api, GOLD_INGOT, "Gold Ingot", 64, "resource", "icons/gold_ingot.png")
	_register_item(api, DIAMOND, "Diamond", 64, "resource", "icons/diamond.png")
	_register_item(api, MESE_CRYSTAL, "Mese Crystal", 64, "resource", "icons/mese_crystal.png")
	_register_item(api, MUREXIUM, "Murexium Crystal", 64, "resource", "icons/murexium.png")


func _register_item(
	api: ModAPI,
	item_id: String,
	display_name: String,
	stack_size: int,
	tag: String,
	icon_relative_path: String,
	properties: Dictionary = {}
) -> void:
	api.register_item({
		"id": item_id,
		"display_name": display_name,
		"stack_size": stack_size,
		"tags": [tag],
		"properties": properties,
		"icon": api.asset(icon_relative_path),
	})


func _register_tools(api: ModAPI) -> void:
	_register_tool_set(api, "wood", "Wood", 2.0)
	_register_tool_set(api, "stone", "Stone", 3.3)
	_register_tool_set(api, "bronze", "Bronze", 5.0)
	_register_tool_set(api, "steel", "Steel", 7.0)
	_register_tool_set(api, "mese", "Mese", 9.0)
	_register_tool_set(api, "diamond", "Diamond", 12.0)
	_register_tool_set(api, "murexium", "Murexium", 16.0)


func _register_tool_set(
	api: ModAPI,
	material: String,
	display_name: String,
	break_power: float
) -> void:
	var ids := {
		"pickaxe": NS + ":%s_pickaxe" % material,
		"axe": NS + ":%s_axe" % material,
		"shovel": NS + ":%s_shovel" % material,
		"sword": NS + ":%s_sword" % material,
	}
	var icon_paths := {
		"pickaxe": "icons/%s_pickaxe.png" % material,
		"axe": "icons/%s_axe.png" % material,
		"shovel": "icons/%s_shovel.png" % material,
		"sword": "icons/%s_sword.png" % material,
	}
	for kind in ids:
		var power := break_power
		if kind == "sword":
			power = break_power * 0.75
		api.register_item({
			"id": ids[kind],
			"display_name": "%s %s" % [display_name, kind.capitalize()],
			"stack_size": 1,
			"tags": ["tool", kind, material],
			"properties": {
				"break_power": power,
				"tool_type": kind,
				"mining_level": ["wood", "stone", "bronze", "steel", "mese", "diamond", "murexium"].find(material) + 1,
				"mining_interval": 0.38 - 0.035 * ["wood", "stone", "bronze", "steel", "mese", "diamond", "murexium"].find(material),
				"material": material,
			},
			"icon": api.asset(icon_paths[kind]),
		})


func _register_food(api: ModAPI) -> void:
	_register_food_item(api, APPLE, "Apple", 16, 4.0, 5.0, "icons/apple.png")
	_register_food_item(api, GOLDEN_APPLE, "Golden Apple", 4, 12.0, 40.0, "icons/golden_apple.png")
	_register_food_item(api, BREAD, "Bread", 16, 5.0, 8.0, "icons/bread.png")
	_register_food_item(api, STRAWBERRY, "Strawberry", 24, 2.0, 4.0, "icons/strawberry.png")
	_register_food_item(api, CARROT, "Carrot", 16, 3.0, 6.0, "icons/carrot.png")
	_register_food_item(api, POTATO, "Potato", 16, 3.0, 8.0, "icons/potato.png")
	_register_food_item(api, TOMATO, "Tomato", 16, 3.0, 8.0, "icons/tomato.png")
	_register_food_item(api, CORN, "Corn", 16, 4.0, 12.0, "icons/corn.png")
	_register_food_item(api, CHILI, "Thai Chili", 16, 2.0, 18.0, "icons/chili.png")
	_register_food_item(api, MUSHROOM, "Mushroom", 16, 3.0, 4.0, "icons/mushroom.png")
	_register_food_item(api, POISON_MUSHROOM, "Poison Mushroom", 16, -2.0, 0.0,
		"icons/poison_mushroom.png", {"poison_seconds": 8.0})
	_register_food_item(api, MUSHROOM_SOUP, "Mushroom Soup", 8, 8.0, 20.0, "icons/mushroom_soup.png")
	_register_food_item(api, HEARTY_STEW, "Hearty Stew", 8, 12.0, 45.0, "icons/hearty_stew.png")
	_register_food_item(api, SPICY_STEW, "Spicy Stew", 8, 10.0, 55.0, "icons/spicy_stew.png")


func _register_food_item(
	api: ModAPI,
	item_id: String,
	display_name: String,
	stack_size: int,
	food_value: float,
	stamina_restore: float,
	icon_relative_path: String,
	extra_properties: Dictionary = {}
) -> void:
	var properties := {
		"food_value": food_value,
		"stamina_restore": stamina_restore,
	}
	for key in extra_properties:
		properties[key] = extra_properties[key]

	api.register_item({
		"id": item_id,
		"display_name": display_name,
		"stack_size": stack_size,
		"tags": ["food"],
		"properties": properties,
		"icon": api.asset(icon_relative_path),
	})


func _register_recipes(api: ModAPI) -> void:
	# Refining
	api.register_recipe(NS + ":copper_ingot", COPPER_INGOT, 1, {COPPER_LUMP: 1})
	api.register_recipe(NS + ":tin_ingot", TIN_INGOT, 1, {TIN_LUMP: 1})
	api.register_recipe(NS + ":iron_ingot", IRON_INGOT, 1, {IRON_LUMP: 1})
	api.register_recipe(NS + ":gold_ingot", GOLD_INGOT, 1, {GOLD_LUMP: 1})
	api.register_recipe(NS + ":silver_ingot", SILVER_INGOT, 1, {SILVER_LUMP: 1})
	api.register_recipe(NS + ":bronze_ingot", BRONZE_INGOT, 3,
		{COPPER_LUMP: 2, TIN_LUMP: 1})
	api.register_recipe(NS + ":steel_ingot", STEEL_INGOT, 2,
		{IRON_LUMP: 2, COAL_LUMP: 1})

	# Material blocks
	for pair in [
		[COPPER_INGOT, COPPER_BLOCK],
		[TIN_INGOT, TIN_BLOCK],
		[BRONZE_INGOT, BRONZE_BLOCK],
		[STEEL_INGOT, STEEL_BLOCK],
		[SILVER_INGOT, SILVER_BLOCK],
		[MESE_CRYSTAL, MESE_BLOCK],
		[MUREXIUM, MUREXIUM_BLOCK],
	]:
		api.register_recipe(
			NS + ":block_%s" % str(pair[0]).get_slice(":", 1),
			str(pair[1]),
			1,
			{str(pair[0]): 9}
		)

	# Building palette
	api.register_recipe(NS + ":dark_planks", DARK_PLANK, 4, {"core:log": 1})
	api.register_recipe(NS + ":weathered_planks", WEATHERED_PLANK, 4, {"core:log": 1})
	api.register_recipe(NS + ":cherry_planks", CHERRY_PLANK, 4, {"core:log": 1})
	api.register_recipe(NS + ":ebony_planks", EBONY_PLANK, 4, {"core:log": 1})
	api.register_recipe(NS + ":granite_brick", GRANITE_BRICK, 4, {"core:stone": 4})

	# Starter and tool tiers
	_register_tool_recipes(api, "wood", "core:log")
	_register_tool_recipes(api, "stone", "core:stone")
	_register_tool_recipes(api, "bronze", BRONZE_INGOT)
	_register_tool_recipes(api, "steel", STEEL_INGOT)
	_register_tool_recipes(api, "mese", MESE_CRYSTAL)
	_register_tool_recipes(api, "diamond", DIAMOND)
	_register_tool_recipes(api, "murexium", MUREXIUM, DIAMOND)

	# Food
	api.register_recipe(NS + ":golden_apple", GOLDEN_APPLE, 1, {
		APPLE: 1,
		GOLD_INGOT: 8,
	})
	api.register_recipe(NS + ":bread", BREAD, 1, {CORN: 2})
	api.register_recipe(NS + ":mushroom_soup", MUSHROOM_SOUP, 1, {
		MUSHROOM: 2,
		CARROT: 1,
	})
	api.register_recipe(NS + ":hearty_stew", HEARTY_STEW, 1, {
		POTATO: 1,
		CARROT: 1,
		MUSHROOM: 1,
		CORN: 1,
	})
	api.register_recipe(NS + ":spicy_stew", SPICY_STEW, 1, {
		TOMATO: 1,
		CHILI: 1,
		POTATO: 1,
	})


func _register_tool_recipes(
	api: ModAPI,
	material: String,
	material_item: String,
	extra_material: String = ""
) -> void:
	var suffix := "" if extra_material.is_empty() else extra_material
	var pickaxe_id := NS + ":%s_pickaxe" % material
	var axe_id := NS + ":%s_axe" % material
	var shovel_id := NS + ":%s_shovel" % material
	var sword_id := NS + ":%s_sword" % material

	var pick_ingredients := {material_item: 3, "core:stick": 2}
	var axe_ingredients := {material_item: 3, "core:stick": 2}
	var shovel_ingredients := {material_item: 1, "core:stick": 2}
	var sword_ingredients := {material_item: 2, "core:stick": 1}

	if not suffix.is_empty():
		pick_ingredients[extra_material] = 1
		axe_ingredients[extra_material] = 1
		shovel_ingredients[extra_material] = 1
		sword_ingredients[extra_material] = 1

	api.register_recipe(NS + ":%s_pickaxe" % material, pickaxe_id, 1, pick_ingredients)
	api.register_recipe(NS + ":%s_axe" % material, axe_id, 1, axe_ingredients)
	api.register_recipe(NS + ":%s_shovel" % material, shovel_id, 1, shovel_ingredients)
	api.register_recipe(NS + ":%s_sword" % material, sword_id, 1, sword_ingredients)


func _register_worldgen(api: ModAPI) -> void:
	api.register_worldgen_stage(NS + ":copper_ore", 320,
		Callable(self, "_generate_copper"))
	api.register_worldgen_stage(NS + ":tin_ore", 325,
		Callable(self, "_generate_tin"))
	api.register_worldgen_stage(NS + ":silver_ore", 330,
		Callable(self, "_generate_silver"))
	api.register_worldgen_stage(NS + ":mese_ore", 360,
		Callable(self, "_generate_mese"))
	api.register_worldgen_stage(NS + ":murexium_ore", 365,
		Callable(self, "_generate_murexium"))
	api.register_worldgen_stage(NS + ":biomes", 450,
		Callable(self, "_generate_biomes"))
	api.register_worldgen_stage(NS + ":deep_vaults", 470,
		Callable(self, "_generate_deep_vaults"))


func _generate_copper(ctx: WorldGenContext) -> void:
	_generate_ore(ctx, "frontier:copper", 12, 46, 0.48, COPPER_ORE)


func _generate_tin(ctx: WorldGenContext) -> void:
	_generate_ore(ctx, "frontier:tin", 8, 38, 0.52, TIN_ORE)


func _generate_silver(ctx: WorldGenContext) -> void:
	_generate_ore(ctx, "frontier:silver", 4, 30, 0.60, SILVER_ORE)


func _generate_mese(ctx: WorldGenContext) -> void:
	_generate_ore(ctx, "frontier:mese", 4, 20, 0.68, MESE_ORE)


func _generate_murexium(ctx: WorldGenContext) -> void:
	_generate_ore(ctx, "frontier:murexium", 4, 12, 0.74, MUREXIUM_ORE)


func _generate_ore(
	ctx: WorldGenContext,
	noise_key: String,
	min_y: int,
	max_y: int,
	threshold: float,
	block_id: String
) -> void:
	var noise: FastNoiseLite = ctx.noise.get_custom_3d(noise_key, 0.06, 2)
	var size: Vector3i = ctx.buffer.get_size()

	for z in range(size.z):
		for x in range(size.x):
			for y in range(size.y):
				var wy: int = ctx.origin.y + y
				if wy < min_y or wy > max_y:
					continue

				var pos := Vector3i(x, y, z)
				if ctx.get_block_id_local(pos) != "core:stone":
					continue

				var wx: int = ctx.origin.x + x
				var wz: int = ctx.origin.z + z
				if noise.get_noise_3d(wx, wy, wz) > threshold:
					ctx.set_voxel_local(pos, block_id)


func _generate_biomes(ctx: WorldGenContext) -> void:
	var size: Vector3i = ctx.buffer.get_size()

	for z in range(size.z):
		for x in range(size.x):
			var wx: int = ctx.origin.x + x
			var wz: int = ctx.origin.z + z
			var temperature: float = ctx.noise.temperature.get_noise_2d(wx, wz)
			var humidity: float = ctx.noise.humidity.get_noise_2d(wx, wz)
			var replacement := ""

			if temperature < -0.52:
				replacement = FROST_GRASS
			elif temperature > 0.52 and humidity < -0.10:
				replacement = BADLAND_GRASS
			elif humidity > 0.52 and temperature > 0.10:
				replacement = BAMBOO_GRASS
			elif humidity > 0.12 and temperature > -0.10:
				replacement = JAPANESE_GRASS
			elif humidity < -0.28 and temperature > 0.12:
				replacement = PRAIRIE_GRASS

			if replacement.is_empty():
				continue

			for y in range(size.y - 1, -1, -1):
				var pos := Vector3i(x, y, z)
				if ctx.get_block_id_local(pos) == "core:grass":
					ctx.set_voxel_local(pos, replacement)
					break


func _generate_deep_vaults(ctx: WorldGenContext) -> void:
	const CELL_SIZE := 28
	const CENTER_Y := 9
	var size: Vector3i = ctx.buffer.get_size()

	var min_cell_x: int = floori(float(ctx.origin.x - 5) / float(CELL_SIZE))
	var max_cell_x: int = floori(float(ctx.origin.x + size.x + 5) / float(CELL_SIZE))
	var min_cell_z: int = floori(float(ctx.origin.z - 5) / float(CELL_SIZE))
	var max_cell_z: int = floori(float(ctx.origin.z + size.z + 5) / float(CELL_SIZE))

	for cell_z in range(min_cell_z, max_cell_z + 1):
		for cell_x in range(min_cell_x, max_cell_x + 1):
			var seed_value: int = (cell_x * 92837111) ^ (cell_z * 689287499) ^ ctx.world_seed
			if absi(seed_value) % 1000 > 7:
				continue

			var center := Vector3i(
				cell_x * CELL_SIZE + 14,
				CENTER_Y + (absi(seed_value) % 5),
				cell_z * CELL_SIZE + 14
			)

			for dy in range(-4, 5):
				for dx in range(-4, 5):
					for dz in range(-4, 5):
						if dx * dx + dy * dy + dz * dz > 16:
							continue
						var world_pos := center + Vector3i(dx, dy, dz)
						var local_pos := world_pos - ctx.origin
						if not ctx.inside(local_pos):
							continue

						var shell := (
							absi(dx) == 4
							or absi(dy) == 4
							or absi(dz) == 4
						)
						if shell:
							ctx.set_voxel_local(local_pos, OBSIDIAN_BRICK)
						else:
							ctx.set_voxel_local(local_pos, ContentRegistry.AIR_ID)

			for prize_pos in [
				Vector3i(0, -2, 0),
				Vector3i(1, -2, 0),
				Vector3i(-1, -2, 0),
				Vector3i(0, -2, 1),
				Vector3i(0, -2, -1),
				Vector3i(0, 0, 0),
			]:
				var prize_world: Vector3i = center + prize_pos
				var prize_local := prize_world - ctx.origin
				if ctx.inside(prize_local):
					ctx.set_voxel_local(prize_local, MUREXIUM_ORE if prize_pos.y == 0 else MESE_BLOCK)


func _on_before_block_break(event: Dictionary) -> Dictionary:
	var block_id: String = str(event.get("block_id", ""))
	var drops: Array = event.get("drops", [])

	match block_id:
		"core:iron_ore":
			event["drops"] = [{"item": IRON_LUMP, "count": 1}]
		"core:coal_ore":
			event["drops"] = [{"item": COAL_LUMP, "count": 1}]
		"core:gold_ore":
			event["drops"] = [{"item": GOLD_LUMP, "count": 1}]
		"core:diamond_ore":
			event["drops"] = [{"item": DIAMOND, "count": 1}]
		_:
			if drops.is_empty():
				event["drops"] = drops

	return event


func _on_item_use(event: Dictionary) -> Dictionary:
	if bool(event.get("handled", false)):
		return event
	var item_id: String = str(event.get("item_id", ""))
	if not _is_food(item_id):
		return event

	var player: CharacterBody3D = event.get("player") as CharacterBody3D
	if player == null or not player.is_multiplayer_authority():
		return event

	var vitals: Node = player.get_node_or_null("FrontierVitals")
	if vitals == null:
		return event

	var eaten: bool = bool(vitals.call("try_eat", item_id))
	if eaten:
		event["handled"] = true
	return event


func _is_food(item_id: String) -> bool:
	var item: Dictionary = _api.content.get_item(item_id)
	return "food" in item.get("tags", [])


func _on_player_spawned(event: Dictionary) -> Dictionary:
	var player: CharacterBody3D = event.get("player") as CharacterBody3D
	if player == null:
		return event

	var peer_id := int(event.get("peer_id", 1))
	var inventory := player.get_node_or_null("Inventory") as Inventory

	# Only the locally-owned player gets the local survival state.
	# GameManager loads a saved local inventory before this event fires, so a
	# returning player keeps their inventory instead of being reset every spawn.
	if not player.is_multiplayer_authority():
		return event

	# Saved equipment is retained. Empty inventory starts with gathering/hand recipes.

	if _vitals_script == null or player.get_node_or_null("FrontierVitals") != null:
		return event

	var vitals: Node = _vitals_script.new()
	vitals.name = "FrontierVitals"
	vitals.set("world_api", _api)
	vitals.set_meta("frontier_heart_texture", _heart_path)
	vitals.set_meta("frontier_stamina_bg", _stamina_bg_path)
	vitals.set_meta("frontier_stamina_fg", _stamina_fg_path)
	player.add_child(vitals)

	var saved_hunger: float = 18.0
	if not _api.stations.path.is_empty():
		saved_hunger = float(_api.stations.player_data("frontier:vitals").get("hunger", 18.0))
	vitals.call("initialize_state", clampf(saved_hunger, 0.0, 20.0))
	_active_vitals[peer_id] = vitals

	return event


func _on_player_despawned(event: Dictionary) -> Dictionary:
	var peer_id: int = int(event.get("peer_id", 1))
	_save_vitals(peer_id)
	_active_vitals.erase(peer_id)
	return event


func _on_game_stopping(event: Dictionary) -> Dictionary:
	for peer_id in _active_vitals.keys():
		_save_vitals(int(peer_id))
	_active_vitals.clear()
	return event


func _save_vitals(peer_id: int) -> void:
	if _api == null or _api.stations.path.is_empty():
		return

	var vitals: Node = _active_vitals.get(peer_id)
	if vitals == null or not is_instance_valid(vitals):
		return

	var hunger: float = float(vitals.get("hunger"))
	_api.stations.set_player_data("frontier:vitals", {"hunger": hunger})
	_api.stations.save()

func _on_world_stopping(event: Dictionary) -> Dictionary:
	for peer_id in _active_vitals.keys():
		_save_vitals(int(peer_id))
	return event
