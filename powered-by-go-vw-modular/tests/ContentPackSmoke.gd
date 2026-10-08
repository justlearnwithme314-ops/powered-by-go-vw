extends Node


func _ready() -> void:
	var registry := ContentRegistry.new()
	assert(registry.register_item({"id": "core:stick", "display_name": "Stick", "stack_size": 64, "tags": ["material"]}))
	var events := EventBus.new()
	var world := VoxelWorldService.new(registry, events)
	var api := ModAPI.new(registry, events, null, world, null, null, "tests:content_pack", "1.0.0", "res://tests/fixtures/content_pack")
	var loader := ContentPackLoader.new()
	var invalid := loader.register_pack(api, "invalid.json")
	assert(not invalid.success)
	assert(not registry.has_block("test:partial"))
	assert(not registry.has_block("test:missing_texture"))
	assert(not registry.has_item("test:token"))

	var loaded := loader.register_pack(api, "valid.json")
	assert(loaded.success, str(loaded.errors))
	assert(registry.has_block("test:catalog_block"))
	assert(registry.has_item("test:token"))
	assert(registry.get_item("test:catalog_block").place_block == "test:catalog_block")
	assert(registry.get_item("test:token").icon is Texture2D)
	assert(registry.get_recipe("test:token_recipe").output == "test:token")
	assert(loaded.registered.blocks == ["test:catalog_block"])
	assert(loaded.registered.items == ["test:token"])
	assert(loaded.registered.recipes == ["test:token_recipe"])

	var duplicate := loader.register_pack(api, "valid.json")
	assert(not duplicate.success)
	print("Content pack smoke passed: validation atomicity, cube registration, items, recipes")
	get_tree().quit()
