class_name ModAPI
extends RefCounted

## Stable public API exposed to one mod instance.
##
## Every mod gets its own context, including its namespace/root path. This
## makes the same mod work from res://, user://, or a mounted .pck without
## changing asset paths.

const API_VERSION := 1

var saves: WorldSaveService
var stations: BlockEntityService
var inventory_commands: InventoryCommandService
var item_instances: ItemInstanceService
var entities: EntityRegistry
var content: ContentRegistry
var events: EventBus
var world_generation: WorldGenerationPipeline
var world: VoxelWorldService
var edits: WorldEditService
var crafting: CraftingService
var storage: ModStorage

var mod_id := ""
var mod_version := ""
var root_path := ""


func _init(
	p_content: ContentRegistry,
	p_events: EventBus,
	p_world_generation: WorldGenerationPipeline,
	p_world: VoxelWorldService,
	p_edits: WorldEditService,
	p_crafting: CraftingService,
	p_mod_id: String = "",
	p_mod_version: String = "",
	p_root_path: String = ""
) -> void:
	content = p_content
	events = p_events
	world_generation = p_world_generation
	world = p_world
	edits = p_edits
	crafting = p_crafting
	mod_id = p_mod_id
	mod_version = p_mod_version
	root_path = p_root_path
	if not mod_id.is_empty():
		storage = ModStorage.new(mod_id)


func register_block(definition: Dictionary) -> int:
	return content.register_block(definition)


func register_item(definition: Dictionary) -> bool:
	return content.register_item(definition)


func register_recipe(
	recipe_id: String,
	output_id: String,
	count: int,
	ingredients: Dictionary,
	options: Dictionary = {}
) -> bool:
	return content.register_recipe(recipe_id, output_id, count, ingredients, options)


func register_worldgen_stage(
	stage_id: String,
	order: int,
	callback: Callable
) -> bool:
	return world_generation.register_stage(stage_id, order, callback)

func configure_recipe(recipe_id: String, options: Dictionary) -> bool:
	return content.configure_recipe(recipe_id, options)

func configure_item_properties(item_id: String, properties: Dictionary) -> bool:
	return content.configure_item_properties(item_id, properties)


func on(event_name: String, callback: Callable, priority: int = 0) -> void:
	events.subscribe(event_name, callback, priority)


func off(event_name: String, callback: Callable) -> void:
	events.unsubscribe(event_name, callback)


func asset(relative_path: String) -> String:
	if relative_path.begins_with("res://") or relative_path.begins_with("user://"):
		return relative_path
	if root_path.is_empty():
		return relative_path
	return root_path.path_join(relative_path)


func load_asset(relative_path: String):
	return load(asset(relative_path))


func save_storage() -> bool:
	if storage == null:
		return false
	return storage.save()


func log(message: String) -> void:
	if mod_id.is_empty():
		print("[Mod] ", message)
	else:
		print("[Mod:%s] %s" % [mod_id, message])
