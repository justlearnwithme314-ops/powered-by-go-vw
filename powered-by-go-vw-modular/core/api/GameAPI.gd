extends Node

## Composition root for the game.
##
## Mods receive a narrow ModAPI contract. GameAPI itself owns the concrete
## services and can be reorganized without forcing mods to follow internal
## implementation details.

var saves: WorldSaveService = WorldSaveService.new()
var content: ContentRegistry
var events: EventBus
var world_generation: WorldGenerationPipeline
var world: VoxelWorldService
var edits: WorldEditService
var mods: ModLoader
var crafting: CraftingService
var base_mod_api: ModAPI


var session: Node = null
var initialized := false

signal ready_for_gameplay


func _ready() -> void:
	initialize()
	tree_exiting.connect(_save_mod_storage)


func _save_mod_storage() -> void:
	if mods != null:
		mods.save_all_storage()


func initialize() -> void:
	if initialized:
		return

	content = ContentRegistry.new()
	events = EventBus.new()
	world_generation = WorldGenerationPipeline.new(content)
	world = VoxelWorldService.new(content, events)
	edits = WorldEditService.new(content, world, events)
	crafting = CraftingService.new(content, events)
	base_mod_api = ModAPI.new(
		content, events, world_generation, world, edits, crafting
	)
	base_mod_api.saves = saves
	mods = ModLoader.new()

	mods.load_all(base_mod_api)
	content.finalize()
	world_generation.finalize()

	initialized = true
	ready_for_gameplay.emit()

	print(
		"[GameAPI] Initialized. Blocks=%d Items=%d Recipes=%d Mods=%d"
		% [
			content.blocks.size(),
			content.items.size(),
			content.recipes.size(),
			mods.loaded_mods.size(),
		]
	)


func ensure_ready() -> bool:
	if initialized:
		return true
	initialize()
	return initialized


func register_block(definition: Dictionary) -> int:
	return content.register_block(definition)


func register_item(definition: Dictionary) -> bool:
	return content.register_item(definition)


func register_recipe(
	recipe_id: String,
	output_id: String,
	count: int,
	ingredients: Dictionary
) -> bool:
	return content.register_recipe(recipe_id, output_id, count, ingredients)


func register_worldgen_stage(stage_id: String, order: int, callback: Callable) -> bool:
	return world_generation.register_stage(stage_id, order, callback)


func on(event_name: String, callback: Callable, priority: int = 0) -> void:
	events.subscribe(event_name, callback, priority)


func off(event_name: String, callback: Callable) -> void:
	events.unsubscribe(event_name, callback)


func get_loaded_mods() -> Array[Dictionary]:
	if mods == null:
		return []
	return mods.get_loaded_mods()
